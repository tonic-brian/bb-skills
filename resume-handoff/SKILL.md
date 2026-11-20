---
name: resume-handoff
description: >-
  Resume work from a handoff anchor in a fresh session, reconciling the saved state against reality before
  trusting a word of it. Use this WHENEVER the developer sends "resume", "resume from the handoff", "pick up
  where we left off", "continue where the last session stopped", "where were we?", or opens a session by
  pointing at a work-state doc or a session-state note — even when they only paste the anchor text. Finds the
  freshest anchor, checks every claim against git, gh and the filesystem, reports the drift, then starts on
  the first Next item.
---

# Resume from a handoff

A handoff anchor is a snapshot: since it was written, commits may have landed, PRs merged, another machine
pushed. Treat every claim in it as a *hypothesis* and let reality win; trusting a stale anchor means redoing
finished work or building on a branch that has moved.

## 1. Find the anchor — take the freshest

Anchors drift apart: only the outgoing session's *last* refresh is current. Check, in order:

- the project's work-state doc, if it keeps one (`PROGRESS.md` or similar): its status and next steps;
- the agent's cross-session memory, if it keeps one: the resume-anchor note and what it links to;
- whatever the developer pasted inline.

If two disagree, say so and prefer the one whose claims survive step 2; never merge them silently.

## 2. Reconcile every claim against the source that can refute it

```bash
git branch --show-current && git status --short   # branch + working tree ("clean" is a claim; check it)
git log -1 --oneline                              # HEAD — a hash in a doc is always one commit behind
git rev-list --count @{u}..HEAD                   # unpushed (no upstream is a finding too)
git rev-list --count HEAD..main                   # behind main
gh pr list --state open                           # PRs the anchor names, and ones it doesn't know about
```

Also confirm the files the anchor says exist (list them), its dates (relative dates are stale by definition:
is "today" still today?), and whether any "Next" item already landed (`git log --oneline -20`, then look).

## 3. Report the drift, then start

Tell the developer in a few lines what matched, what didn't, and what you now treat as true, then begin the
first "Next" item. If the drift changes what "next" means — a merged PR, a moved branch, a locked decision
reality has overtaken — stop and ask instead of guessing.

## Critical details (easy to get wrong)

- **Locked decisions stay locked.** They are in the anchor so a fresh context doesn't relitigate them; "I'd
  have chosen differently" is not new evidence.
- **A hash written by the commit that produced it is wrong by construction:** `git log -1` is the answer,
  never the doc.
- **Resume doesn't refresh the anchor; handoff does.** But if reconciliation found drift, correct the anchor
  now: the next session inherits what you leave, and a "Next" list doesn't renew itself.
- **Don't re-plan.** The anchor's Next list is the plan; a resume that opens with a fresh proposal throws away
  what the last session paid for.
