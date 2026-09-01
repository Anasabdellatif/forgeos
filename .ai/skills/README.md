# Skills

Reusable techniques for common engineering activities. Portable across tools.

## Available Skills

| Skill | Use for |
| --- | --- |
| `codebase-navigation.md` | Locating relevant code without scanning the repository |
| `debugging.md` | Isolating a root cause with evidence and controlled experiments |
| `refactoring.md` | Improving structure without changing observable behavior |
| `test-generation.md` | Designing meaningful tests from acceptance criteria and risk |
| `documentation-update.md` | Updating the correct canonical document, without duplication |

## This directory is the single source of truth

Each file here holds the whole technique: objective, method, constraints, efficiency guidance, and
the output owed.

`.claude/skills/<name>/SKILL.md` carries only the description that drives auto-triggering plus a
pointer back here — 8 lines, no method. **That is enforced, not requested:** `check-policy` fails
the build on an adapter over 20 lines or carrying a section such as `## Method` or `## Never`. The
controls live in `scripts/validation/check-policy.ps1`; the rule they enforce is section 1 of
`.ai/rules/documentation.md`.

Codex and other tools load these files directly.

## Usage

Load a skill only when the current task calls for it.

A skill is a **technique**, not permission. It never authorizes exceeding task scope, bypassing a
repository rule, or skipping a safety control.
