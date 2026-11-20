---
name: choices
description: >-
  Walk the developer through open decisions one at a time — brief context, two to four choices, and a
  recommendation each — so they settle them interactively without scrolling or opening a plan. Use this
  WHENEVER the developer says "present choices", "walk me through the open decisions", "go through the open
  questions", "what's blocked on me?", or answers a list of open items, deferrals or blockers with "one at a
  time" — even when they just say "choices". Asks in dependency order, records each answer, then resumes.
---

# Choices

Open decisions arrive as a list to scroll through. This makes it a sequence: one item on screen with enough
context to judge it, a few concrete choices and your recommendation — answered, recorded, gone before the
next. They supply the judgment; you supply the framing and the homework.

## 1. Gather every open item first

From wherever they hide: the last report's open questions or "blocked on you", a draft plan's undecided
points, deferrals in the work-state doc, questions raised mid-conversation and never answered. Drop any that
evidence can settle: a question the code, the docs or one command could answer is homework you skipped, so do
it and present the finding instead. Tell the developer the count, then start.

## 2. Ask one at a time, in dependency order

Blockers before deferrals; an answer that would make others moot goes first. Use the harness's interactive
question tool if it has one (Claude Code's AskUserQuestion), one item per call; otherwise write the item as a
short numbered prompt and stop for the answer. Each item stands alone:

- **Context**: one or two lines on what the decision is and what it blocks or changes.
- **Choices**: two to four, one line each with its trade-off, concrete enough that "other" is rare;
  single-select when they exclude each other, multi-select when several can apply at once.
- **Recommendation**: listed first and marked, with a one-line reason. If you can't recommend, the honest
  option is "investigate X first", naming what that would settle.

## 3. Record, then resume

Each answer is a decision: write it where the project keeps them (the plan's decisions table, the work-state
doc's locked decisions) so it never comes back as a question. When the list is empty, restate the decisions in
one line each and pick up the work they unblocked.

## Critical details (easy to get wrong)

- **Never make them scroll.** The context lives inside the item; "as discussed above" and "see the plan" are
  the failures this skill exists to remove.
- **A menu without a recommendation is the same list in a new shape.** The developer is choosing whether to
  overrule you, not doing your thinking for you.
- **One item per turn.** Four questions in one message puts the scrolling back.
- **Attended only.** An unattended run has nobody to answer and must proceed on its own recommendations,
  labeled as such in its report.
