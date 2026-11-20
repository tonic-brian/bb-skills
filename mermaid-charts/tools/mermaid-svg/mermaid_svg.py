"""Turn a Mermaid chart into an SVG that Inkscape and browsers both draw, with pinned tools and a pinned browser.

Usage:
  python mermaid_svg.py setup  [--install-dir DIR]
  python mermaid_svg.py check  [--install-dir DIR]
  python mermaid_svg.py plan   [--install-dir DIR]
  python mermaid_svg.py render IN.mmd OUT.svg [--install-dir DIR] [--config FILE]

From Python, with this folder on sys.path:
  import mermaid_svg
  notes = mermaid_svg.render("chart.mmd", "chart.svg")  # NotInstalled or RenderError when it can't

`setup` installs the pins in this folder: mermaid-cli and Puppeteer from the npm registry, then the one browser they
render with, the chrome-headless-shell build that Puppeteer pins, from Google's Chrome for Testing storage. It says
what it fetches, and from where, before each download, and it proves the install with a two-node render. Run it again
whenever you like: while the install matches the pins it does nothing.

`plan` installs nothing and prints JSON for a setup that offers to install: the install's state, the Node.js on PATH
and whether it will do, and the command that installs Node.js on this platform, where there is one to run.

The install goes in ~/.mermaid-svg/, or in MERMAID_SVG_HOME, an absolute path, or in
--install-dir. It needs Node.js 22.13 or newer, and records the one it checked: every render runs that Node on
mermaid-cli's own script, never through a shell. `check` says whether the install is there and matches the pins.

`render` draws labels as SVG text in Mermaid's classic look, at the chart's own size, and marks the root
xml:space="preserve", so Inkscape draws the chart's shapes and labels as a browser does. On the same platform, the
same chart and pins give the same bytes.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ElementTree
from typing import Callable, Mapping, Optional

HERE = pathlib.Path(__file__).resolve().parent
# Copied into the install folder. Together they are the install's identity: when one changes, `setup` proves the
# install again, and `render` and `check` say it is out of date.
PIN_FILES = ("package.json", "package-lock.json", ".puppeteerrc.cjs", "browser-plan.mjs")
# Read from this folder at each render, so a change to it needs no new install. It draws labels as SVG text, not as
# HTML in a <foreignObject>, which Inkscape doesn't draw; in the classic look, whose shapes Inkscape does draw; without
# useMaxWidth, which gives the SVG a width of 100% and no height, so a browser shrinks a tall chart to fit its window;
# and it wraps labels at 240 px, not 120, since a word too wide for its line is split mid-word. It also seeds the shapes
# Mermaid draws by hand, such as the stadium, which would otherwise differ at each render.
CONFIG = HERE / "mermaid-config.json"
STAMP = "installed.json"
LOCK = "setup.lock"
HOME_VARIABLE = "MERMAID_SVG_HOME"
MERMAID_CLI = ("@mermaid-js/mermaid-cli", "mmdc")
PUPPETEER = ("puppeteer", "puppeteer")
MINIMUM_NODE = (22, 13)
NODE_INSTALL = {"win32": "winget install --exact --id OpenJS.NodeJS.LTS", "darwin": "brew install node"}
PLAN_KEYS = ("browser", "buildId", "platform", "url", "cacheDirectory", "installPath", "executablePath",
             "skipsChrome", "skipsFirefox")
PROOF = 'flowchart LR\n  one["proof one"] --> two["proof two"]\n'
SVG = "{http://www.w3.org/2000/svg}"
XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"
QUERY_TIMEOUT = 120  # seconds, for a call that only answers a question
RENDER_TIMEOUT = 300  # mermaid-cli and Puppeteer time out sooner on their own; this stops a render that never returns
MOVE_ATTEMPTS = 30  # seconds, on Windows, for a scanner to let go of a browser just unpacked


class RenderError(Exception):
    """The SVG could not be written; the message says why."""


class NotInstalled(RenderError):
    """There is no proven install to render with; the message says how to make one."""


class SetupError(Exception):
    """The setup stopped; the message says why."""


# The install folder and what is in it.

def absolute(path) -> pathlib.Path:
    """path made absolute from the working folder, then resolved. Node runs in the install folder, so every path it
    gets must be absolute, and Python 3.9's resolve() leaves a relative path relative on Windows when it doesn't
    exist yet."""
    return pathlib.Path(os.path.abspath(path)).resolve()


def install_folder(install_dir: Optional[str] = None, environ: Optional[Mapping[str, str]] = None,
                   home: Optional[pathlib.Path] = None) -> pathlib.Path:
    """install_dir when given, then MERMAID_SVG_HOME, which must be absolute, then ~/.mermaid-svg."""
    if install_dir is not None and str(install_dir).strip():
        return absolute(pathlib.Path(install_dir).expanduser())
    environ = os.environ if environ is None else environ
    variable = environ.get(HOME_VARIABLE, "").strip()
    if variable:
        path = pathlib.Path(variable).expanduser()
        if not path.is_absolute():
            # A relative path would name a different folder from every working directory.
            raise ValueError(f"{HOME_VARIABLE} must be an absolute path, not {variable!r}")
        return absolute(path)
    return (pathlib.Path.home() if home is None else home) / ".mermaid-svg"


def pins_digest(folder: pathlib.Path = HERE) -> str:
    """The SHA-256 of the pin files, each taken by name, length and bytes."""
    digest = hashlib.sha256()
    for name in PIN_FILES:
        content = (folder / name).read_bytes()
        digest.update(f"{name}\0{len(content)}\0".encode("utf-8"))
        digest.update(content)
    return digest.hexdigest()


def package_script(install: pathlib.Path, package: str, command: str) -> Optional[pathlib.Path]:
    """The script an installed package runs as command, from its package.json, or None when it isn't installed."""
    folder = install / "node_modules" / package
    try:
        declared = json.loads((folder / "package.json").read_text(encoding="utf-8")).get("bin")
    except (OSError, ValueError, AttributeError):
        return None
    relative = declared if isinstance(declared, str) else (declared or {}).get(command)
    if not isinstance(relative, str):
        return None
    script = (folder / relative).resolve()
    return script if script.is_file() else None


def packages_current(install: pathlib.Path) -> bool:
    """Whether node_modules holds exactly what package-lock.json pins, as npm recorded when it installed them.
    Optional packages for other platforms are missing by design, and "libc" is not compared: npm 10.9.9 on Linux
    leaves it out of its record of a package the lockfile gives one."""
    try:
        locked = json.loads((install / "package-lock.json").read_text(encoding="utf-8"))["packages"]
        installed = json.loads((install / "node_modules" / ".package-lock.json").read_text(encoding="utf-8"))
        installed = installed["packages"]
    except (OSError, ValueError, KeyError, TypeError):
        return False
    if package_script(install, *MERMAID_CLI) is None or package_script(install, *PUPPETEER) is None:
        return False
    locked = {key: entry for key, entry in locked.items() if key}
    if set(installed) - set(locked):
        return False
    def comparable(entry: dict) -> dict:
        return {field: value for field, value in entry.items() if field != "libc"}
    return all(comparable(installed[key]) == comparable(entry) if key in installed else entry.get("optional") is True
               for key, entry in locked.items())


def node_environment(environ: Optional[Mapping[str, str]] = None) -> dict[str, str]:
    """This environment without a PUPPETEER_ variable. Each would override the install folder's .puppeteerrc.cjs,
    which then alone decides which browser runs and where it lives."""
    environ = os.environ if environ is None else environ
    return {key: value for key, value in environ.items() if not key.upper().startswith("PUPPETEER_")}


def flush_output() -> None:
    """Send out what this process has printed. A child process writes to the same console or pipe straight away,
    while Python holds its own output back when stdout is a pipe, so without this the child's lines come out first."""
    sys.stdout.flush()
    sys.stderr.flush()


def read_stamp(install: pathlib.Path) -> Optional[dict]:
    """What the setup recorded when it proved the install, or None when it never finished."""
    try:
        stamp = json.loads((install / STAMP).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return stamp if isinstance(stamp, dict) else None


def status(install: pathlib.Path) -> str:
    """'missing' without a proven install, or when its Node, packages, browser or own copies of the pins have changed
    or gone; 'stale' when it was installed from other pins than these; otherwise 'current'. The stamp names the
    browser relative to the install, so a moved install stays current. It raises OSError when this tool's own pins
    can't be read."""
    stamp = read_stamp(install)
    if stamp is None or not packages_current(install):
        return "missing"
    node, executable = stamp.get("node"), stamp.get("executable")
    if not isinstance(node, str) or not pathlib.Path(node).is_file():
        return "missing"
    if not isinstance(executable, str) or not (install / executable).is_file():
        return "missing"
    try:
        intact = pins_digest(install) == stamp.get("pins")
    except OSError:
        intact = False
    if not intact:
        # Without the install's own .puppeteerrc.cjs, Puppeteer would look for its settings, and a browser, elsewhere.
        return "missing"
    return "current" if stamp["pins"] == pins_digest() else "stale"


def shell_word(path) -> str:
    """A path as one word on a command line. It is written with forward slashes, which Windows takes too, since bash
    reads a backslash as an escape; and it is quoted only when it has to be, since PowerShell won't run a quoted first
    word. A path without spaces or special characters then pastes as it is into PowerShell, bash or zsh."""
    text = (path if isinstance(path, pathlib.PurePath) else pathlib.PurePath(path)).as_posix()
    return f'"{text}"' if re.search(r"[\s\"'&|;<>()$`^%!*?\[\]{}#~]", text) else text


def setup_command(install: pathlib.Path, explicit: bool) -> str:
    folder = f" --install-dir {shell_word(install)}" if explicit else ""
    return f"{shell_word(sys.executable)} {shell_word(HERE / 'mermaid_svg.py')} setup{folder}"


# Rendering.

def parse_svg(content: bytes) -> ElementTree.Element:
    """The root of an SVG, or RenderError when content isn't one."""
    try:
        root = ElementTree.fromstring(content)
    except ElementTree.ParseError as error:
        raise RenderError(f"mermaid-cli wrote an SVG that does not parse: {error}") from None
    if root.tag != f"{SVG}svg":
        raise RenderError(f"mermaid-cli wrote {root.tag}, not an SVG")
    return root


def keep_spaces(content: bytes) -> bytes:
    """The SVG with xml:space="preserve" on its root. In Mermaid's text labels each word after the first starts with a
    space, in a <tspan> of its own, and Inkscape drops that space unless told to keep it. Browsers draw it the same
    either way. mermaid-cli writes the root <svg> first, and nothing else changes, so a render stays the same bytes."""
    if parse_svg(content).get(XML_SPACE) is not None:
        return content
    start = content.find(b"<svg")
    if start < 0 or content[:start].strip():
        raise RenderError("mermaid-cli's SVG does not start with its root <svg>")
    kept = content[:start + 4] + b' xml:space="preserve"' + content[start + 4:]
    if parse_svg(kept).get(XML_SPACE) != "preserve":
        raise RenderError("could not mark the SVG's root with xml:space")
    return kept


def render_with(node: str, mmd: pathlib.Path, svg: pathlib.Path, install: pathlib.Path,
                config: pathlib.Path = CONFIG, run: Callable = subprocess.run, timeout: float = RENDER_TIMEOUT,
                environ: Optional[Mapping[str, str]] = None) -> None:
    """Render mmd as svg: node runs the install's mermaid-cli, which prints its own errors; RenderError says what
    failed.

    mmdc writes into a folder beside svg, and the result moves into place in one step, once it parses as an SVG and
    its root keeps spaces. A viewer reloading the file never reads half of one, and a failed render leaves nothing."""
    mmd, svg, config = absolute(mmd), absolute(svg), absolute(config)
    if not mmd.is_file():
        raise RenderError(f"there is no chart at {mmd}")
    if not config.is_file():
        raise RenderError(f"there is no Mermaid config at {config}")
    if not svg.parent.is_dir():
        raise RenderError(f"there is no folder {svg.parent} to write the SVG in")
    script = package_script(install, *MERMAID_CLI)
    if script is None:
        raise RenderError(f"there is no mermaid-cli in {install}")
    try:
        scratch = pathlib.Path(tempfile.mkdtemp(prefix=".svg-", dir=svg.parent))
    except OSError as error:
        raise RenderError(f"could not write in {svg.parent}: {error}") from None
    try:
        rendered = scratch / "chart.svg"  # mermaid-cli takes the format from the extension
        # Node itself, on mermaid-cli's script: an argument list that no shell reads. The working folder is the
        # install, so Puppeteer finds its .puppeteerrc.cjs there, which is why every path here is absolute.
        command = [node, str(script), "--input", str(mmd), "--output", str(rendered), "--configFile", str(config),
                   "--quiet"]
        flush_output()
        try:
            result = run(command, cwd=str(install), env=node_environment(environ), stdin=subprocess.DEVNULL,
                         timeout=timeout, check=False)
        except subprocess.TimeoutExpired:
            raise RenderError(f"mermaid-cli had not finished after {timeout:g} s") from None
        except OSError as error:
            raise RenderError(f"mermaid-cli did not start: {error}") from None
        if result.returncode != 0:
            raise RenderError(f"mermaid-cli exited with {result.returncode}")
        if not rendered.is_file() or rendered.stat().st_size == 0:
            raise RenderError("mermaid-cli wrote no SVG")
        try:
            rendered.write_bytes(keep_spaces(rendered.read_bytes()))
            os.replace(rendered, svg)  # fails if a viewer holds the old file open
        except OSError as error:
            raise RenderError(f"could not write {svg}: {error}") from None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def render(mmd_path, svg_path, *, install_dir: Optional[str] = None, config: Optional[str] = None) -> list[str]:
    """Render the Mermaid chart in mmd_path as the SVG svg_path. Returns notes worth printing, such as an install out
    of date with the pins; raises NotInstalled without an install, and RenderError when the render fails."""
    explicit = install_dir is not None and bool(str(install_dir).strip())
    try:
        install = install_folder(install_dir)
    except ValueError as error:
        raise RenderError(str(error)) from None
    try:
        state = status(install)
    except OSError as error:
        raise RenderError(f"mermaid-svg's own files are incomplete: {error}") from None
    if state == "missing":
        raise NotInstalled(f"mermaid-svg is not installed in {install}; install it with "
                           f"{setup_command(install, explicit)}")
    node = read_stamp(install)["node"]
    render_with(node, pathlib.Path(mmd_path), pathlib.Path(svg_path), install, CONFIG if config is None else config)
    if state == "stale":
        return [f"mermaid-svg in {install} was installed from other pins; update it with "
                f"{setup_command(install, explicit)}"]
    return []


# Setting up.

@dataclasses.dataclass(frozen=True)
class Host:
    """What the setup reaches outside Python: the environment, the home folder, PATH and processes."""
    environ: Mapping[str, str]
    home: pathlib.Path
    which: Callable[[str], Optional[str]]
    run: Callable[..., subprocess.CompletedProcess]
    platform: str

    @classmethod
    def real(cls) -> "Host":
        return cls(os.environ, pathlib.Path.home(), shutil.which, subprocess.run, sys.platform)


def repositories_holding(folder: pathlib.Path, home: pathlib.Path) -> list[pathlib.Path]:
    """Every repository folder sits in, nearest first: each folder at or above it with a .git, which in a worktree is
    a file. The search stops below the home folder, which some people keep as a repository of its own."""
    found = []
    for candidate in (folder, *folder.parents):
        if candidate == home:
            break
        if (candidate / ".git").exists():
            found.append(candidate)
    return found


def target_folder(install_dir: Optional[str], host: Host, here: pathlib.Path = HERE) -> pathlib.Path:
    """The folder to install into, refused when it lies inside a repository that holds this tool."""
    try:
        target = absolute(install_folder(install_dir, host.environ, host.home))
    except ValueError as error:
        raise SetupError(str(error)) from None
    for repository in repositories_holding(here, absolute(host.home)):
        if target == repository or repository in target.parents:
            raise SetupError(f"{target} is inside {repository}, a repository that holds mermaid-svg. The install "
                             f"belongs outside it: pass another --install-dir, or set {HOME_VARIABLE}.")
    return target


def foreign_contents(target: pathlib.Path) -> bool:
    """Whether target already holds something that isn't a mermaid-svg install, which the setup must not write over:
    anything but an empty folder (a setup's lock aside), or one with a stamp, or with this tool's package.json."""
    if not target.exists():
        return False
    if not target.is_dir():
        return True
    if not any(entry.name != LOCK for entry in target.iterdir()) or (target / STAMP).is_file():
        return False
    try:
        ours = json.loads((HERE / "package.json").read_text(encoding="utf-8"))["name"]
        return json.loads((target / "package.json").read_text(encoding="utf-8")).get("name") != ours
    except (OSError, ValueError, KeyError, AttributeError):
        return True


def query(host: Host, command: list, cwd: Optional[pathlib.Path] = None, env: Optional[dict] = None) -> str:
    """Run a command that answers a question, and return what it printed."""
    name = pathlib.Path(command[0]).name
    flush_output()
    try:
        result = host.run(command, cwd=None if cwd is None else str(cwd), env=env, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=QUERY_TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(f"{name} failed: {error}") from None
    if result.returncode != 0:
        raise SetupError(f"{name} exited with {result.returncode}: {(result.stderr or '').strip()}")
    return result.stdout or ""


def watch(host: Host, command: list, cwd: pathlib.Path, env: dict, what: str) -> None:
    """Run a command whose output the developer watches, such as a download, after what was printed about it."""
    flush_output()
    try:
        result = host.run(command, cwd=str(cwd), env=env, stdin=subprocess.DEVNULL, check=False)
    except OSError as error:
        raise SetupError(f"{what} did not start: {error}") from None
    if result.returncode != 0:
        raise SetupError(f"{what} failed with exit code {result.returncode}; run the setup again")


def node_version(text: str) -> Optional[tuple]:
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", text.strip())
    return tuple(int(part) for part in match.groups()) if match else None


def check_node(host: Host) -> str:
    """The node on PATH, as an absolute path, when it is new enough for mermaid-cli 12."""
    need = f"Node.js {MINIMUM_NODE[0]}.{MINIMUM_NODE[1]} or newer, which mermaid-cli 12 requires"
    command = NODE_INSTALL.get(host.platform)
    how = (f"Install it with `{command}` or from https://nodejs.org/en/download" if command
           else "Install it from https://nodejs.org/en/download")
    found = host.which("node")
    if found is None:
        raise SetupError(f"there is no Node.js on PATH. mermaid-svg needs {need}. {how}, then run this again.")
    node = str(absolute(found))
    text = query(host, [node, "--version"]).strip()
    version = node_version(text)
    if version is None or version[:2] < MINIMUM_NODE:
        raise SetupError(f"Node.js {text or '(no version)'} at {node} will not do. mermaid-svg needs {need}. {how}, "
                         f"then run this again.")
    print(f"Node.js {text}, at {node}.")
    return node


def npm_command(host: Host, node: str) -> list[str]:
    """npm as Node running npm's own script, so no shell reads its arguments: npm-cli.js beside npm.cmd on Windows, or
    the file npm links to elsewhere. An unusual layout falls back to the npm on PATH, whose arguments are fixed."""
    found = host.which("npm")
    if found is None:
        raise SetupError("npm is not on PATH. It comes with Node.js: reinstall Node.js, then run this again.")
    npm = absolute(found)
    script = npm.parent / "node_modules" / "npm" / "bin" / "npm-cli.js" if host.platform == "win32" else npm
    return [node, str(script)] if script.name == "npm-cli.js" and script.is_file() else [str(npm)]


def browser_plan(host: Host, node: str, target: pathlib.Path, env: dict) -> dict:
    """What the installed Puppeteer would fetch, and where it would put it and look for it, refused unless that is
    the headless shell inside the install folder, where mermaid-cli's launch will look for it."""
    output = query(host, [node, str(target / "browser-plan.mjs")], cwd=target, env=env)
    lines = [line for line in output.splitlines() if line.strip()]
    try:
        plan = json.loads(lines[-1])
    except (IndexError, ValueError):
        raise SetupError(f"Puppeteer's browser plan is not JSON: {output.strip()[:400]}") from None
    missing = [key for key in PLAN_KEYS if key not in plan] if isinstance(plan, dict) else list(PLAN_KEYS)
    if missing:
        raise SetupError(f"Puppeteer's browser plan lacks {', '.join(missing)}")
    cache = (target / "browsers").resolve()
    if pathlib.Path(plan["cacheDirectory"]).resolve() != cache:
        raise SetupError(f"Puppeteer would keep its browsers in {plan['cacheDirectory']}, not {cache}, so it did not "
                         f"read the install folder's .puppeteerrc.cjs")
    if cache not in pathlib.Path(plan["executablePath"]).resolve().parents:
        raise SetupError(f"Puppeteer would look for its browser at {plan['executablePath']}, outside {cache}")
    if pathlib.Path(plan["installPath"]).resolve() != pathlib.Path(plan["executablePath"]).resolve():
        raise SetupError(f"Puppeteer would install {plan['browser']} {plan['buildId']} at {plan['installPath']}, but "
                         f"mermaid-cli would launch {plan['executablePath']}")
    if plan["skipsChrome"] is not True or plan["skipsFirefox"] is not True:
        raise SetupError("Puppeteer's configuration would also download the full Chrome or Firefox; the install "
                         "holds chrome-headless-shell alone")
    return plan


def move_into_place(source: pathlib.Path, destination: pathlib.Path, platform: str,
                    pause: Callable[[float], None] = time.sleep) -> None:
    """Move a browser just unpacked into place. On Windows a scanner or indexer may hold a new file open for a while,
    and the rename fails meanwhile, so there it is retried for up to MOVE_ATTEMPTS seconds."""
    attempts = MOVE_ATTEMPTS if platform == "win32" else 1
    for attempt in range(1, attempts + 1):
        try:
            if destination.exists():
                shutil.rmtree(destination)  # what an older, interrupted install left
            os.replace(source, destination)
            return
        except PermissionError as error:
            if attempt == attempts:
                raise SetupError(f"could not move the browser from {source} to {destination}: {error}. Run the setup "
                                 f"again.") from None
            pause(1)
        except OSError as error:
            raise SetupError(f"could not move the browser from {source} to {destination}: {error}. Run the setup "
                             f"again.") from None


def install_browser(host: Host, node: str, target: pathlib.Path, plan: dict, env: dict,
                    pause: Callable[[float], None] = time.sleep) -> None:
    """Install the plan's browser build into a folder of its own, then move it into place in one step, so a download
    cut short never leaves half a browser where mermaid-cli looks for one."""
    cache = (target / "browsers").resolve()
    executable = pathlib.Path(plan["executablePath"]).resolve()
    build = executable.relative_to(cache).parts[:2]  # <browser>/<platform>-<build>, as Puppeteer's cache lays it out
    final = cache.joinpath(*build)
    if executable.is_file():
        print(f"{plan['browser']} {plan['buildId']} is already in {final}; nothing to fetch.")
        return
    script = package_script(target, *PUPPETEER)
    if script is None:
        raise SetupError(f"there is no Puppeteer in {target}")
    partial = target / "browsers.partial"
    shutil.rmtree(partial, ignore_errors=True)
    if partial.exists():
        # Puppeteer would take half a browser left there for a whole one.
        raise SetupError(f"could not clear {partial}, which an earlier download left: delete it, then run the setup "
                         f"again")
    print(f"Fetching {plan['browser']} {plan['buildId']} for {plan['platform']}, and no other browser, from "
          f"Google's Chrome for Testing storage: {plan['url']}")
    watch(host, [node, str(script), "browsers", "install", f"{plan['browser']}@{plan['buildId']}"], target,
          dict(env, PUPPETEER_CACHE_DIR=str(partial)), "Puppeteer's browser install")
    fetched = partial.joinpath(*build)
    if not (fetched / executable.relative_to(final)).is_file():
        raise SetupError(f"Puppeteer's browser install left no browser in {fetched}")
    final.parent.mkdir(parents=True, exist_ok=True)
    move_into_place(fetched, final, host.platform, pause)
    shutil.rmtree(partial, ignore_errors=True)


def prove(host: Host, node: str, target: pathlib.Path, browser: pathlib.Path) -> None:
    """Render a two-node chart the way `render` does, and check that its labels are SVG text, which Inkscape draws,
    and not HTML in a <foreignObject>, which it doesn't."""
    with tempfile.TemporaryDirectory(prefix="mermaid-svg-proof-") as scratch:
        mmd = pathlib.Path(scratch) / "proof.mmd"
        mmd.write_text(PROOF, encoding="utf-8")
        svg = mmd.with_suffix(".svg")
        try:
            render_with(node, mmd, svg, target, run=host.run, environ=host.environ)
            root = parse_svg(svg.read_bytes())
        except RenderError as error:
            raise SetupError(f"the two-node proof did not render: {error}. If {browser} is left from a download that "
                             f"was cut short, delete it and run the setup again.") from None
        if next(root.iter(f"{SVG}foreignObject"), None) is not None:
            raise SetupError("the two-node proof drew its labels as HTML, which Inkscape can't show; check that "
                             "mermaid-config.json turns off htmlLabels")
        labels = " ".join("".join(text.itertext()) for text in root.iter(f"{SVG}text"))
        if "proof one" not in labels or "proof two" not in labels:
            raise SetupError("the two-node proof's SVG does not hold its two labels as SVG text")


def size_in_mb(folder: pathlib.Path) -> float:
    total = 0
    for root, _, files in os.walk(folder):
        for name in files:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total / 1e6


def setup(install_dir: Optional[str] = None, host: Optional[Host] = None) -> None:
    """Install the pins into the install folder and prove them, or do nothing while the install matches them."""
    host = host or Host.real()
    target = target_folder(install_dir, host)
    node = check_node(host)
    npm = npm_command(host, node)
    if status(target) == "current" and pathlib.Path(read_stamp(target)["node"]) == pathlib.Path(node):
        print(f"mermaid-svg in {target} matches the pins; nothing to do.")
        return
    if foreign_contents(target):
        raise SetupError(f"{target} already holds files that aren't a mermaid-svg install, and the setup won't write "
                         f"over them. Pass an empty or new folder to --install-dir, or set {HOME_VARIABLE} to one.")
    target.mkdir(parents=True, exist_ok=True)
    lock = target / LOCK
    try:
        handle = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise SetupError(f"another setup is running in {target}. If none is, one stopped without cleaning up: delete "
                         f"{lock}, then run the setup again.") from None
    try:
        os.write(handle, f"{os.getpid()} {datetime.datetime.now().astimezone().isoformat()}\n".encode("utf-8"))
        os.close(handle)
        install_and_prove(host, target, node, npm)
    finally:
        lock.unlink(missing_ok=True)


def install_and_prove(host: Host, target: pathlib.Path, node: str, npm: list[str]) -> None:
    """The setup's work, under its lock: copy the pins, install what isn't there, prove it, and record it."""
    print(f"Installing mermaid-svg into {target}.")
    (target / STAMP).unlink(missing_ok=True)  # until the new install is proven, there is none
    for name in PIN_FILES:
        shutil.copyfile(HERE / name, target / name)
    env = node_environment(host.environ)
    pinned = json.loads((target / "package.json").read_text(encoding="utf-8"))["dependencies"]
    named = " and ".join(f"{name} {version}" for name, version in pinned.items())
    if packages_current(target):
        print(f"The npm packages in {target} already match package-lock.json ({named}); nothing to fetch.")
    else:
        registry = query(host, [*npm, "config", "get", "registry"], cwd=target, env=env).strip()
        print(f"Fetching {named}, with the packages package-lock.json pins beneath them, from the npm registry: "
              f"{registry}")
        watch(host, [*npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund"], target, env, "npm ci")

    plan = browser_plan(host, node, target, env)
    install_browser(host, node, target, plan, env)
    executable = pathlib.Path(plan["executablePath"]).resolve()
    print("Proving the install with a two-node chart.")
    prove(host, node, target, executable.parent)
    stamp = {"pins": pins_digest(target), "packages": pinned, "browser": f"{plan['browser']} {plan['buildId']}",
             "platform": plan["platform"], "executable": executable.relative_to(target.resolve()).as_posix(),
             "node": node, "installed": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}
    (target / STAMP).write_text(json.dumps(stamp, indent=1) + "\n", encoding="utf-8")
    print(f"Installed and proven: {size_in_mb(target):.0f} MB in {target}.")


def check(install_dir: Optional[str] = None, host: Optional[Host] = None) -> int:
    """Say whether the install is there and matches the pins: 0 when it does, else 1."""
    host = host or Host.real()
    try:
        install_path = install_folder(install_dir, host.environ, host.home)
        state = status(install_path)
    except (ValueError, OSError) as error:
        print(f"mermaid-svg: {error}")
        return 1
    fix = setup_command(install_path, install_dir is not None and bool(str(install_dir).strip()))
    if state == "missing":
        print(f"mermaid-svg: not installed in {install_path}; install it with {fix}")
        return 1
    if state == "stale":
        print(f"mermaid-svg: the install in {install_path} is from other pins; update it with {fix}")
        return 1
    stamp = read_stamp(install_path) or {}
    packages = ", ".join(f"{name} {version}" for name, version in (stamp.get("packages") or {}).items())
    print(f"mermaid-svg: installed in {install_path}, matching the pins: {packages}, {stamp.get('browser')}, "
          f"rendering with Node at {stamp.get('node')}")
    return 0


def node_report(host: Host) -> dict:
    """The Node.js on PATH, its version, and whether it is new enough for the setup, without stopping as check_node
    does when it isn't."""
    report = {"path": None, "version": None, "ok": False}
    found = host.which("node")
    if found is None:
        return report
    report["path"] = str(absolute(found))
    try:
        text = query(host, [report["path"], "--version"]).strip()
    except SetupError:
        return report
    version = node_version(text)
    report["version"] = text or None
    report["ok"] = version is not None and version[:2] >= MINIMUM_NODE
    return report


def plan(install_dir: Optional[str] = None, host: Optional[Host] = None) -> dict:
    """What a setup needs to offer this tool's install, as data, installing nothing: the install folder and its state
    (missing, stale, current, or error), the Node.js found and whether it will do, the minimum, and this platform's
    command that installs Node.js. That command is None on Linux, where a distribution's Node.js is often older than
    mermaid-cli needs, and nodejs.org or nvm is the advice instead."""
    host = host or Host.real()
    report = {"install": {"folder": None, "state": "error", "error": None}, "node": node_report(host),
              "minimumNode": ".".join(str(part) for part in MINIMUM_NODE),
              "nodeInstall": NODE_INSTALL.get(host.platform)}
    try:
        folder = install_folder(install_dir, host.environ, host.home)
        report["install"]["folder"] = str(folder)
        report["install"]["state"] = status(folder)
    except (ValueError, OSError) as error:
        report["install"]["error"] = str(error)
    return report


def main(argv: Optional[list] = None, host: Optional[Host] = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        # A console's code page, such as Windows' cp1252 when stdout is a pipe, lacks most of Unicode. A path it can't
        # show prints escaped, as on stderr, rather than failing, which could come after the work is done.
        sys.stdout.reconfigure(errors="backslashreplace")
    parser = argparse.ArgumentParser(prog="mermaid_svg.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    folder_help = f"the install folder (default: {HOME_VARIABLE}, else ~/.mermaid-svg)"
    for name, summary in (("setup", "install the pinned tools and browser, and prove them"),
                          ("check", "say whether the install is there and matches the pins"),
                          ("plan", "print, as JSON, what a setup would need to install; install nothing")):
        commands.add_parser(name, help=summary).add_argument("--install-dir", metavar="DIR", help=folder_help)
    drawing = commands.add_parser("render", help="render a Mermaid chart as an SVG")
    drawing.add_argument("mmd", help="the Mermaid chart to read")
    drawing.add_argument("svg", help="the SVG to write")
    drawing.add_argument("--install-dir", metavar="DIR", help=folder_help)
    drawing.add_argument("--config", metavar="FILE", help="a Mermaid config, instead of mermaid-config.json here")
    args = parser.parse_args(argv)
    if args.command == "setup":
        try:
            setup(args.install_dir, host)
        except (SetupError, OSError) as error:
            print(f"mermaid_svg setup: {error}", file=sys.stderr)
            return 1
        return 0
    if args.command == "check":
        return check(args.install_dir, host)
    if args.command == "plan":
        print(json.dumps(plan(args.install_dir, host), indent=1))
        return 0
    try:
        notes = render(args.mmd, args.svg, install_dir=args.install_dir, config=args.config)
    except RenderError as error:
        print(f"mermaid_svg render: {error}", file=sys.stderr)
        return 1
    for note in notes:
        print(f"mermaid_svg render: {note}", file=sys.stderr)
    print(pathlib.Path(args.svg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
