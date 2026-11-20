---
name: agent-times
argument-hint: "[agent id ...]"
description: >-
  Show how long each agent of this Claude Code session has run, its state, and how long since it last wrote.
  Use this WHENEVER the developer asks how long an agent has been running, whether an agent is stuck, hung,
  done or still working, which agents are still going, or types /agent-times, with or without an agent's id.
  It runs one Node.js script over the session's own files and prints a table; it never stops or messages an
  agent.
compatibility: Claude Code, Node.js
---

# Agent times

One script reads the files where Claude Code keeps this session's agents and prints, for each: what it is,
who started it, when, its state, how long it ran, when it last wrote, and which record decided its state.
`<skill>` is this skill's folder.

## 1. Run it, passing the developer's words on

```bash
node "<skill>/agent-times.js" [words]
```

- **An agent's id, or its start** (`a2d0ff`), as bare words: only those agents. Several are fine.
- **"In the last N hours"**: `--hours N`, from 1 to 8760; the default is 24.
- **Another session**: `--session <id or its start>`, found in any project. **Another project's newest**:
  `--project-dir <dir>`.
- **`--json`** when you will compute from it rather than show it: times in ISO 8601, durations in seconds.

It finds this session by `$CLAUDE_CODE_SESSION_ID`, and the header's last words say what chose the session.
If they say otherwise and the developer meant this one, say so before reading the table.

## 2. Read the table

| State | Means |
|---|---|
| `running` | It wrote within the last 15 minutes (`--quiet-minutes`) |
| `quiet` | Nothing for 15 minutes, and nothing says it ended: one long step, or stopped unseen. Not dead |
| `finished` | A record says it ended; `From` names which |
| `failed`, `killed`, `stopped` | The session's completion notice says so |
| `interrupted` | A foreground agent whose request was interrupted |

`From` names the record: `journal` (its workflow's journal has its result), `prefix` (its `prefix.json`),
`turn` (its own last record ended its turn), `notice` (the session's completion notice) or `report` (a
foreground agent's report came back). It is empty for `running` and `quiet`.

## Critical details (easy to get wrong)

- **`quiet` with an empty `From` isn't dead or hung.** Say how long since it wrote and what it was started
  for: a long build or test step looks the same. Only the agent's next write, or the developer, tells more.
- **`finished` is the state at that moment.** A stopped agent can be woken, most often by a follow-up from
  whoever started it, and then reads `running` again.
- **The files it reads are undocumented.** When agents that plainly ended read `quiet` with nothing in
  `From`, Claude Code's files have changed: say so rather than guessing a state.
- **Some it can't settle:** a stopped workflow's agents with no journal result, and an agent another agent
  started, whose notice lands in that agent's transcript. Both stay `quiet` unless their own turn ended.
- **No `node` on PATH:** tell the developer the skill needs Node.js 18 or later, and that `pwsh -NoProfile
  -File "<skill>/setup.ps1"` checks for it. Don't read the files by hand instead.
