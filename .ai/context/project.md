# Project Context

**Operational summary. Loaded every session, so it stays short.** `docs/` owns the facts; this file
holds only what an agent needs *before* it knows which document to open.

## Where the facts live

| Fact | Source of truth |
| --- | --- |
| Product, users, non-goals, success measures | `docs/product/vision.md` |
| Requirements and scope | `docs/product/requirements.md` |
| Architecture, components, data flows | `docs/architecture/overview.md` |
| Domain vocabulary and business rules | `docs/domains/domain-map.md` |
| Technology and commands | `.ai/context/stack.md` |
| Hard constraints | `.ai/context/constraints.md` |
| Decisions · assumptions and open questions | `.ai/memory/decisions/` · `.ai/memory/open-questions.md` |
| Mandatory roles and gates for this kind of system | `.ai/profiles/` |
| Active work | `.ai/tasks/active/` · `.ai/plans/active/` |

## Identity

- Name: AI Project Blueprint → `README.md`
- One line: reusable engineering foundation; other projects adopt it, one contract governs all.
- Stage: `production` — released, versioned, adopted.
- Profile: `none` — blueprint itself, not a system being built. → `.ai/profiles/README.md`
- Promoted roles: `none`

## The three facts an agent must not get wrong

- Primary user: an AI coding agent inside an adopting project; the engineer who maintains the
  blueprint reads it second.
- Most likely mistake: adding surface — another profile, role, or check — instead of proving what
  already exists. See the Not proven section of `README.md`.
- Hardest constraint: cross-platform parity — every script exists as `.ps1` and `.sh` with identical
  behaviour, proven on both in CI. Full list: `.ai/context/constraints.md`

## Rules for this file

- **Keep it under 45 lines.** Loaded every session; depth belongs in `docs/`.
- Never restate facts `docs/` owns. Link instead.
- Completed entries only as facts; unknowns → `.ai/memory/open-questions.md`.
- Any `TBD` here = discovery gate closed. → `.ai/contract/core.md` §0.
