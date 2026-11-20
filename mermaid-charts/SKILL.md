---
name: mermaid-charts
description: >-
  Draw, render and export Mermaid flowcharts that people can read, in a browser and in Inkscape. Use this
  WHENEVER the chart itself is the work: writing or changing a .mmd file, rendering a chart, exporting it as
  SVG, checking it in Inkscape, drawing a palette as swatches, or checking the charts a document holds — or
  the developer asks to "draw a flowchart", "make a Mermaid chart", "render the chart", "export it as SVG",
  "check it in Inkscape" or "check the charts in this document", or says a chart "looks wrong", "runs upside
  down", "is spaghetti" or "cuts off its labels". A quick diagram inside a document doesn't need it. Holds the
  lessons that keep layout, labels and colours intact, a pinned renderer installed only on a yes, and a way to
  see what Inkscape draws.
compatibility: Python, Node.js, (optionally) Inkscape
---

# Mermaid charts

A chart is done when a reader can follow it, which its source can't tell you: flipped sections, stray lines
and empty labels show only in a render. So loop: draft from the lessons, render, look, fix. `<skill>` is this
skill's folder and `<scratch>` a scratch folder outside the project; quote a path with spaces. The commands
say `python`: on Windows run `py`, elsewhere `python3` where that is Python 3's name.

## 1. Read the lessons before you draw

Read [LESSONS.md](LESSONS.md) before writing or changing a chart. Its 33 lessons, learned on Mermaid 12.0.0
and Inkscape 1.4.4: working (1–2), SVG for strict renderers (3–11), layout (12–18), shapes, text, edges,
Inkscape's versions (27), swatches (28–31), and parsing and width (32–33).

## 2. Check for the renderer, and install it only on a yes

```bash
pwsh -NoProfile -File "<skill>/setup.ps1"                  # asks once about each missing item, Inkscape too
python "<skill>/tools/mermaid-svg/mermaid_svg.py" check    # 0 when installed at the pins; 1 says what to run
python "<skill>/tools/mermaid-svg/mermaid_svg.py" setup    # only after the developer says yes
```

- **`setup.ps1` asks once about each missing item** — Python, Node.js, the renderer and Inkscape — and
  installs only on a yes. Installing the skill may already have run it; run it again to be asked again.
- **Ask before the setup, saying what it does:** it installs about 700 MB into `~/.mermaid-svg/`, or
  `MERMAID_SVG_HOME`: mermaid-cli and Puppeteer from the npm registry, and chrome-headless-shell from Google's
  Chrome for Testing storage. The renderer's [README](tools/mermaid-svg/README.md) has the details.
- **The setup needs Node.js 22.13 or later** and stops without it, saying how to install it. Ask before
  installing Node too; on Linux prefer nvm or nodejs.org's tarball, as a distribution's package is often
  older.
- **On a no, keep going.** Draft from the lessons and say at handover that the chart wasn't rendered. Don't
  swap in another renderer: an unpinned `npx` mermaid-cli isn't what the lessons were checked on, and an
  online one sends the chart away.

## 3. Draft, render, look, repeat

```bash
python "<skill>/tools/preview_png.py" chart.mmd "<scratch>/preview.png"        # a PNG from the pinned browser
python "<skill>/tools/mermaid-svg/mermaid_svg.py" render chart.mmd chart.svg   # the SVG to hand over
python "<skill>/tools/export_blocks.py" doc.md "<scratch>/charts" --preview    # a document's charts, one by one
pwsh -NoProfile -File "<skill>/tools/Export-MermaidBlocks.ps1" doc.md "<scratch>/charts" -Preview   # the same, in PowerShell
```

- **Keep the chart in its own `.mmd` file** (lesson 2). Previews are working files, kept out of the project
  unless the developer wants them.
- **Check a document's charts one by one.** `export_blocks.py` writes each mermaid block as
  `block-NN-line-L.mmd`, `L` being its fence's line, clearing only its own earlier files; `--preview` adds
  each one's PNG and width. It exits 1 on a failed preview, an unclosed fence or a chart over 1,250 px wide
  (lesson 33; `--max-width` sets another, 0 none). `Export-MermaidBlocks.ps1` does the same in PowerShell.
- **Render after every structural change** (a node, a link, a subgraph) and open the PNG. Look for what the
  source hides: one direction of flow throughout, no stray diagonals, every label present and whole, and each
  `linkStyle` on the arrow it was meant for.
- **Search the SVG for `foreignObject`:** there should be none. The renderer applies lesson 3's settings, but
  a chart's own front matter can override them.

## 4. See what Inkscape draws

```bash
python "<skill>/tools/inkscape_png.py" chart.svg "<scratch>/inkscape.png"    # 2 without Inkscape 1.4.2 or later
```

Before handing over an SVG, export it and compare the PNG with the preview. Grey boxes for unstyled groups
(lesson 7) and a plainer font (lesson 8) are expected; anything else is a finding. Exit 2 says why, and when
Inkscape is missing lists lesson 4's install commands for this platform: ask, install only on a yes, and
otherwise say the Inkscape check was skipped.

## 5. Hand over

Give the paths of the `.mmd`, the `.svg` and any page built from them, and say what was and wasn't checked:
"not rendered" or "Inkscape check skipped" is part of the answer. A chart that fails to parse, or renders
wider than about 1,250 px (lesson 33), isn't finished. A mermaid block in a page is drawn by whatever shows
the page, with its own Mermaid and settings, so say your checks were of the SVG. If the developer has the SVG
open in Inkscape, File → Revert shows the new render (lesson 11).

## Critical details (easy to get wrong)

- **A keyword can't be a node ID** (lesson 32). `style`, `end`, `class` and their kind fail the parse with
  `got 'STYLE'` or the like: keep the word in the label and give the node another ID.
- **`linkStyle` counts every link in the file** (lesson 25). Adding or removing one silently moves the styles
  onto other arrows: recount after each change, and check the arrows in the preview.
- **On Windows, a render can't replace an SVG a viewer holds open** (lesson 11). The old file stays: ask the
  developer to close it, then render again.
- **A swatch's fill is an opaque `#RRGGBB`** (lesson 30). CSS reads eight digits as `#RRGGBBAA`, so a colour
  copied from XAML's `#AARRGGBB` is drawn from the wrong channels.
- **Each install is its own question.** A yes to the renderer isn't a yes to Node.js or Inkscape.
- **The lessons are bound to their versions.** On another Mermaid or Inkscape, check a lesson before relying
  on it.
