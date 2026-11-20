# crunch's hooks

Optional: the skill's root `hooks.json` declares them, and they are registered in `settings.json` only when the
developer says yes at install time. Each needs Node.js 18 or later, and always exits 0. The `hooks.json` in this
folder is the mod's, below: Claude Code reads it, and the installer doesn't.

| File | Runs on | Does |
|---|---|---|
| `suggest-compact.js` | PreToolUse, every tool call | Suggests `/compact` from the context's size and the count of edits and writes, to Claude and to the developer, and records each call it suggested it on |
| `on-compact.js` | PostCompact, every trigger | Starts the session's count and context level again, and records the compaction under its trigger |
| `check-transcript.js` | Run by hand | Says whether the size check can read a transcript: exit 0, 1, or 2 with nothing to check |

`suggest-compact.js` runs before a subagent's calls too, and returns at once. A run costs about 10 ms more than a
bare `node` start, measured on Windows with Node.js 26.9, so starting Node.js is most of what it costs.

## What Claude and the developer are told

`suggest-compact.js` tells Claude in lines led by `[Crunch]`, which the skill looks for, and tells the
developer in a line of their own, the one a terminal prints. Where both nudges fire on one call, Claude reads two
lines and the developer one.

| Nudge | Claude reads | The developer reads |
|---|---|---|
| The context's size | `[Crunch] Context ~254k tokens (25% of 1M window) - consider /compact at the next logical boundary` | `Context ~254k tokens @ 25% - consider /crunch \| /compact (1M window)` |
| The count's first | `[Crunch] 50 edits and writes so far - consider /compact if moving to a new phase` | The size's line, or with no size to read, `50 edits and writes - consider /crunch \| /compact` |
| The count's later ones | `[Crunch] 75 edits and writes - a good checkpoint for /compact if the context is stale` | As for the first |

Where the window is assumed rather than set or detected, both leave out the share and the window. The skill is
named by the folder it is installed in. The notice that the transcript can't be read goes to the developer alone,
and keeps the tag, since it has to say where it comes from.

## The state folder and its records

The hooks keep each session's state in a folder of their own: `crunch` under `%LOCALAPPDATA%` on Windows,
else under `%USERPROFILE%\AppData\Local`, and elsewhere under `$XDG_STATE_HOME` when that is an absolute path,
else under `~/.local/state`. Each file is named by the session's id and holds one number, written to a temporary
file and renamed into place.

| File | Written by | Holds | Read by |
|---|---|---|---|
| `<session>.count` | `suggest-compact.js`; `on-compact.js` removes it | The edits and writes since the session started or last compacted | `suggest-compact.js` |
| `<session>.level` | `suggest-compact.js`; `on-compact.js` removes it | The context level it last nudged at | `suggest-compact.js` |
| `<session>.notice` | `suggest-compact.js` | That the notice that the transcript can't be read has been given | `suggest-compact.js` |
| `<session>.nudged` | `suggest-compact.js`, before it answers | The calls it told Claude to consider `/compact` on: one for each, however many lines its answer holds, and none for the notice | `crunch` |
| `<session>.manual` | `on-compact.js` | The compactions that stood with trigger `manual`: a typed `/compact`, and the mod's own | `crunch` |
| `<session>.auto` | `on-compact.js` | The compactions Claude Code made by itself, trigger `auto` | `crunch` |
| `<session>.plugin` | `on-compact.js` | The compactions another plugin's `$.session.compact` made, trigger `plugin` | `crunch` |

The last four are the records, and they only rise through a session: `on-compact.js` leaves `.nudged`, and adds
one to its trigger's record before it removes `.count` and `.level`. A subagent's call or compaction writes
nothing. On a session's first call, and on its first after each compaction, `suggest-compact.js` sweeps the folder
of other sessions' files older than `COMPACT_STATE_TTL_DAYS`, keeping its own session's files. It removes only
files named as above, and the temporary files a failed write leaves, so that a folder called `crunch` that another
program also keeps there loses nothing of that program's.

A Claude Desktop session on Windows writes elsewhere. Desktop is an MSIX package, `Claude_pzs8sxrjxfjjc`, and
Windows redirects what its process tree writes under `AppData\Local` into
`%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local`, so its sessions' state is in `crunch`
there. Inside the package the real path reads as both folders merged, so the hooks and the mod, which run in one
process tree, each find the session's files where they look. A shell outside the package, SSH's among them, finds
a Desktop session's files only in the package's folder, and no `%LOCALAPPDATA%\crunch` at all on a
machine where only Desktop has run the hooks. Seen with Desktop 3.6556.2.0 on 2026-10-26, and from a mod inside
Desktop on 2026-10-29.

## crunch, the mod

In Claude Desktop the developer's line is kept in the transcript but not shown, so only Claude sees a nudge.
`crunch` shows it there, and with its band on offers to compact on a focus the session drafts. It is a mod, a
Claude Code plugin whose hooks are a TypeScript module: `../.claude-plugin/plugin.json` declares it, `hooks.json`
here names its module, `crunch.tsx`, and `../types/index.d.ts` declares what it keeps in `$.state`, the band and
whether a `/compact` is under way. Claude Code loads it from the installed skill's folder, so it comes with the
skill and needs no Node.js and no registering; it is loaded again when its settings change. Its tests,
`crunch.test.ts`, sit beside it for `claude plugin test`. It wants Claude Code 2.1.300 or later, and is checked on
2.1.304: 2.1.280 refused its first version, its validator rejecting `$` passed to `update` and not knowing
`$.ui.notify`, both of which this one uses too, and said so only in its debug log. The skill and its hooks work
either way.

It learns of nudges and compactions from the hooks' records, above, read through `$.fs` in the folder `state.js`
picks, found through `$.env.get` and named by `$.session.id()`. It reads them on events that reach a person's
plugins under any account: at each main tool call's `tool.check`, which fires after the PreToolUse hooks and before
the tool runs, and again once the call returns; at each main turn's start and end; around a `/compact` it sees
through `command.run`; and after its own. So it works the same where Claude Code's security plugin is seated, as
under a Team or Enterprise account, which keeps the `classic.*` events and `session.compact` from a person's
plugins: the repository's `docs/hook-messages-and-mods.md` has what it passes over. The events and calls the mod
rests on ran there under 2.1.309, seen with a probe on 2026-10-29. Without the hooks registered the mod sees no
nudge and no compaction: it shows the status line alone, and adds no note.

A read under a session id it hasn't read yet takes the counts as they stand for its start: at `session.start`,
which fires again whenever the mod loads, and at the first turn after `/clear` or on resuming another session. So
a reload or a switch of session shows nothing old, and a switch drops what the mod kept for the session before, its
band and a draft on the way included. The first read after that to find `.nudged` risen is a nudge, shown as its
call starts. A subagent's calls and turns read nothing.

At a nudge it shows ``Context ~82k tokens @ 8% - consider `/crunch` | `/compact` (1M window)``, each
command in backticks, which the band draws as code; a nudge with no size to read waits for the next reading. The
size and the window are Claude Code's own, from `$.session.usage()`, so where `ECC_CONTEXT_WINDOW_TOKENS` is set,
or an unlisted model is taken as 200k, its share can differ from the hook's. The notice that the transcript can't
be read is no nudge, so it isn't shown; `check-transcript.js` checks by hand.

A record's rise is a compaction that stood, and the record says whose it was:

| Record | Whose | The hint | The band |
|---|---|---|---|
| `.manual` | The developer's: a typed `/compact`, Compact now, or Enter in the band's field | Turned off | Taken down |
| `.auto` | Claude Code's own, inside a turn | Turned on | Left |
| `.plugin`, or `.manual` while another plugin's `/compact` runs | Another plugin's, told by the `origin` that `command.run` hands on | Left | Left |

Each drops a draft on its way, and adds the note, below. One seen as a `/compact` resolves
hides the status line until the next response, since the size may still read from before it; Claude Code's own is
first seen after a response, so the status line is read afresh there.

| Part | Switch | Default | Where | Shows or does |
|---|---|---|---|---|
| Status line | `showStatusLine` | On | Everywhere | `Context @ 8%` after each tool call and turn, once there is a size, and `Context @ 8% · /compact` from a nudge, or a compaction Claude Code made by itself, until the developer's `/compact`; hidden by a reading with no size, and by a `/compact` until the next response |
| Toast | `showToast` | On | Off a terminal | The nudge |
| Log line | `showLog` | On | Off a terminal | The nudge, as a dim line in the transcript that stays after the toast has gone and isn't sent to Claude |
| Band | `showBand` | Off | A terminal and Claude Desktop | The latest nudge above the prompt, with a field holding the focus for `/compact` and Compact now, below, until a press, Dismiss, the next nudge or the developer's `/compact` |
| Notification | `showNotification` | Off | Everywhere | The nudge, as a native notification through the terminal's channel; Claude Desktop shows none |
| Note | `addNote` | On | Everywhere | After each compaction, a note telling Claude to read the project's `PROGRESS.md` first, below |

Off a terminal means while something other than a terminal draws the session, as Claude Desktop does: a terminal
prints the developer's line already, so a toast there would be a second copy, and the band leaves the line out.
Each switch is a row in `/config`, kept in `~/.claude/settings.json` under the manifest's name and where the mod
was loaded from, as `"pluginConfigs": { "crunch@skills-dir": { "options": { "showBand": true } } }`. At each
session start the mod writes one line to the debug log, `claude --debug`: each switch, and the surfaces the session
draws on.

### The band

From the top, each part only when it has something to show:

- the nudge's line, its commands drawn as code, off a terminal;
- the context's three largest parts, from `$.session.usage({ breakdown: 'summary' })`, as
  `Messages 180k · Tool results 62k · System tools 21k`;
- the session's WAIT, below, as `Claude is mid-implementation: <its reason>`;
- the field, labelled `/compact `, holding what the developer typed there, else the draft, else
  `state in PROGRESS.md` where the session's root holds that file; then Compact now, or a dim `compacting…` while a
  `/compact` the mod didn't run is under way; then Dismiss;
- a message where the mod's own `/compact` failed: `Not compacted: <the command's output>` where it was refused, as
  by a `PreCompact` hook, and `Not compacted: the turn was stopped before it ran. Compact again.` where the turn it
  waited for was stopped and dropped it.

Compact now, or Enter in the field, takes the band down at once and runs `/compact` on the field's text through
`$.command.run`, as the developer would type it; while a turn runs, Claude Code queues it for the turn's end. One
press runs one `/compact`, and none starts while another is under way. A refused or dropped one brings the band
back with its message. One that leaves no record and no output shows nothing: the mod writes it to the debug log
and reads the records again at the next turn's start. The band isn't drawn on a mobile surface, nor while Claude
Code shows a survey above the prompt.

### The draft and its prompt

At the end of a main turn that saw a nudge, one Claude answered rather than one stopped or broken, the mod asks a
fork of the session for the focus, through `$.model.fork`, once its `turn.complete` hook has returned. It asks only
while the band is on. The prompt, with its sentence on `PROGRESS.md` only where the session's
root holds that file:

> crunch is about to offer a /compact. Answer in one line and nothing else. If you are in the middle of
> implementing something, with names, paths or half-made edits a summary would lose, answer WAIT: and what you are
> in the middle of. If PROGRESS.md doesn't yet record where the work stands, answer WAIT: and what it's missing.
> Otherwise answer the focus for /compact: what the next phase is and what it needs kept, in at most 25 words.

A reply that begins `WAIT`, in any case and past any emphasis or quote marks, is a WAIT, shown in the band with the
rest of its line as the reason. Any other reply is the draft, joined onto one line, with `; state in PROGRESS.md`
added where that file is there and the reply doesn't name it. A compaction, or a switch of session, while the fork
runs drops its reply. Each fork writes a line to the debug log, as `fork: answered in 1234 ms`, with the usage it
reports.

### The note: `addNote`

On by default. After each compaction that stood, whoever's it was, and where the session's root holds
`PROGRESS.md`, the mod appends a message through `$.session.append` that Claude reads and the developer doesn't
see: `` This conversation was just compacted. Before carrying on, read `C:\work\PROGRESS.md` for where the work
stands. ``, the path joined with the root's own separator. A compaction seen inside a turn, as Claude Code's own
is, holds its note until the turn ends, so the note never lands between a tool call and its result.

## Configuration

The hooks read these from the environment of the Claude Code that runs them: the shell it was started from, for one
session, or the `env` of `~/.claude/settings.json`, for every session, as `"env": { "COMPACT_THRESHOLD": "80" }`.
A value in `settings.json` wins over the shell's and applies once the file is saved, so a variable set there must be
taken out of it before the shell can set it for one session. A value the hook can't use gives the default.

| Variable | Default | Sets | Takes |
|---|---|---|---|
| `COMPACT_CONTEXT_THRESHOLD` | 250,000 on a window of 1M or more, 160,000 on a smaller one | The context size of the first nudge | A whole number up to 10,000,000; `0` turns the size check off |
| `COMPACT_CONTEXT_INTERVAL` | `COMPACT_CONTEXT_THRESHOLD`'s, so the nudges come at its multiples: 250k, 500k and 750k of 1M | The context between one nudge's level and the next | A whole number up to 10,000,000 |
| `COMPACT_THRESHOLD` | 50 | The edits and writes before the count's first nudge | 1 to 10,000 |
| `COMPACT_INTERVAL` | `COMPACT_THRESHOLD`'s, so the nudges come at its multiples: 50, 100, 150 | The edits and writes between the count's nudges | 1 to 10,000 |
| `COMPACT_STATE_TTL_DAYS` | 14 | The age at which other sessions' state files are swept | 1 to 3,650 |
| `ECC_CONTEXT_WINDOW_TOKENS` | Unset | The context window, for a model whose window the hook guesses wrong | A whole number |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Unset | Claude Code's own auto-compact window, taken as the window when `ECC_CONTEXT_WINDOW_TOKENS` is unset | A whole number |

Without either window variable, a model whose id carries `[1m]`, or is of a listed family, `claude-opus-5`,
`claude-fable-5` or `claude-mythos-5`, has a 1M window. Any other model counts as 200k until its context passes
that, and as 1M after. A nudge gives a percentage of the window only when the window was set or detected, not
inferred from the context's size.

`../env.json` declares the six that are the hooks' own, each with what it takes, and the mod's manifest declares
its switches, above. `Install-Skills.ps1` offers both when it installs the skill, showing the change to
`settings.json` before writing it, and `-Configure crunch -Apply` asks again later.

Fixed in code, with no variable:

- `suggest-compact.js` runs before every tool call, matcher `*`, with a 10-second timeout, as `../hooks.json` says.
- Only Edit and Write count toward the edit count. A subagent's call counts nothing and says nothing.
- The notice that the transcript can't be read comes once per session, from the fifth edit or write on.
- A compaction of the session, whatever its trigger, starts the edit count and the context level again.
- The transcript is read from its last 256 KiB, and up to 4 MiB back when that holds no size.
- State is kept per session in the state folder, above.

## Where each file came from

From [affaan-m/ECC](https://github.com/affaan-m/ECC) at `b92f181b3b748d1abbc2afd94af6aa7d8c8fca29`, under its MIT
license, in `../LICENSE`. A copy of it at `worldflowai/everything-claude-code` has no license file and a January
version of the hook, whose counter never passes 1.

| File | From | Changed |
|---|---|---|
| `file-tail.js` | `scripts/lib/file-tail.js` | Nothing |
| `transcript-context.js` | `scripts/lib/transcript-context.js` | Bugs 4 and 5 below, each marked `bb-skills` in the code |
| `suggest-compact.js` | Rebuilt from `scripts/hooks/suggest-compact.js` | Its two signals, thresholds, variables and most wording kept; the rest is new |
| `hook-io.js` | In place of the 742-line `scripts/lib/utils.js` | Only reading input and writing the answer |
| `state.js`, `on-compact.js`, `transcript-probe.js`, `check-transcript.js` | New | — |
| `crunch.tsx`, `crunch.test.ts`, `hooks.json` here, `../.claude-plugin/plugin.json`, `../types/index.d.ts`, `../env.json` | New | — |

In `../tests`, `file-tail.test.js` and `transcript-context.test.js` are upstream's, with the lines that find the
code changed and `bb-skills` sections added. `suggest-compact.test.js` draws on upstream's cases;
`upstream-bugs.test.js` holds one test for each bug below, and the rest are new.

## What it reads, which isn't documented

The context size is the latest assistant record's `message.usage` in the session transcript: `input_tokens`,
`cache_read_input_tokens` and `cache_creation_input_tokens`, summed. A compaction's `compact_boundary` record gives
the size it left. Claude Code calls the transcript only "conversation JSON", so this shape can change without notice.
When the hook finds no size from the fifth edit or write of a session on, `transcript-probe.js` says what is missing
and the developer is told once per session; `check-transcript.js` runs the same check by hand. Other tools' calls
don't bring the notice on, so a session that never edits is never told.

A response's records reach the transcript only after its first tool call has started, so that call's hook reads the
response before, and a session's first response has none before it: the hook is silent on a session's first calls,
when the context is at its smallest. Observed on Claude Code 2.1.300, with `CLAUDE_CODE_EAGER_FLUSH` and without;
`PostToolUse` and `UserPromptSubmit` found nothing there either. So a test of the hook needs a second response.

## The bugs fixed

| | In upstream's hook | Now |
|---|---|---|
| 1 | Silent for the rest of a session after its first compaction: the step it last fired at was never reset | It keeps the token level it last fired at, cleared below the threshold |
| 2 | A reminder skipped when an unlisted model's window estimate moved from 200k to 1M mid-session | The same level |
| 3 | The edit count ran on through a compaction | `on-compact.js` starts it again |
| 4 | While the transcript lagged a compaction, it read the size from before it | The scan stops at a compaction boundary |
| 5 | Silent when the latest usage sat more than 256 KiB from the end, behind a large tool result | It looks up to 4 MiB back |
| 6 | Input over 1 MiB, as a large Write carries, became `{}`, merging every such session into one called `default` | Up to 16 MiB is read; input it can't use counts nothing |
| 7 | Its count of edits and writes called them "tool calls" | It says "edits and writes" |
| 8 | Every call listed the whole OS temporary folder to sweep old state | State has a folder of its own, swept on a session's first call |
| 9 | State files in a shared `/tmp` were opened through symlinks and truncated | That folder is in the user's own state folder, and refused if it is a link |
| 10 | On Windows its careful counter write always failed and fell back | Writes go to a temporary file renamed into place |
| 11 | A subagent's edits counted toward the session, and its nudge went into the subagent | A subagent's call counts nothing and says nothing |

Two things stay as upstream had them: two calls run in parallel can read the same state and show the same line, and
the table of model context windows lags new models. `ECC_CONTEXT_WINDOW_TOKENS` sets a window it guesses wrong. A
third stays because nothing can change it: the silence on a session's first calls, above.
