"""See what Inkscape draws: export an SVG as a PNG through Inkscape's command line, which renders as the application
does, on white.

Usage:  python inkscape_png.py <chart.svg> <out.png> [--width PX]
        python inkscape_png.py --plan

It exports with Inkscape 1.4.2 or later. Inkscape 1.2, which Ubuntu 24.04 and Debian 12 ship, and 1.4.0, which
Debian 13 ships, drop Mermaid's whole stylesheet and draw its charts broken (lesson 27); 1.4.1 was never released.
It runs the program INKSCAPE names, as it is, when that is set. Otherwise it takes the first it finds: on PATH, where
on Windows the console build, inkscape.com, comes first; in Inkscape's bin folder on Windows; in the app bundle on
macOS; or in Snap's folder or Flatpak on Linux.

It prints the PNG's path and exits 0 once the PNG is in place, and exits 1 when the export fails. Without Inkscape
1.4.2 or later it lists lesson 4's install commands for this platform and exits 2. Nothing else exits 2: a usage
error exits 1.

Inkscape writes into a folder beside the PNG, and the PNG moves into place once it is whole, so a viewer never reads
half a file, and a failed export leaves the old PNG as it was and nothing else behind.

With --plan instead of the two paths, it exports nothing and prints JSON: the floor; the Inkscape it would use, or
why none will do; the one install command it chose for this machine and why, or why it chose none; and the rows a
person could choose from. Windows takes the first package manager present in lesson 4's order, so winget when it is
there. On Linux, apt, dnf and zypper are asked which Inkscape they offer: 1.4.2 or later takes the plain package;
otherwise Ubuntu takes Inkscape's PPA, and others Flatpak.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Callable, Iterator, Mapping, Optional

VARIABLE = "INKSCAPE"
MINIMUM = (1, 4, 2)  # lesson 27: Inkscape 1.2 and 1.4.0 drop Mermaid's stylesheet, and 1.4.1 was never released
WIDTH = 2000  # pixels, as in lesson 5
FLATPAK_APP = "org.inkscape.Inkscape"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
VERSION_TIMEOUT = 120  # seconds; Inkscape's first start builds its font cache
EXPORT_TIMEOUT = 300
TAIL = 20  # lines of Inkscape's output shown when an export fails


def dotted(numbers: tuple) -> str:
    """A version's numbers as Inkscape writes them, as 1.4.2."""
    return ".".join(str(number) for number in numbers)


FLOOR = dotted(MINIMUM)


@dataclasses.dataclass(frozen=True)
class Install:
    """A row of lesson 4's table: how to install Inkscape with one package manager."""
    platform: str  # as sys.platform names it
    system: str  # as the table names it
    manager: str
    tool: str  # the package manager's command, looked for on PATH
    commands: tuple  # run in this order


INSTALLS = (
    Install("win32", "Windows", "winget", "winget", ("winget install --id Inkscape.Inkscape -e",)),
    Install("win32", "Windows", "Chocolatey", "choco", ("choco install inkscape",)),
    Install("win32", "Windows", "Scoop", "scoop", ("scoop bucket add extras", "scoop install extras/inkscape")),
    Install("darwin", "macOS", "Homebrew", "brew", ("brew install --cask inkscape",)),
    Install("linux", "Ubuntu", "apt, with Inkscape's PPA", "apt",
            ("sudo add-apt-repository ppa:inkscape.dev/stable", "sudo apt install inkscape")),
    Install("linux", f"apt offering {FLOOR} or later", "apt", "apt", ("sudo apt install inkscape",)),
    Install("linux", "Debian 12 and 13", "apt, then Flatpak", "apt",
            ("sudo apt install flatpak",
             "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo",
             "flatpak install flathub org.inkscape.Inkscape")),
    Install("linux", "Fedora", "dnf", "dnf", ("sudo dnf install inkscape",)),
    Install("linux", "Arch", "pacman", "pacman", ("sudo pacman -S inkscape",)),
    Install("linux", "openSUSE", "zypper", "zypper", ("sudo zypper install inkscape",)),
    Install("linux", "Any Linux", "Flatpak", "flatpak", ("flatpak install flathub org.inkscape.Inkscape",)),
    Install("linux", "Any Linux", "Snap", "snap", ("sudo snap install inkscape",)),
)


class NoInkscape(Exception):
    """There is no Inkscape at the floor or later to export with. notes says what was found that won't do; configured is true
    when INKSCAPE named the program, so the fix is there rather than in an install."""

    def __init__(self, notes: list, configured: bool = False):
        super().__init__("; ".join(notes) or "there is no Inkscape")
        self.notes = list(notes)
        self.configured = configured


class ExportError(Exception):
    """The PNG could not be written; the message says why."""


def read_os_release(path: str = "/etc/os-release") -> dict:
    """A Linux distribution's /etc/os-release as a map from key to value, or {} where there is none."""
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError:
        return {}
    values = {}
    for line in text.splitlines():
        key, equals, value = line.partition("=")
        if equals and key.strip() and not key.lstrip().startswith("#"):
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


@dataclasses.dataclass(frozen=True)
class Host:
    """What finding and running Inkscape reaches outside Python: the environment, the home folder, PATH, processes,
    the platform, and on Linux which distribution it is."""
    environ: Mapping[str, str]
    home: pathlib.Path
    which: Callable[[str], Optional[str]]
    run: Callable[..., subprocess.CompletedProcess]
    platform: str
    os_release: Callable[[], Mapping[str, str]] = read_os_release

    @classmethod
    def real(cls) -> "Host":
        return cls(os.environ, pathlib.Path.home(), shutil.which, subprocess.run, sys.platform)


@dataclasses.dataclass(frozen=True)
class Inkscape:
    """How to run an Inkscape, as the start of a command line, and the version it reported."""
    command: tuple
    version: str


def absolute(path) -> pathlib.Path:
    """path made absolute from the working folder, then resolved: Inkscape gets every path whole."""
    return pathlib.Path(os.path.abspath(path)).resolve()


def call(host: Host, command, timeout: float) -> subprocess.CompletedProcess:
    """Run command with nothing on its input and its output captured as text. No shell reads its arguments."""
    return host.run(list(command), capture_output=True, text=True, encoding="utf-8", errors="replace",
                    stdin=subprocess.DEVNULL, timeout=timeout, check=False)


# Finding Inkscape.

def console_build(program: str, platform: str) -> str:
    """program, or on Windows the inkscape.com beside an inkscape.exe: the console build, which shows Inkscape's
    messages (lesson 5)."""
    path = pathlib.Path(program)
    if platform == "win32" and path.suffix.lower() == ".exe":
        console = path.with_suffix(".com")
        if console.is_file():
            return str(console)
    return program


def usual_programs(host: Host) -> list:
    """Where Inkscape's program is when it isn't on PATH, in the order to try: on Windows its bin folder under Program
    Files, then under Programs in LOCALAPPDATA, where an install for one user may go; on macOS the app bundle, in
    /Applications and then in the home folder's Applications; on Linux, Snap's folder."""
    if host.platform == "win32":
        roots = [host.environ.get(name, "").strip() for name in ("ProgramFiles", "ProgramW6432", "ProgramFiles(x86)")]
        folders = [pathlib.Path(root) / "Inkscape" / "bin" for root in roots if root]
        local = host.environ.get("LOCALAPPDATA", "").strip()
        if local:
            folders.append(pathlib.Path(local) / "Programs" / "Inkscape" / "bin")
        return [folder / name for folder in dict.fromkeys(folders) for name in ("inkscape.com", "inkscape.exe")]
    if host.platform == "darwin":
        bundle = pathlib.Path("Inkscape.app", "Contents", "MacOS", "inkscape")
        return [pathlib.Path("/Applications") / bundle, host.home / "Applications" / bundle]
    if host.platform == "linux":
        return [pathlib.Path("/snap/bin/inkscape")]
    return []


def flatpak_has_inkscape(host: Host, flatpak: str) -> bool:
    try:
        return call(host, [flatpak, "info", FLATPAK_APP], VERSION_TIMEOUT).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def places(host: Host) -> Iterator[tuple]:
    """Commands that may run Inkscape, in the order to try: PATH, where on Windows the console build comes first; the
    usual install folders; then Flatpak on Linux. Each is looked at only when those before it won't do, so Flatpak is
    asked only when nothing else is there."""
    for name in ("inkscape.com", "inkscape") if host.platform == "win32" else ("inkscape",):
        found = host.which(name)
        if found:
            yield (console_build(found, host.platform),)
    for program in usual_programs(host):
        if program.is_file():
            yield (str(program),)
    if host.platform == "linux":
        flatpak = host.which("flatpak")
        if flatpak and flatpak_has_inkscape(host, flatpak):
            yield (flatpak, "run", FLATPAK_APP)


def version_of(host: Host, command: tuple) -> Optional[tuple]:
    """The version command reports as Inkscape's, as its text and its major, minor and patch numbers, or None when
    it doesn't say, or doesn't start. A missing patch is 0: Inkscape 1.4.0 calls itself 1.4."""
    try:
        result = call(host, [*command, "--version"], VERSION_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"\bInkscape ((\d+)\.(\d+)(?:\.(\d+))?\S*)", f"{result.stdout or ''}\n{result.stderr or ''}")
    if not match:
        return None
    return match.group(1), tuple(int(part or 0) for part in match.group(2, 3, 4))


def checked(host: Host, command: tuple) -> Inkscape:
    """command as an Inkscape to export with, or NoInkscape saying why it won't do."""
    shown = " ".join(command)
    version = version_of(host, command)
    if version is None:
        raise NoInkscape([f"{shown} did not say which Inkscape it is"])
    text, numbers = version
    if numbers < MINIMUM:
        raise NoInkscape([f"{shown} is Inkscape {text}, and Mermaid's SVGs need {FLOOR} or later (lesson 27)"])
    return Inkscape(tuple(command), text)


def find(host: Optional[Host] = None) -> Inkscape:
    """The Inkscape to export with: the program INKSCAPE names when it is set, else the first Inkscape at the floor
    or later in places(). NoInkscape says what was found that won't do."""
    host = host or Host.real()
    chosen = host.environ.get(VARIABLE, "").strip()
    if chosen:
        path = pathlib.Path(chosen).expanduser()
        program = str(path) if path.is_file() else host.which(chosen)
        if program is None:
            raise NoInkscape([f"{VARIABLE} is set to {chosen}, which is not a program"], configured=True)
        try:
            return checked(host, (program,))
        except NoInkscape as error:
            raise NoInkscape(error.notes, configured=True) from None
    notes, tried = [], set()
    for command in places(host):
        key = (os.path.normcase(os.path.abspath(command[0])), *command[1:])
        if key in tried:
            continue
        tried.add(key)
        try:
            return checked(host, command)
        except NoInkscape as error:
            notes.extend(error.notes)
    raise NoInkscape(notes)


def install_lines(host: Host) -> list:
    """Lesson 4's installs for this platform as aligned lines: those whose package manager is on PATH, or all of them
    when none is."""
    rows = [row for row in INSTALLS if row.platform == host.platform]
    rows = [row for row in rows if host.which(row.tool)] or rows
    if not rows:
        return []
    systems, managers = max(len(row.system) for row in rows), max(len(row.manager) for row in rows)
    return [f"  {row.system:<{systems}}  {row.manager:<{managers}}  {', then '.join(row.commands)}" for row in rows]


def no_inkscape_message(error: NoInkscape, host: Host) -> str:
    lines = [f"inkscape_png: {note}." for note in error.notes]
    if error.configured:
        lines.append(f"inkscape_png: point {VARIABLE} at Inkscape {FLOOR} or later, or unset it.")
        return "\n".join(lines)
    lines.append(f"inkscape_png: there is no Inkscape {FLOOR} or later on PATH or where it usually installs.")
    table = install_lines(host)
    if table:
        lines.append("It installs with:")
        lines.extend(table)
    lines.append(f"It also installs from https://inkscape.org. To use one installed elsewhere, set {VARIABLE} to its "
                 f"program.")
    return "\n".join(lines)


# Planning an install, for a setup that offers one.

# Per Linux package manager that can say which Inkscape it offers: its plain install command, the query that says,
# and a pattern whose three groups are the offered version's major, minor and patch numbers, the patch optional. An
# epoch before them is read past, and a packaging revision after them is not a patch: Debian 13's 1.4-6 is 1.4.0.
PLAIN_LINUX = {
    "apt": ("sudo apt install inkscape", ("apt-cache", "policy", "inkscape"),
            r"Candidate:\s*(?:\d+:)?(\d+)\.(\d+)(?:\.(\d+))?"),
    "dnf": ("sudo dnf install inkscape", ("dnf", "info", "--quiet", "inkscape"),
            r"(?m)^Version\s*:\s*(\d+)\.(\d+)(?:\.(\d+))?"),
    "zypper": ("sudo zypper install inkscape", ("zypper", "--non-interactive", "info", "inkscape"),
               r"(?m)^Version\s*:\s*(?:\d+:)?(\d+)\.(\d+)(?:\.(\d+))?"),
}


def row_named(system: str, manager: Optional[str] = None) -> Install:
    return next(row for row in INSTALLS if row.system == system and manager in (None, row.manager))


def offered_version(host: Host, manager: str) -> Optional[tuple]:
    """The newest Inkscape a Linux package manager offers, as (major, minor, patch), or None when it offers none or
    can't be asked."""
    _, query, pattern = PLAIN_LINUX[manager]
    program = host.which(query[0])
    if program is None:
        return None
    try:
        result = call(host, [program, *query[1:]], VERSION_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    found = re.findall(pattern, f"{result.stdout or ''}\n{result.stderr or ''}")
    return max(tuple(int(part or 0) for part in parts) for parts in found) if found else None


def choose_linux(host: Host) -> tuple:
    """The Linux install row for this machine and why: the plain package when the package manager offers the floor
    or later; otherwise Inkscape's PPA on Ubuntu, and Flatpak elsewhere. A table of releases would be out of date by
    the next one, so the package manager is asked instead."""
    distribution = {str(key): str(value) for key, value in (host.os_release() or {}).items()}
    name = distribution.get("PRETTY_NAME") or distribution.get("ID") or "this distribution"
    for manager, (plain, _, _) in PLAIN_LINUX.items():
        if not host.which(manager):
            continue
        version = offered_version(host, manager)
        if version and version >= MINIMUM:
            return (next(row for row in INSTALLS if row.commands == (plain,)),
                    f"{manager} offers Inkscape {dotted(version)} on {name}")
        older = (f"{manager} offers Inkscape {dotted(version)}, older than {FLOOR}" if version
                 else f"{manager} offers no Inkscape")
        if manager == "apt" and distribution.get("ID", "").lower() == "ubuntu":
            return row_named("Ubuntu"), f"{older}, so Inkscape's PPA"
        if manager == "apt":
            return row_named("Debian 12 and 13"), f"{older}, so Flatpak, installed through apt"
        if host.which("flatpak"):
            return row_named("Any Linux", "Flatpak"), f"{older}, so Flatpak"
        return None, f"{older}, and there is no Flatpak to fall back on"
    return None, "there is no apt, dnf or zypper to ask which Inkscape it offers"


def choose_install(host: Host) -> tuple:
    """The one install row for this machine and why, or None and why not. Elsewhere than Linux it is the first row
    whose package manager is present, in lesson 4's order, so winget on Windows when it is there."""
    if host.platform == "linux":
        return choose_linux(host)
    rows = [row for row in INSTALLS if row.platform == host.platform]
    present = [row for row in rows if host.which(row.tool)]
    if present:
        return present[0], f"{present[0].manager} is present"
    if rows:
        return None, f"none of {', '.join(row.manager for row in rows)} is present"
    return None, f"lesson 4 has no install for {host.platform}"


def install_plan(host: Optional[Host] = None) -> dict:
    """What a setup needs to offer Inkscape, as data, the floor among it. It installs nothing, and asks no package
    manager anything when an Inkscape at the floor or later is already there."""
    host = host or Host.real()

    def shown(row: Optional[Install]) -> Optional[dict]:
        return None if row is None else {"system": row.system, "manager": row.manager, "commands": list(row.commands)}

    rows = [row for row in INSTALLS if row.platform == host.platform]
    candidates = [row for row in rows if host.which(row.tool)] or rows
    report = {"platform": host.platform, "minimum": FLOOR, "found": None, "notes": [], "configured": False,
              "chosen": None, "reason": "", "candidates": [shown(row) for row in candidates]}
    try:
        inkscape = find(host)
    except NoInkscape as error:
        report["notes"], report["configured"] = error.notes, error.configured
    else:
        report["found"] = {"command": list(inkscape.command), "version": inkscape.version}
        report["reason"] = f"Inkscape {inkscape.version} is already there"
        return report
    if report["configured"]:
        report["reason"] = f"{VARIABLE} names the program to use: fix it there, rather than install another"
        return report
    chosen, report["reason"] = choose_install(host)
    report["chosen"] = shown(chosen)
    return report


# Exporting.

def export_command(inkscape: Inkscape, svg, png, width: int = WIDTH) -> list:
    """Lesson 5's export: png, width pixels wide, on an opaque white background, which a PNG lacks without both of
    the background options."""
    return [*inkscape.command, str(svg), "--export-type=png", f"--export-filename={png}", f"--export-width={width}",
            "--export-background=white", "--export-background-opacity=1"]


def paths(svg, png) -> tuple:
    """svg and png made absolute, or ExportError when there is no SVG or no folder to write the PNG in."""
    svg, png = absolute(svg), absolute(png)
    if not svg.is_file():
        raise ExportError(f"there is no SVG at {svg}")
    if not png.parent.is_dir():
        raise ExportError(f"there is no folder {png.parent} to write the PNG in")
    return svg, png


def is_png(path: pathlib.Path) -> bool:
    try:
        with open(path, "rb") as file:
            return file.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE
    except OSError:
        return False


def tail(result: subprocess.CompletedProcess) -> str:
    lines = f"{result.stdout or ''}\n{result.stderr or ''}".strip().splitlines()
    return "\n".join(lines[-TAIL:]) if lines else "(nothing)"


def export(inkscape: Inkscape, svg, png, width: int = WIDTH, host: Optional[Host] = None) -> None:
    """Export svg as png through inkscape, as lesson 5 does. Inkscape writes into a folder beside png, and the PNG
    moves into place in one step once it is one; ExportError says what failed."""
    host = host or Host.real()
    svg, png = paths(svg, png)
    try:
        scratch = pathlib.Path(tempfile.mkdtemp(prefix=".png-", dir=png.parent))
    except OSError as error:
        raise ExportError(f"could not write in {png.parent}: {error}") from None
    try:
        written = scratch / "chart.png"
        try:
            result = call(host, export_command(inkscape, svg, written, width), EXPORT_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise ExportError(f"Inkscape had not finished after {EXPORT_TIMEOUT} s") from None
        except OSError as error:
            raise ExportError(f"Inkscape did not start: {error}") from None
        if result.returncode != 0:
            raise ExportError(f"Inkscape exited with {result.returncode}. It printed:\n{tail(result)}")
        if not is_png(written):
            raise ExportError(f"Inkscape wrote no PNG. It printed:\n{tail(result)}")
        try:
            os.replace(written, png)  # fails on Windows while a viewer holds the old PNG open
        except OSError as error:
            raise ExportError(f"could not write {png}: {error}") from None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def printable(text: str, stream) -> str:
    """text as stream's encoding can hold it, with each character it lacks escaped. A console's code page, such as
    Windows' cp1252 when stdout is a pipe, lacks most of Unicode, and the PNG is in place before its path prints."""
    encoding = getattr(stream, "encoding", None) or "utf-8"
    return text.encode(encoding, "backslashreplace").decode(encoding)


class Arguments(argparse.ArgumentParser):
    """argparse, but a usage error exits 1, so that exit 2 means only that there is no Inkscape to export with."""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, f"{self.prog}: error: {message}\n")


def pixels(text: str) -> int:
    value = int(text) if text.strip().isdigit() else 0
    if value < 1:
        raise argparse.ArgumentTypeError(f"{text!r} is not a width in pixels")
    return value


def main(argv: Optional[list] = None, host: Optional[Host] = None) -> int:
    host = host or Host.real()
    parser = Arguments(prog="inkscape_png.py", description=__doc__,
                       formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("svg", nargs="?", help="the SVG to export")
    parser.add_argument("png", nargs="?", help="the PNG to write")
    parser.add_argument("--width", type=pixels, default=WIDTH, metavar="PX",
                        help=f"the PNG's width in pixels (default {WIDTH})")
    parser.add_argument("--plan", action="store_true",
                        help="export nothing; print, as JSON, the Inkscape to use or the install chosen for this machine")
    args = parser.parse_args(argv)
    if args.plan:
        print(json.dumps(install_plan(host), indent=1))
        return 0
    if args.svg is None or args.png is None:
        parser.error("the SVG to export and the PNG to write are both needed, unless --plan is given")
    try:
        paths(args.svg, args.png)  # a wrong path is reported before any search for Inkscape
    except ExportError as error:
        print(f"inkscape_png: {error}", file=sys.stderr)
        return 1
    try:
        inkscape = find(host)
    except NoInkscape as error:
        print(no_inkscape_message(error, host), file=sys.stderr)
        return 2
    try:
        export(inkscape, args.svg, args.png, args.width, host)
    except ExportError as error:
        print(f"inkscape_png: {error}", file=sys.stderr)
        return 1
    print(printable(str(pathlib.Path(args.png)), sys.stdout))
    return 0


if __name__ == "__main__":
    sys.exit(main())
