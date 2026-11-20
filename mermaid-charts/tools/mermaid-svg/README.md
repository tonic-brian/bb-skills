# mermaid-svg

Turns a Mermaid chart into an SVG that Inkscape and browsers both draw. It renders with pinned tools and a pinned
browser, so everyone on the same commit renders a chart the same way. It knows nothing about who calls it: the
[mermaid-charts skill](../../SKILL.md) uses it, and anything else can. From the skill's folder:

```bash
python tools/mermaid-svg/mermaid_svg.py setup                  # once per machine
python tools/mermaid-svg/mermaid_svg.py render chart.mmd chart.svg
python tools/mermaid-svg/mermaid_svg.py check                  # 0 when the install matches the pins
python tools/mermaid-svg/mermaid_svg.py plan                   # JSON for a setup: the install's state, and Node.js
```

From Python, with this folder on `sys.path`:

```python
import mermaid_svg

notes = mermaid_svg.render("chart.mmd", "chart.svg")  # returns notes worth printing, such as an out-of-date install
```

`render` raises `mermaid_svg.NotInstalled` when there's no install, and `mermaid_svg.RenderError`, its parent class,
when a render fails. It takes `install_dir=`, and `config=`, a Mermaid config file to use instead of
[`mermaid-config.json`](mermaid-config.json). On the command line they are `--install-dir` and `--config`.

## The SVG

| Setting | Why |
|---|---|
| Labels are SVG text (`htmlLabels: false`) | Mermaid's default HTML labels sit in `<foreignObject>`, which Inkscape doesn't draw: it showed only the edges |
| Mermaid's `classic` look | Mermaid 12's default look, `neo`, draws shapes Inkscape doesn't show |
| `xml:space="preserve"` on the root `<svg>` | each word after a label's first starts with a space in a `<tspan>` of its own, and Inkscape drops that space unless told to keep it |
| `flowchart.useMaxWidth: false` | Mermaid's default writes a width of 100% and no height, so a browser shrinks a tall chart to fit its window, and zooming only fits it again. The SVG gets its own width and height instead |
| `flowchart.wrappingWidth: 240` | at Mermaid's 120 px, a word too wide for its line is split mid-word, as in `ReverseMarkdow` / `n` |
| `handDrawnSeed: 1` | Mermaid draws its newer shapes, such as the stadium and `procs`, by hand, with random control points unless seeded, so each render of a chart that had one differed |

`xml:space` is added after mermaid-cli writes the file; the rest is `mermaid-config.json`. Verified on Windows in
Inkscape 1.4.4 and in the pinned Chrome 154. Two things differ between them:
- Browsers draw the labels in the font the SVG embeds, Mermaid's own "Recursive Variable". Inkscape draws them in a
  font of its own, and they still fit.
- Browsers colour each group's background. Inkscape draws them grey, because the colours are CSS rules it doesn't
  read.

**The same chart and pins give the same bytes** on the same platform: two renders of the same chart were identical,
on Windows and on Linux (Ubuntu 24.04 under WSL). The two platforms' SVGs differ from each other, because each has its
own build of the browser, which measures text a little differently.

**A render replaces the SVG in one step.** mermaid-cli writes into a folder beside the SVG, and the file moves into
place once it parses as an SVG. A viewer reloading it never reads half a file, and a failed render leaves the old SVG
untouched and nothing else behind.

**No shell reads an argument.** Every render runs the Node the setup checked, on mermaid-cli's own script, with an
argument list, never npm's `.cmd` shim. A path with `&`, `%` or spaces in it reaches mermaid-cli whole.

## Setup

`python tools/mermaid-svg/mermaid_svg.py setup` needs Node.js 22.13 or newer, which mermaid-cli 12
requires; without it, the setup says so and stops. It then:

1. copies the pins in this folder into the install: [`package.json`](package.json),
   [`package-lock.json`](package-lock.json), [`.puppeteerrc.cjs`](.puppeteerrc.cjs) and
   [`browser-plan.mjs`](browser-plan.mjs);
2. installs `@mermaid-js/mermaid-cli` 12.0.0 and `puppeteer` 25.12.0, with everything the lockfile pins beneath them,
   from the npm registry, without running their install scripts, unless `node_modules` already holds exactly that;
3. asks the installed Puppeteer which browser it would fetch and where it would keep it, and stops unless that is
   chrome-headless-shell inside the install, where mermaid-cli will look for it, with the full Chrome and Firefox
   turned off;
4. installs that one build, chrome-headless-shell 154.0.8037.57 today, from Google's Chrome for Testing storage, unless
   it is already there. It downloads into a folder of its own and moves the browser into place once it is whole;
5. renders a two-node chart, and checks that its labels are SVG text;
6. records the install in `installed.json`: the pins' digest, the Node it checked, and the browser.

Before each download it says what it fetches and from where. It never downloads the full Chrome. One setup runs at a
time: a second, started meanwhile, finds `setup.lock` in the install and stops.

Run the setup again whenever you like. While the install matches the pins, its packages are as npm installed them,
and the Node on PATH is the one it recorded, it does nothing. After the pins change, it proves the install again,
reinstalling the packages only if the lockfile's changed, and fetching a browser only for a new build. Until you rerun
it, `render` still renders with the old install and says to update it, and `check` exits 1.

Don't run npm in this folder: it would install here, in the repository, and Puppeteer's own install script would fetch
a browser into it too. This folder's `.gitignore` keeps such an install out of commits.

**On Linux**, unpacking the browser needs `unzip`, and the browser needs Chrome's shared libraries. **Behind a proxy**,
npm uses your proxy settings but the browser download doesn't, because Puppeteer's optional `proxy-agent` isn't
installed.

## Where the install lives

In `.mermaid-svg/` under your home folder, outside every repository. On Windows it takes about 670 MB: 380 MB of npm
packages and 285 MB of browser. `--install-dir DIR` puts it somewhere else, or the environment variable
`MERMAID_SVG_HOME`, an absolute path, does for every command. The setup refuses a folder inside a repository that
holds this tool, and a folder that already holds something other than a mermaid-svg install: it never writes over
another project's files.

The install is one per machine, and every checkout on the machine shares it. When one branch changes the pins and
another doesn't, whichever setup ran last wins, and the other branch's renders say its install is from other pins.

To move the install, move the folder and point `--install-dir` or `MERMAID_SVG_HOME` at it: `installed.json` names
the browser relative to the install. To remove it, delete the folder. npm's own cache keeps a copy of the packages
too, as it does for any npm install, outside the install and not counted in its size.

Puppeteer runs from the install folder, where `.puppeteerrc.cjs` keeps the browser in `browsers/` and turns off the
full Chrome and Firefox. mermaid_svg.py drops every `PUPPETEER_*` variable from the environment it runs Node in,
because each would override that file. The one exception is `PUPPETEER_CACHE_DIR` during the browser download, which
points at the download's own folder.

## Moving the tool

This folder holds everything the conversion needs. mermaid_svg.py uses Python's standard library only, finds its own
files beside itself, and imports nothing else. To use it elsewhere, copy the folder. The paths in this README are from
the skill's folder: change them when the folder moves.

## Tests

```bash
python -m unittest discover -s tools/mermaid-svg/tests
```

They run on their own, with a stub in mermaid-cli's place and Python playing Node, and they download nothing. Where
this machine has a current install, `test_real.py` renders with it too, and exports the SVG through Inkscape when
Inkscape is on PATH or in its usual install folder. Without either, those tests skip.
