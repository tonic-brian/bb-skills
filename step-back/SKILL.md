---
name: step-back
argument-hint: "[plan | wip | branch]"
description: >-
  Take a step back and adversarially review a proposed plan, the code in progress, or the whole branch since
  base, before more work piles onto it. Use this WHENEVER the developer says "step back", "take a step back",
  "poke holes in this", "red-team this", "what's wrong with this approach", "adversarially review the plan",
  "review the diff before I commit", "review everything since main", or "play devil's advocate" — even when
  the whole message is just "step back". Read-only for work in progress and a branch, ending in ranked
  objections and a verdict; a DRAFT plan gets the review's own fixes and one more read — one round per draft,
  two drafts at most, then it asks.
---

# Step back

Leave the thread you were on and read the artifact as a skeptical reviewer who never saw the work: assume it
is wrong somewhere, and find where. For work in progress and a branch the review changes nothing; fixing as
you go turns it back into the momentum it was meant to interrupt. A **draft plan** is the exception: a draft
is still being written, so the review is one round of its iteration and applies what it found (see 4).

## 1. Pick the target — and say which

The developer's if they named one, else the first row that applies; open the review by naming your pick.

| Target | When | What you read |
|---|---|---|
| **plan** | a plan was just proposed, or a draft plan is awaiting approval | the plan, plus the ask it answers |
| **wip** | the working tree is dirty | `git diff HEAD` and `git status --short` (untracked files too) |
| **branch** | tree clean, branch ahead of its base | `git diff main...HEAD` — all commits since the default branch |

## 2. Re-derive the goal before re-reading the work

Write down in your own words what was asked and what done looks like, from the original request, not the
artifact's framing: the artifact argues for itself. Then read it against that; every gap is a finding.

## 3. Attack it

The strongest objection, not a list of nits, each with evidence: a line, a section, a command's output. What
you can't point at is a hunch, labeled as one. Where it hides, by target:

- **plan**: the assumption that sinks everything if false; the step with no verification named; the
  irreversible step; the alternative dismissed in a sentence; the "and then it works" gap; anything the plan
  decided that the developer never said.
- **wip / branch**: spec, tests and code disagreeing; a test that cannot fail (built from the constant it
  asserts on, or setup that can't reach the state it names); the error path or edge nobody ran; the same
  defect elsewhere (search for it); files the ask never implied; behavior bent to pass a check that was wrong.

## 4. Report: objections ranked, then a verdict — and, for a draft plan, the next round

Strongest first, each with its evidence and the smallest fix that answers it. Then one verdict: **proceed**
(nothing changes course; say where you looked), **fix first** (the named items), or **rethink** (the framing
or goal is off; name what must change).

- **wip / branch**: stop there; the developer picks what to act on.
- **plan, still a draft** (its status line says draft, or awaiting approval): don't stop. Apply in place every
  objection that has a stated smallest fix and needs no decision only the developer can make: that is the
  second draft. Read it once more as a fresh skeptical reviewer, re-deriving the goal and attacking again, not
  merely checking that the edits landed. One round per draft, two drafts at most: if the second is at
  **proceed**, done; if not, stop and ask, saying what the loop can't fix — never a third draft without the
  developer. Then report once: per round, each objection and the fix applied, one line each; what remains, as
  numbered decisions for the developer; the final verdict. An **approved** plan is never edited: supersede it
  (see the `plan-file` skill).

## Critical details (easy to get wrong)

- **A clean review says where it looked.** "Looks good" with no named search is the sycophantic failure this
  skill exists to prevent; "checked X, Y and Z, found nothing load-bearing" is a finding.
- **You wrote what you are reviewing.** Re-deriving the goal first guards against reviewing your own framing
  back to yourself; when stakes are high, hand it and the ask to a fresh subagent and reconcile both reviews.
- **Iterating is not deciding.** A locked decision, a stated preference, or a choice the plan tables for the
  developer is listed, never resolved by the loop. Nor does the loop widen scope: a fix that adds a
  deliverable the ask did not imply is a decision, not a fix.
- **Finished work is a different job.** Once the claim is "done", the question is whether the claims are true,
  not whether this was the right thing: a verification pass (re-run the checks, diff what changed).
- **Base means the real base:** `main...HEAD` after a fetch; a stale local `main` reviews the wrong diff.
