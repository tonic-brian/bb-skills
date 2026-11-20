"""Write each Mermaid chart in a Markdown document to its own .mmd file and, with --preview, render each to a PNG
beside it, so a document's charts can be checked one by one.

Usage:  python export_blocks.py <document.md> <out folder> [--preview] [--max-width <px>]

Each chart becomes block-NN-line-L.mmd in the out folder, NN counting the document's charts from 01 and L being the
line of its opening fence, in UTF-8 with LF line endings. The folder is made when it is missing. This tool's own files
from an earlier run, block-NN-line-L.mmd and .png, are removed first, since a chart the document has since lost would
read as current; anything else in the folder is left alone.

A fence is read as CommonMark reads one: three or more backticks or tildes, indented at most three spaces, whose info
string's first word is mermaid, in any case, where a backtick fence's info string holds no backtick; closed by a fence
of the same character, at least as long, with nothing after it but spaces or tabs. A chart loses as many spaces from
the start of each line as its fence is indented. A Mermaid example inside a longer fence is an example, not a chart,
and a fence inside a block quote, or indented four spaces or more, is not read. HTML blocks are not recognised: a fence
inside <!-- --> or <pre>, or after a <details> line with no blank line between, is read as a chart though a renderer
shows it as HTML, and a lone fence line inside one can hide the charts after it. The document is read as UTF-8, and
one that is not is refused.

--preview renders each chart with preview_png.py, beside this file, so with mermaid-svg's pinned install, as a layout
preview: block-NN-line-L.png beside its .mmd. Without an install it says how to make one, and renders nothing. It says
how wide each chart is, half its preview's width, since the preview is drawn at twice the chart's size; after the
previews, and so after any that failed, it names each chart wider than --max-width, 1250 px unless given, which on
GitHub or a projector shrinks until it can't be read (LESSONS.md, lesson 33). --max-width 0 measures without a limit.

It exits 0 once every chart is written and, with --preview, every preview rendered and none wider than the limit. It
exits 1 on a fence never closed, which leaves the rest of the document unread, on a preview that failed, on a chart
wider than the limit, and on a usage error.
"""
from __future__ import annotations

import os
import pathlib
import re
import struct
import subprocess
import sys
from typing import List, Optional, Tuple

sys.dont_write_bytecode = True
TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS / "mermaid-svg"))
sys.path.insert(0, str(TOOLS))
import mermaid_svg  # noqa: E402
import preview_png  # noqa: E402

PREVIEW = TOOLS / "preview_png.py"
MAX_WIDTH = 1250  # px: wider, a chart shrinks on GitHub or a projector until its text can't be read
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
OWN_FILE = re.compile(r"block-\d{2,}-line-\d+\.(?:mmd|png)")
OPENING = re.compile(r"( {0,3})(`{3,}|~{3,})(.*)")
CLOSING = re.compile(r" {0,3}(`{3,}|~{3,})[ \t]*")
PREVIEW_TIMEOUT = mermaid_svg.RENDER_TIMEOUT + 60  # preview_png.py stops mermaid-cli itself at RENDER_TIMEOUT
SHOWN = 6  # lines of a failed preview's output shown, from the first, where mermaid-cli says what went wrong


class Fence:
    """A fence opened and not yet closed: where it opened, its indentation, its run of fence characters, and, when it
    holds a chart, the chart's lines."""

    def __init__(self, line: int, indent: int, run: str, chart: bool):
        self.line, self.indent, self.char, self.length, self.chart = line, indent, run[0], len(run), chart
        self.body: List[str] = []

    def closed_by(self, text: str) -> bool:
        match = CLOSING.fullmatch(text)
        return bool(match) and match.group(1)[0] == self.char and len(match.group(1)) >= self.length

    def take(self, text: str) -> None:
        if self.chart:
            spaces = len(text) - len(text.lstrip(" "))
            self.body.append(text[min(spaces, self.indent):])


def opening(number: int, text: str) -> Optional[Fence]:
    """The fence a line opens, or None."""
    match = OPENING.fullmatch(text)
    if not match:
        return None
    indent, run, info = match.groups()
    if run[0] == "`" and "`" in info:
        return None
    # The first word ends at ASCII whitespace alone, as GitHub's cmark reads it: a no-break space is part of the word.
    first = re.split(r"[ \t\v\f]+", info.strip(" \t\v\f"))[0]
    return Fence(number, len(indent), run, first.lower() == "mermaid")


def charts(text: str) -> Tuple[List[Tuple[int, List[str]]], Optional[int]]:
    """Each chart in a document, as the line of its opening fence and its lines, and the line of a fence never closed,
    or None."""
    found = []
    fence = None
    for number, line in enumerate(text.split("\n"), start=1):
        if fence is None:
            fence = opening(number, line)
        elif fence.closed_by(line):
            if fence.chart:
                found.append((fence.line, fence.body))
            fence = None
        else:
            fence.take(line)
    return found, (None if fence is None else fence.line)


def clear(out: pathlib.Path) -> None:
    """Remove this tool's own files from an earlier run, and nothing else."""
    for entry in out.iterdir():
        if entry.is_file() and OWN_FILE.fullmatch(entry.name):
            entry.unlink()


def write(out: pathlib.Path, found: List[Tuple[int, List[str]]]) -> List[Tuple[int, pathlib.Path]]:
    """Each chart's .mmd, as the line of its fence and its path."""
    written = []
    for index, (line, body) in enumerate(found, start=1):
        path = out / f"block-{index:02d}-line-{line}.mmd"
        with open(path, "w", encoding="utf-8", newline="\n") as chart:
            chart.write("\n".join(body) + "\n")
        written.append((line, path))
    return written


def render(mmd: pathlib.Path, png: pathlib.Path) -> Optional[str]:
    """None once preview_png.py has written the PNG, else why it has not."""
    environ = dict(os.environ, PYTHONIOENCODING="utf-8")
    try:
        result = subprocess.run([sys.executable, str(PREVIEW), str(mmd), str(png)], stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, encoding="utf-8", errors="replace", env=environ,
                                timeout=PREVIEW_TIMEOUT, check=False)
    except subprocess.TimeoutExpired:
        return f"preview_png.py had not finished after {PREVIEW_TIMEOUT} s"
    except OSError as error:
        return f"preview_png.py did not start: {error}"
    if result.returncode == 0 and png.is_file():
        return None
    lines = (result.stdout + result.stderr).strip().splitlines()
    return " / ".join(lines[:SHOWN]) or f"preview_png.py exited {result.returncode}"


def chart_width(png: pathlib.Path) -> Optional[int]:
    """The chart's width in pixels, from the width in its preview's header, or None where the preview is no PNG."""
    try:
        with open(png, "rb") as image:
            head = image.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != PNG_SIGNATURE or head[12:16] != b"IHDR":
        return None
    return -(-struct.unpack(">I", head[16:20])[0] // preview_png.SCALE)


def preview(written: List[Tuple[int, pathlib.Path]], limit: int) -> bool:
    """Render a PNG beside each chart, saying how each went and how wide each chart is, then name each chart wider than
    the limit, 0 being none; True when every one rendered and none is wider."""
    try:
        install = mermaid_svg.install_folder(None)
        state = mermaid_svg.status(install)
    except (ValueError, OSError) as error:
        print(f"export_blocks: {error}", file=sys.stderr, flush=True)
        return False
    fix = mermaid_svg.setup_command(install, False)
    if state == "missing":
        print(f"export_blocks: mermaid-svg is not installed in {install}; install it with {fix}, then preview again",
              file=sys.stderr, flush=True)
        return False
    if state == "stale":
        print(f"export_blocks: mermaid-svg in {install} was installed from other pins; update it with {fix}",
              file=sys.stderr, flush=True)
    rendered = 0
    wide = []
    for line, mmd in written:
        png = mmd.with_suffix(".png")
        why = render(mmd, png)
        width = chart_width(png) if why is None else None
        if width is None:
            print(f"line {line}: FAILED: {why or 'the preview is not a PNG'}", flush=True)
            continue
        rendered += 1
        print(f"line {line}: {png}, {width} px wide", flush=True)
        if limit and width > limit:
            wide.append(f"line {line}, {width} px")
    print(f"{rendered} of {len(written)} previews rendered.", flush=True)
    if wide:
        print(f"{len(wide)} chart{'' if len(wide) == 1 else 's'} wider than {limit} px: {'; '.join(wide)}. Lay a long "
              "chain out top to bottom, or fold it into rows (LESSONS.md, lessons 13 and 33).", flush=True)
    return rendered == len(written) and not wide


def parse(arguments: List[str]) -> Optional[Tuple[List[str], bool, int]]:
    """The two paths, whether to preview, and the width limit; None for arguments that are not this tool's."""
    paths, previewed, limit = [], False, MAX_WIDTH
    given = iter(arguments)
    for argument in given:
        if argument == "--preview":
            previewed = True
        elif argument == "--max-width":
            value = next(given, None)
            if value is None or not re.fullmatch(r"[0-9]+", value):
                return None
            limit = int(value)
        else:
            paths.append(argument)
    if len(paths) != 2 or any(not path or path.startswith("-") for path in paths):
        return None
    return paths, previewed, limit


def main(arguments: List[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        # A console's code page, such as Windows' cp1252 when stdout is a pipe, lacks most of Unicode. A path it can't
        # show prints escaped, rather than failing after the charts are written.
        sys.stdout.reconfigure(errors="backslashreplace")
    parsed = parse(arguments)
    if parsed is None:
        sys.exit(__doc__)
    paths, previewed, limit = parsed
    document, out = (mermaid_svg.absolute(path) for path in paths)
    if not document.is_file():
        sys.exit(f"export_blocks: there is no document at {document}")
    try:
        text = document.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError) as error:
        sys.exit(f"export_blocks: {document} could not be read: {error}")
    found, unclosed = charts(text)
    try:
        out.mkdir(parents=True, exist_ok=True)
        clear(out)
        written = write(out, found)
    except OSError as error:
        sys.exit(f"export_blocks: {error}")
    print(f"{len(written)} mermaid block{'' if len(written) == 1 else 's'} from {document}, written to {out}",
          flush=True)
    if unclosed is not None:
        print(f"export_blocks: the fence opened at line {unclosed} is never closed, so nothing after it was read as a "
              "chart", file=sys.stderr, flush=True)
    shown = not previewed or not written or preview(written, limit)
    return 0 if shown and unclosed is None else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
