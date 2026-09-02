# Current State

**The session starts here.** One screen answering "where are we?", so no session reconstructs it
from history. Refresh at every close, handoff, and final report. Rules: `.ai/contract/economy.md`.

## Position

- Now: idle — v1.15.31. This repository is the public home of ForgeOS. The release adds
  `forgeos prompt`, the session package: session, model, effort, scope, policy, reading order,
  report checklist and a paste-ready prompt, all read from project files, with model and effort
  from the adopter-editable `scripts/lib/session-policy.json` table. 210 self-test cases per
  shell, all 11 validation rows green.
- Next: M-23 — driving a real project end to end through the full work loop, now startable from
  `forgeos prompt` output. Package-manager channels stay deferred with their blockers named.
- Blocked by: none
- Watch: open questions 002 (macOS CI) and 003 (npm name) gate two distribution channels.

## Last known good

- Commit: the release commit for v1.15.31 — this history begins at the public launch.
- Validation: 11 rows green, 2026-09-02; selftest 210/210 in both shells; release 14/14.
- Lesson: an unchecked public page drifts first — which is why `check-public-surface` gates.

## Gates

- Discovery: **closed** — this repository's context is filled; code writes follow governance.
- Governance: `.ai/context/governance.json` — codeAuthorized true for this repository.

## Rules for this file

- Under 30 lines, loaded every session. Point, never narrate — link instead of restating.
- Trigger-only file list: `.ai/contract/economy.md` §1. Unknowns: `.ai/memory/open-questions.md`.
