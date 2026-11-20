"""Render a Mermaid chart to PNG with mermaid-svg's pinned install, as a layout preview only.

Usage:  python preview_png.py <chart.mmd> <out.png>

It uses the mermaid-svg folder beside this file, and mermaid-svg's install, from MERMAID_SVG_HOME or ~/.mermaid-svg
as for mermaid_svg.py. Like `mermaid_svg.py render`, it says how to make an install when there is none, and renders
with one from other pins but says to update it. The SVG for pages and Inkscape comes from `mermaid_svg.py render`, not
from here.
"""
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPTS = Path(__file__).resolve().parent / "mermaid-svg"
sys.path.insert(0, str(SCRIPTS))
import mermaid_svg  # noqa: E402

SCALE = 2  # the PNG's pixels to each of the chart's: half its width is the chart's, rounded up


def command(node: str, script: Path, mmd: Path, png: Path) -> list:
    """mermaid-cli's command for a PNG at twice the chart's size, on white, with the settings `render` uses."""
    return [node, str(script), "--input", str(mmd), "--output", str(png), "--configFile", str(mermaid_svg.CONFIG),
            "--quiet", "--scale", str(SCALE), "--backgroundColor", "white"]


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    # Node runs in the install folder, so every path it gets is absolute.
    mmd, png = (mermaid_svg.absolute(argument) for argument in sys.argv[1:3])
    if not mmd.is_file():
        sys.exit(f"preview_png: there is no chart at {mmd}")
    if not png.parent.is_dir():
        sys.exit(f"preview_png: there is no folder {png.parent} to write the PNG in")
    try:
        install = mermaid_svg.install_folder(None)
        state = mermaid_svg.status(install)
    except (ValueError, OSError) as error:
        sys.exit(f"preview_png: {error}")
    fix = mermaid_svg.setup_command(install, False)
    if state == "missing":
        sys.exit(f"preview_png: mermaid-svg is not installed in {install}; install it with {fix}")
    if state == "stale":
        print(f"preview_png: mermaid-svg in {install} was installed from other pins; update it with {fix}",
              file=sys.stderr)
    node = mermaid_svg.read_stamp(install)["node"]
    script = mermaid_svg.package_script(install, *mermaid_svg.MERMAID_CLI)
    mermaid_svg.flush_output()
    try:
        result = subprocess.run(command(node, script, mmd, png), cwd=str(install),
                                env=mermaid_svg.node_environment(None), stdin=subprocess.DEVNULL,
                                timeout=mermaid_svg.RENDER_TIMEOUT, check=False)
    except subprocess.TimeoutExpired:
        sys.exit(f"preview_png: mermaid-cli had not finished after {mermaid_svg.RENDER_TIMEOUT} s")
    except OSError as error:
        sys.exit(f"preview_png: mermaid-cli did not start: {error}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
