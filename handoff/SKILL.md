---
name: handoff
description: >-
  Prepare a clean context handoff so work resumes in a fresh session without losing state. Use this WHENEVER
  the developer says "handoff", "hand off", "let's do a handoff", "prep for /clear", "I'm about to clear
  context", or "save state before I reset" — even when they only imply a deliberate context reset without
  saying the word. Refreshes the resume anchor and AI-facing docs, then says exactly how to resume.
---

# Handoff

A handoff is a deliberate context reset: you write enough state for a fresh session to resume cleanly, then
hand control back to the developer to `/clear` and resume.

## What to do

1. **Refresh the resume anchor**, the durable record of cross-session state (typically a memory file),
   explicit and reconcilable:
   - **Branch** and HEAD commit.
   - **Done**: what landed this session (commits, pushes, PRs opened or updated, decisions made).
   - **Next**: the concrete next steps, in order.
   - **Locked decisions**, so a fresh context doesn't relitigate them.
   - Absolute dates, never relative. Reconcile the anchor against ground truth (`git`, `gh pr`) as you write
     it; never copy a stale claim forward.
   - **Lean: the present, not the past.** HEAD, Next and Locked decisions as short, wrapped Markdown lines,
     never one ever-widening line. An item done and no longer actionable moves to a history file (e.g.
     `<name>-arc.md`): history converges to the arc, the anchor to now.
2. **Refresh the AI-facing docs** a fresh context reads: the area `CLAUDE.md` or working agreements, any
   onboarding doc (e.g. `ONBOARDING.md`), the active plan and progress notes. Update what advanced this
   session, above all status, roadmap and active-branch sections, which drift fastest.
3. **Tell the developer how to resume**, naming the anchor. End with something like:
   > Handoff ready — run `/clear`, then send `resume` as your next message. Resume anchor: <branch + the one-line next step>.

## Critical details (easy to get wrong)

- **`resume` is a plain message, not a slash command.** Never write it as `/resume`, a built-in that switches
  to another conversation, the opposite of what you want.
- **Update the docs yourself; never run `/clear`.** It is the developer's, and it discards the context you are
  writing from.
- **Every outgoing session refreshes, not just the first.** Any session that advances state (commits, merges,
  pushes, opens or updates a PR) refreshes the handoff before its own clear: a "Next" list left behind doesn't
  renew itself, and the snapshot silently desyncs.

## The resume side (why the discipline exists)

A handoff is a snapshot, not a live mirror. A resuming session treats the anchor as a **hypothesis** and
reconciles before trusting it: branch and commits against `git status` and `git log`, open PRs against
`gh pr`, and file mtimes, letting reality win on any conflict. Trusting a stale anchor means redoing finished
work, which this ritual exists to prevent.
