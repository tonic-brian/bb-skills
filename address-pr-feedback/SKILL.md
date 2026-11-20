---
name: address-pr-feedback
description: >-
  Fetch, vet, and act on review feedback left on a pull request, from AI reviewers (codex, Copilot, greptile,
  …) or humans. Use this WHENEVER the developer says there's review feedback on a PR: "address the PR
  feedback", "codex left comments on #1234", "handle the Copilot review", "respond to the reviewers", "there
  are unresolved threads on my PR", or similar — even if they don't name a specific reviewer. Pulls the
  unresolved threads, vets each against the actual code, fixes the real issues, and responds/resolves.
compatibility: GitHub, gh CLI
---

# Address PR feedback

Review feedback is a trigger to act, not a notification to acknowledge: separate real bugs, gaps and smells
from noise, fix what's real, and close the loop on every thread. Never blind-accept, never silently ignore.

## 1. Fetch everything

Find the repo and PR number (`gh pr view` on the current branch, or ask if ambiguous). Pull all three feedback
surfaces; they're separate APIs and each can hold comments:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews     # review summaries + verdicts
gh api repos/<owner>/<repo>/pulls/<n>/comments    # inline (line-level) review comments
gh api repos/<owner>/<repo>/issues/<n>/comments   # top-level conversation comments
```

Focus on **unresolved** threads: GraphQL's `reviewThreads` connection exposes `isResolved` to filter inline
threads precisely.

## 2. Vet each item against the actual code

Open the file and the code around each comment and judge it on the merits, not the reviewer's word: AI
reviewers are sometimes confidently wrong, which is the whole reason to vet.

- **Real**: a genuine bug, gap, security issue or smell → fix it.
- **Wrong, already handled or stale** → leave the code; draft a short, specific reply saying why, citing the
  line or test that already covers it.
- **Real but out of scope** → defer deliberately and **name the owning ticket** in your reply.

Never dismiss something because it's inconvenient: "won't fix" needs a concrete justification, not silence.

## 3. Respond and resolve

Reply to each thread with what you did (fixed: reference the commit or diff) or why you didn't (the
justification and ticket). Then **resolve** the threads you addressed, so the PR's unresolved count reflects
reality.

## Respect project-specific exemptions

A project's own docs (`CLAUDE.md`, `AGENTS.md`, contributing notes) may exempt reviewers or tools from this
loop: a scanner whose findings humans triage by hand, a bot whose comments are informational only. Honor it:
don't chase exempted findings, and say so if asked rather than silently skipping.
