# Specialized Agents

Role definitions for separating responsibilities during complex work. Portable across tools.

## The Eight Roles

| Role | Owns the question | Delegate when |
| --- | --- | --- |
| `product-analyst` | *What is being asked, and how would we know it worked?* | A request arrives as a sentence; criteria are unfalsifiable; scope is contested |
| `architect` | *What shape should this take, and what does it foreclose?* | Contracts, data models, migrations, or more than one valid path |
| `implementer` | *What is the smallest complete change that satisfies the criteria?* | The change is scoped and approved |
| `tester` | *What evidence proves this works and cannot silently regress?* | Validation design is non-trivial, or a bug needs a regression test |
| `reviewer` | *Is this correct, in scope, and actually verified?* | A change is ready — **and you did not write it** |
| `security-reviewer` | *What is the worst reachable outcome if this is attacked?* | Auth, tenancy, input, secrets, execution, integrations, infrastructure |
| `data-reviewer` | *Is this safe to run, safe to reverse, and correct mid-deploy?* | Schema, migration, backfill, retention, or a hot-path query |
| `release-manager` | *Is the evidence sufficient to put this in front of users?* | Any deploy, migration run, release tag, or flag enablement |

## Three Lenses, Not Three Reviewers

`reviewer` is the general lens. `security-reviewer` and `data-reviewer` are specialized ones that
ask questions the general lens does not: *what does an attacker reach* and *what happens to forty
million rows*. They run alongside `reviewer`, not instead of it.

## What This Directory Deliberately Does Not Contain

Recorded so the question does not return. A role earns a file only when it asks a **different
question**, prevents a **different failure mode**, and cannot be covered by an existing role plus a
rule file.

| Rejected | Why |
| --- | --- |
| `backend-engineer` · `frontend-engineer` | Same operating discipline as `implementer` — understand, change minimally, validate, report. Only the *technique* differs, and technique belongs in `.ai/skills/` and `docs/`. Splitting by technology would also bind this blueprint to a stack it is meant to stay independent of. |
| `database-engineer` | The gap was never a second implementer; it was a missing **review lens**. That is `data-reviewer`. |
| `documentation-maintainer` | Covered three times over: `.ai/rules/documentation.md` owns the rules, `.ai/skills/documentation-update.md` owns the technique, and `check-links` plus the source-of-truth guards enforce it mechanically. A role would add no question. |
| `performance-engineer` | No rule file, no budget, and no target exist yet. A role with nothing to measure against would invent its own standard. Revisit when `docs/architecture/overview.md` carries real quality attributes. |

## In Claude Code

`.claude/agents/` carries only the frontmatter Claude Code needs plus a pointer back here — 8 to 12
lines, no operational content. **That is enforced, not requested:** `check-policy` fails the build
on an adapter over 20 lines, on one carrying a section such as `## Method`, and on any role file
here without a matching adapter or any adapter without a matching role. The controls live in
`scripts/validation/check-policy.ps1`; the rule they enforce is section 1 of
`.ai/rules/documentation.md`.

Codex and other tools read these files directly.

Where another file already owns a subject, the role references it rather than restating it —
`reviewer` points at `.ai/workflows/review.md` for the review order and severity scale. Fixing
duplication between `.ai/` and `.claude/` must not create duplication inside `.ai/`.

## Rule

Agent specialization **never** overrides `.ai/contract/core.md`, the active task, a safety control,
or a repository rule. A role narrows responsibility; it does not grant an exception.

A subagent's report is **evidence to be checked**, not truth to be relayed. Verify claims that
matter before acting on them — `.ai/rules/ai-safety.md` §6.
