# bb-skill-pack-20261120-3525958

8 skills for your  `AGENT`, built on 2026-11-20 from commit `3525958` of the bb-skills repository.

| **Skill**                 | **What it does**                                             | **Needs**                                      |
| ------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| **`handoff`**             | Prepare a clean context handoff so work resumes in a fresh session without losing state. |                                                |
| **`resume-handoff`**      | Resume work from a handoff anchor in a fresh session, reconciling the saved state against reality before trusting a word of it. |                                                |
| **`address-pr-feedback`** | Fetch, vet, and act on review feedback left on a pull request, from AI reviewers (`codex`, `Copilot`, `greptile`, …) or humans. | `GitHub`, `gh` CLI                             |
| **`step-back`**           | Take a step back and adversarially review a proposed plan, the code in progress, or the whole branch since base, before more work piles onto it. |                                                |
| **`choices`**             | Walk the developer through open decisions one at a time — brief context, two to four choices, and a recommendation each — so they settle them interactively without scrolling or opening a plan. |                                                |
| **`mermaid-charts`**      | Draw, render and export Mermaid flowcharts that people can read, in a browser and in Inkscape. | `Python`, `Node.js`, (*optionally*) `Inkscape` |
| **`agent-times`**         | Show how long each agent of this Claude Code session has run, its state, and how long since it last wrote. | `Claude Code`, `Node.js`                       |
| **`crunch`**              | Decide when to compact the context, and how, so a long session keeps what the next phase needs. | `Claude Code`, `Node.js`                       |

## What you need

- **PowerShell 7.4 or later,** run as `pwsh`; `pwsh -v` shows which you have.
  - Windows: `winget install --id Microsoft.PowerShell --source winget`
  - macOS: `brew install --cask powershell`
  - Linux: Microsoft's package for your distribution, from
    <https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux>
  - macOS or Linux without it: `sh Install-Skills.sh`, under Install, fetches it for you.
- **Claude Code.** The skills install into `~/.claude/skills`. `crunch`'s mod, its status line, toast and band,
  wants Claude Code 2.1.300 or later.
- **Node.js 18 or later,** for `agent-times`, which runs on it, and for `crunch`'s hooks. Their setups say when it
  is missing and install nothing: get it from <https://nodejs.org> or a version manager.
- **For `mermaid-charts`:** Python, Node.js, its pinned renderer and Inkscape. Its setup asks about each one
  that is missing and installs it on a yes; on Linux it names Python and Node.js rather than installing them.

## On Windows, unblock the files first

Windows marks each file taken out of a downloaded `.zip` as downloaded, and PowerShell's `RemoteSigned`
execution policy, the default on Windows, then refuses to run the installer and every script it runs. In
PowerShell, in this folder:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

macOS and Linux need no such step.

## Install

`Install-Skills.ps1`: Installs this repository's skills into Claude Code's skills folder, with their setups, hooks and settings. Read only unless -Apply.

Run it in this folder, either way, with the same arguments:

- **With PowerShell 7.4,** on any platform: `pwsh -NoProfile -File Install-Skills.ps1`
- **On macOS or Linux, with or without PowerShell:** `sh Install-Skills.sh`. It runs the installer under the `pwsh`
  on PATH when that is 7 or later, or else one in `~/.local/share/powershell/autoinstall`, where it downloads
  the latest stable release with `curl` when there is none. `sh Install-Skills.sh --help` lists its own flags too.

`pwsh -NoProfile -File Install-Skills.ps1 -?`, or `sh Install-Skills.sh -?`, shows the installer's help. Its examples, each
of which runs the same with `sh Install-Skills.sh` in place of `pwsh -NoProfile -File Install-Skills.ps1`:

```
pwsh -NoProfile -File Install-Skills.ps1
```

With nobody to ask, shows what is installed and what an install would change; at a terminal, offers a menu.

```
pwsh -NoProfile -File Install-Skills.ps1 -Apply
```

Installs or updates every skill, asking only what a person can answer.

```
pwsh -NoProfile -File Install-Skills.ps1 -Skill crunch
```

A dry run: what installing crunch would change, ending with the command that does it.

```
pwsh -NoProfile -File Install-Skills.ps1 -Skill agent-times -Rename agent-times=times -Apply
```

Installs agent-times alone, as /times.

```
pwsh -NoProfile -File Install-Skills.ps1 -AddHooks crunch -Apply
```

Adds crunch's hooks to settings.json.

```
pwsh -NoProfile -File Install-Skills.ps1 -Configure crunch -Apply
```

Asks about each of crunch's settings, and writes the change on a yes.

`agent-times` installs under its own name; add `-Rename agent-times=times` to install it as `times`, run
as `/times`.
