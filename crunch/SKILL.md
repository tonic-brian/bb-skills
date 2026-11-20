---
name: crunch
description: >-
  Decide when to compact the context, and how, so a long session keeps what the next phase needs. Use this
  WHENEVER the developer asks "should I compact?", "is it time to /compact?", "compact now or later?" or says
  "the context is getting full", or a [Crunch] line appears — and at a phase change in a long
  session, even when nobody mentions compacting. Compacts between phases, after writing the state to a file.
compatibility: Claude Code, Node.js
---

# Crunch

Compaction keeps a summary and loses the rest: the reasoning, the files read, the developer's exact words.
Auto-compaction fires when the window is nearly full, usually mid-task. Compacting on purpose, between phases
and with the state written down first, keeps what the next phase needs. `<skill>` is this skill's folder.

## 1. Decide whether this is the moment

| Moving from | To | Compact? |
|---|---|---|
| Research | Planning | Yes: the plan is the distilled result |
| Planning | Implementation | Yes, once the plan is in a file |
| Implementation | Testing | Maybe: not while the tests lean on code just read |
| Debugging | The next task | Yes: the traces are noise now |
| A failed approach | Another | Yes: clear the dead end first |
| Mid-implementation | — | No: names, paths and half-made edits are costly to lose |

## 2. Write down what must survive

- **Files survive; the conversation doesn't.** CLAUDE.md, memory, files on disk and git state come through;
  reasoning, file contents read, tool output and preferences said in passing don't.
- **Put the plan, the decisions and the next step in the project's plan or work-state file** first. A task
  list is no record: this Claude Code may not have one.

## 3. Suggest the compaction, with its focus

Only the developer compacts: a typed `/compact` or the mod's Compact now.
Suggest it with what comes next, as `/compact auth middleware next`, naming the state's file to read first.

## 4. Read a `[Crunch]` line as a prompt, not an order

The optional hook writes one before a tool call: at about 160k tokens of a 200k window, or 250k, 500k and
750k of 1M, and at 50, 100 and 150 edits and writes. It says *when*; step 1 decides *if*.

```bash
node "<skill>/hooks/check-transcript.js"    # 0 when the hook can read this Claude Code's transcript
```

- **Variables tune it,** with defaults in `<skill>/hooks/README.md`: `COMPACT_CONTEXT_THRESHOLD`,
  `COMPACT_CONTEXT_INTERVAL`, `COMPACT_THRESHOLD`, `COMPACT_INTERVAL`. `~/.claude/settings.json`'s `env` sets
  them for every session, over the shell's, once saved: take one out to set it per session.
- **Install offers the hook, the variables and the mod's switches;** `-AddHooks crunch -Apply` adds the hook
  again, and `-Configure crunch -Apply` asks again. Its mod shows nudges, with Compact now.

## Critical details (easy to get wrong)

- **Never compact mid-implementation.** The summary keeps the goal and drops the details the next edit needs.
- **Write the state down first, every time.** After a compaction, what isn't in a file is gone.
- **A line that the transcript can't be read means no size check:** run the check above; tell the developer.
- **An unlisted model counts as 200k until it passes that.** A 1M model's first nudge then comes at 160k;
  `ECC_CONTEXT_WINDOW_TOKENS`, or else `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, sets its window.
