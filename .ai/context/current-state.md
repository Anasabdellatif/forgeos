# Current State

**The session starts here.** Refresh at every close, handoff, and final report. Rules: `.ai/contract/economy.md`.

## Position

- Now: idle — v1.20.1. A patch release for two reproducibility defects a real adoption found:
  the PowerShell self-test no longer reads a child engine's UTF-8 output through the console pipe,
  so the suite returns the same verdict whatever the console code page is; and a reference to a
  file the project's build produces is declared in a project-owned `link-policy.json`, counted, and
  reported as UNVERIFIED when it does not resolve, instead of being called broken in every clean
  checkout. 251 cases per shell, 12 validation rows green.
- Next: M-23 row 8 — a second adopted project resuming from `forgeos brief` and files alone.
- Blocked by: none
- Watch: Q-002 (macOS CI) and Q-003 (npm name) gate two channels; Q-006 protocol unmeasured.

## Last known good

- Commit: the v1.20.1 release commit — this history begins at the public launch.
- Validation: check-all 12 rows green; selftest 251/251 both shells, case lists identical.

## Gates

- Discovery: **closed** — blocking markers present; code writes refused.
- Governance: `.ai/context/governance.json` — codeAuthorized true.

## Rules for this file

- Under 30 lines, loaded every session. Point, never narrate — link instead of restating.
- Trigger-only file list: `.ai/contract/economy.md` §1. Unknowns: `.ai/memory/open-questions.md`.
