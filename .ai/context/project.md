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

- Name: AI Project Blueprint. Depth: `README.md`
- One line: a reusable engineering foundation other projects adopt, so one contract governs them all.
- Stage: `production` — released, versioned, and adopted by one project so far.
- Profile: `none` — this repository is the blueprint itself, not a system being built, so no
  profile applies and **nothing is enforcing a role set here**, as `.ai/profiles/README.md` requires.
- Promoted roles: `none`

## The three facts an agent must not get wrong

- Primary user: an AI coding agent inside an adopting project; the engineer who maintains the
  blueprint reads it second.
- Most likely mistake: adding surface — another profile, role, or check — instead of proving what
  already exists. See the Not proven section of `README.md`.
- Hardest constraint: cross-platform parity — every script exists as `.ps1` and `.sh` with identical
  behaviour, proven on both in CI. Full list: `.ai/context/constraints.md`

## Rules for this file

- **Keep it under 45 lines.** It is loaded every session; depth belongs in `docs/`.
- Never restate a fact `docs/` owns. Link to it.
- Treat only completed entries as confirmed facts. Never infer a missing one; record it in
  `.ai/memory/open-questions.md`.
- While any `TBD` remains here, the discovery gate is closed. See `.ai/contract/core.md` §0.
