# Mermaid flowchart lessons

Learned on Mermaid 12.0.0 through mermaid-cli 12.0.0, with the default layout, the `classic` look and
`htmlLabels: false`. Inkscape's behaviour was checked in Inkscape 1.4.4 on Windows, then on one chart in the same
build on Ubuntu 24.04, where lesson 27's was checked in Inkscape 1.2.2. Lesson 27's floor was measured on one chart in
Inkscape's own builds of 1.4.0, 1.4.2, 1.4.3 and 1.4.4 on Ubuntu 26.04, in Ubuntu 26.04's own 1.4.3 and the 1.4.4 of
Inkscape's PPA, in Debian 13's 1.4.0 and in 1.4.4 on Windows. Lesson 24's one-line labels and lessons 28 to 33 were
checked in mermaid-cli's own render, not in Inkscape. On another version, check a lesson before relying on it.

## Working

1. **Render it and look after every structural change.** Flipped sections, stray lines and empty labels don't show in
   the source. A PNG from the pinned renderer is quick to check, at twice the chart's size on white:
   `python tools/preview_png.py chart.mmd chart.png` from the skill's folder.
2. **Keep one source.** Keep the chart in its own `.mmd` file, and build any page that shows it from a template with a
   placeholder, so the copy in the page never drifts from the chart.

## SVG for Inkscape and other strict renderers

3. **Render with these settings:**
   ```json
   { "htmlLabels": false, "look": "classic",
     "flowchart": { "htmlLabels": false, "useMaxWidth": false, "wrappingWidth": 240 } }
   ```
   - `htmlLabels: false` makes labels SVG text. HTML labels sit in `<foreignObject>`, which Inkscape doesn't draw, so
     it shows only the edges. After a render, search the SVG: it should hold no `foreignObject`.
   - `look: "classic"`: the `neo` look draws shapes Inkscape doesn't show.
   - `useMaxWidth: false` gives the SVG its own width and height, instead of a width of 100% and no height, which a
     browser shrinks to fit its window.
   - Add `xml:space="preserve"` to the root `<svg>` after rendering. Each word after a label's first starts with a space
     in a `<tspan>` of its own, and Inkscape drops that space without it.
4. **If Inkscape is missing, offer to install it rather than work around it.** Check with `inkscape --version`. On
   Windows the installer may not add Inkscape to `PATH`, so try its `bin` folder too, where the console program is
   `inkscape.com` (for example `C:\Program Files\Inkscape\bin\inkscape.com`). If it isn't there, ask the developer whether
   to install it, naming the command for their platform and the package manager they use, and install only on a yes:

   | Platform | Package manager | Install | Then run it as |
   |---|---|---|---|
   | Windows | winget | `winget install --id Inkscape.Inkscape -e` | `inkscape.com` in the install's `bin` folder |
   | Windows | Chocolatey | `choco install inkscape` | the same |
   | Windows | Scoop | `scoop bucket add extras`, then `scoop install extras/inkscape` | `inkscape` |
   | macOS | Homebrew | `brew install --cask inkscape` | `/Applications/Inkscape.app/Contents/MacOS/inkscape` |
   | Ubuntu | apt, with Inkscape's PPA | `sudo add-apt-repository ppa:inkscape.dev/stable`, then `sudo apt install inkscape` | `inkscape` |
   | apt offering 1.4.2 or later | apt | `sudo apt install inkscape` | `inkscape` |
   | Debian 12 and 13 | apt, then Flatpak | `sudo apt install flatpak`, then `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`, then `flatpak install flathub org.inkscape.Inkscape` | `flatpak run org.inkscape.Inkscape` |
   | Fedora | dnf | `sudo dnf install inkscape` | `inkscape` |
   | Arch | pacman | `sudo pacman -S inkscape` | `inkscape` |
   | openSUSE | zypper | `sudo zypper install inkscape` | `inkscape` |
   | Any Linux | Flatpak | `flatpak install flathub org.inkscape.Inkscape` | `flatpak run org.inkscape.Inkscape` |
   | Any Linux | Snap | `sudo snap install inkscape` | `inkscape` |

   Any platform can also install from inkscape.org. Then check that `--version` prints 1.4.2 or later: a
   distribution's own package can lag behind the current release, and Inkscape 1.2, which Ubuntu 24.04 and Debian 12
   ship, and 1.4.0, which Debian 13 ships and which prints `Inkscape 1.4`, draw Mermaid's SVGs broken (lesson 27).
   Which apt row fits is the package manager's to say, so `inkscape_png.py --plan` asks it. Until Inkscape is
   installed, say that the Inkscape check was skipped, and rely on lesson 3's settings and a browser's render.
5. **See what Inkscape draws without opening it.** Its command line renders exactly as the application does, so export
   a PNG and compare it with a browser's render:
   ```
   inkscape chart.svg --export-type=png --export-filename=chart-inkscape.png --export-width=2000 --export-background=white --export-background-opacity=1
   ```
   On Windows, run `inkscape.com`, the console build, to see its messages. Without the two background options the PNG
   is transparent.
6. **Inkscape reads inline styles and Mermaid's simple CSS rules.** All of these draw as they do in a browser:
   - node colours from `classDef` and `class`, which Mermaid writes inline, `!important` included;
   - a group box coloured by a `style <subgraphId> fill:…,stroke:…` statement;
   - dotted edges;
   - Mermaid's rule for edge-label backgrounds, and a `themeCSS` rule that overrides it (lesson 21);
   - bold text, which is a `font-weight="bold"` attribute on its `<tspan>`;
   - classic shapes, stacked rectangles, hexagons and cylinders.
7. **Inkscape skips the CSS that colours unstyled groups.** Mermaid gives each group a pastel with rules like
   `[data-color-id="color-0"].cluster:not(.swimlane) rect`. Inkscape doesn't apply them, and draws every unstyled group
   in the base grey of `.cluster rect`. So give each group box a `style` statement whenever its colour matters. It also
   stops a pastel from swallowing a node of the same hue.
8. **Inkscape draws its own font.** It doesn't load the web font Mermaid embeds, "Recursive Variable" in an `@font-face`
   rule, and substitutes a plain sans. Mermaid sized every box for its own font, so leave slack: lines broken at about
   26 characters still fitted.
9. **Inkscape's warnings are noise.** "Ignoring unrecognized CSS property: background-color", and the `@font-face`
   declarations it lists as unrecognised, come from Mermaid's rules for HTML labels. The drawing isn't affected.
10. **Coloured and removed arrowheads carry over.** Mermaid writes a coloured copy of the arrowhead marker for each
    `linkStyle` stroke colour, so an orange line gets an orange head. An inline `marker-end:none` removes one end in
    Inkscape as in a browser (lesson 15).
11. **Inkscape doesn't notice a re-rendered file.** Use File → Revert to reload it. Write each render to a temporary file
    and move it into place, so a viewer never reads half a file. On Windows the move fails while a viewer holds the old
    file open.

## Layout

12. **Lay the chart out along its flow, not in one lane per actor.** Lanes turn to spaghetti when most arrows cross
    them. Show who acts with colour and a key instead.
13. **Fold a long chain into rows.** A top-to-bottom chain of *n* steps is *n* ranks tall, and `flowchart LR` only turns
    the problem sideways: in one chart it took 0.34 wide-to-tall to 8.3. Put runs of steps in subgraphs with
    `direction LR`, stacked top to bottom. That chart came out at 0.9.
14. **A row keeps its direction only if it's connected at the subgraph.** Mermaid ignores a subgraph's `direction` as
    soon as any node inside links to a node outside, so point every outside arrow at the subgraph's id:
    ```
    subgraph row["One row"]
      direction LR
      a --> b --> c
    end
    start --> row
    row --> finish
    ```
15. **A return arrow can turn the chart upside down.** An arrow from late in the flow back to an early node makes a
    cycle, and to break it the layout can reverse part of the main flow. Declare the arrow forward, from the early node,
    as two-headed, and remove its far arrowhead:
    ```
    early <-. "the reason" .-> late
    linkStyle 12 stroke:#fd7e14,marker-end:none
    ```
    Only the arrowhead at `early` shows, and the flow keeps running down. The arrowheads are `marker-start` and
    `marker-end` attributes, so the inline style overrides them.
16. **ELK isn't there.** `layout: elk` needs the ELK layout package registered. mermaid-cli 12.0.0 doesn't bundle it,
    and asking for it renders the default layout without a word.
17. **Two unlinked nodes in an `LR` row stack up and down.** An invisible link, `a ~~~ b`, sets them side by side.
18. **Stray diagonal lines point to a subgraph.** In one chart, two subgraphs drew long stray diagonals across it.
    Removing them, and letting colour carry the grouping, fixed it.

## Shapes

19. **A diamond grows to fit its text.** Its text box has to fit inside the rhombus, so even a short decision label
    makes it the biggest shape on the chart. Keep decision labels to a few words, and use a hexagon, `{{"Approved"}}`,
    for a small gate.
20. **Stacked rectangles show "many",** such as a pool of agents: `id@{ shape: procs, label: "…" }`.

## Text

21. **Make edge labels opaque.** Mermaid draws an edge label's background at 50% opacity, so its line shows through, in
    Inkscape as in a browser. Override that in the chart's front matter, which Mermaid scopes to the chart:
    ```
    ---
    config:
      themeCSS: ".edgeLabel rect { opacity: 1 !important; fill: #ffffff !important; }"
    ---
    ```
22. **Break label lines yourself.** With `wrappingWidth: 240`, a line longer than about 26 characters is rewrapped
    wherever it falls. Break it with `<br/>`.
23. **Bold needs a markdown label, and only classic shapes render one.** A markdown label is wrapped in backticks
    inside the quotes:
    ```
    a["`A commit **SHA**
    or **branch**`"]
    ```
    It shows bold in `[…]`, `[/…/]`, `[[…]]` and the other classic shapes. An `@{ shape: … }` shape draws a markdown
    label empty. A markdown label breaks at real newlines, as above, not at `<br/>`. Mermaid puts a space before
    punctuation that follows a bold word (`branch ,`), so reword to keep punctuation away from bold text.
24. **Escape `#` and `"` only in a label broken with `<br/>`.** Mermaid turns `#…;` into an HTML entity. In a label
    broken with `<br/>` the entity is then decoded: `#4;` becomes U+0004, which breaks an SVG export, so there write
    `#35;` for `#` and `#quot;` for `"`. In a label of one line the entity is drawn as written, so `#35;` shows as
    `&#35;` and `#quot;` as `&quot;`; write `#` plainly there, and `#FF0000` draws as it reads. No spelling draws a `"`
    in a label of one line: use `'`, or break the label with `<br/>`.

## Edges

25. **`linkStyle` counts every link in the file, in order.** Links inside subgraphs count, and so do invisible `~~~`
    links; a two-headed link counts once. A wrong index silently styles the wrong arrow, so recount after adding,
    removing or moving any link. Writing the links in one block, in a fixed order, makes the count easy.
26. **Give line styles a meaning, and put it in a key.** For example: solid for work that moves, dotted for a message,
    and one colour for anything that passes through a given person. A `direction LR` subgraph named KEY, holding a
    sample node of each class and a note for the line styles, lets a reader decode the chart.

## Inkscape versions

27. **Inkscape 1.2 and 1.4.0 drop Mermaid's whole stylesheet.** Each chart Mermaid 12 draws declares one CSS
    variable, `:root{--mermaid-font-family:…}`, and Inkscape 1.2.2 can't parse it, so it applies none of Mermaid's CSS
    rules, not even those before it. Nodes without a `classDef` fill black, and so do edge-label boxes; labels sit
    off-centre, without their `text-anchor: middle`; dotted lines draw solid; and a link can fill as a black wedge, or
    lose its line and keep only its arrowhead. Inline styles still apply, so the styled nodes look right, which makes
    the rest look like a fault in the chart. Inkscape 1.4.0, which prints `Inkscape 1.4`, draws a chart as it would
    draw one with no stylesheet at all: unstyled nodes and groups black with their labels lost in them, edge-label boxes
    black, a group's title black instead of its `titleColor`, and dotted lines gone. Taking out the `:root` rule
    doesn't help there, so its cause is another. Inkscape 1.4.2, 1.4.3 and 1.4.4 apply the rules, and 1.4.1 was never
    released. So use 1.4.2 or later: Ubuntu 24.04 and Debian 12 ship 1.2.2 and Debian 13 ships 1.4.0, and lesson 4's
    table installs a newer one.

## Swatches

28. **Draw a palette as rows of swatches.** One node per colour, labelled with its name and, after a `<br/>`, its value
    (lesson 24), filled by a `style` line. Put four to a row, each row a `direction LR` subgraph whose nodes are linked
    with `~~~` (lesson 17), and the rows in one panel subgraph:
    ```
    subgraph panel["Palette"]
      direction TB
      subgraph row1["Palette.axaml:31-36"]
        direction LR
        accent["Accent<br/>#35;4CAF50"] ~~~ chrome["Chrome<br/>#35;087F23"]
      end
      subgraph row2["Palette.axaml:42-53"]
        direction LR
        surface["Surface<br/>#35;323232"] ~~~ danger["Danger<br/>#35;CF6679"]
      end
      row1 ~~~ row2
    end
    style accent fill:#4CAF50,stroke:#5B5B5B,color:#000000
    ```
29. **Link the rows in order.** Rows with no link between them stack in whatever order the layout picks: in one chart,
    four rows came out last first. Link each row to the next at the subgraphs' ids, `row1 ~~~ row2`, as lesson 14 asks,
    and they stack as written.
30. **Fill a swatch with an opaque `#RRGGBB`.** CSS reads an eight-digit colour as `#RRGGBBAA`, alpha last, where XAML
    writes `#AARRGGBB`: copied into a `style` line, XAML's half-transparent red `#80FF0000` drew fully transparent. Read
    the right way round, a translucent fill still shows whatever is behind the node, not the ground the colour is drawn
    on in use. So composite the colour over that ground and write the result, and fill the panel with the ground. Give
    each label `color:` black or white, whichever contrasts more with its fill: a node's `color:` reaches its label.
31. **Colour subgraph titles in the front matter, once per chart.** A `style` line's `color:` doesn't reach a subgraph's
    title, which keeps the theme's title colour: black, all but lost on a dark panel. Set the colour in the chart's
    front matter:
    ```
    ---
    config:
      themeVariables:
        titleColor: "#F9F9F9"
    ---
    ```
    It is one rule for every title in the chart, so a light theme's swatches and a dark theme's need a chart each.

## Parsing and width

32. **A flowchart keyword can't be a node ID.** The lexer reads the bare word as its keyword wherever it stands, so the
    parser never sees a node there, and the error doesn't say the name is taken:
    ```
    Parse error on line 2:
    ...t LR    ingest --> style[pdf_style] & r
    ----------------------^
    Expecting 'AMP', 'COLON', 'PIPE', … 'UNICODE_TEXT', got 'STYLE'
    ```
    The word after "got" is the keyword's token, `STYLE`, `CLASS` or `GRAPH`, or `end` or `subgraph` in lower case,
    and the caret points at it. As bare IDs, `style`, `end`, `subgraph`, `class`, `classDef`, `linkStyle`, `graph`,
    `flowchart` and `interpolate` failed wherever they stood, and `click`, `call` and `href` after an `&`; `direction`,
    `default`, `accTitle` and `accDescr` parsed. The match is exact: `End`, `Style`, `STYLE`, `endpoint` and `styles`
    parsed too. A label is free text, so keep the word there and give the node another ID: `pdfstyle[pdf_style]`.
33. **Keep a chart under about 1,250 px wide.** On GitHub, and projected, a wider chart shrinks until its text can't be
    read, and a long chain laid out `LR` is the usual cause: five steps, a fan-out to three and four more steps drew
    2,300 px wide as `flowchart LR` and 691 px as `flowchart TD`. Lay a chain of more than about six nodes top to
    bottom, or fold it into rows (lesson 13), and keep `LR` for short chains and wide, shallow comparisons. Read the
    width off the render, not the source: `tools/export_blocks.py --preview` says how wide each chart in a document
    is, and with lesson 3's `useMaxWidth: false` an SVG's root `<svg>` carries it as `width`.
