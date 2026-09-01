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
| Decisions · assumptions and open questions | `.ai/memory/decisions/` · `.ai/memory/open-questions.md` |
| Mandatory roles and gates for this kind of system | `.ai/profiles/` |
| Active work | `.ai/tasks/active/` · `.ai/plans/active/` |

## Identity

- Name: TBD: official project name. Depth: `docs/product/vision.md`
- One line: TBD: what this project does, and for whom.
- Stage: TBD: `idea` · `prototype` · `MVP` · `production` · `maintenance`
- Profile: TBD: one of `.ai/profiles/` — `saas` · `erp` · `crm` · `api-platform` · `content-site`,
  or `none` with a stated reason. It decides which roles are mandatory and which gates must pass,
  and `finish-task` reads it. Leaving it unanswered is safer than answering `none` by default.
- Promoted roles: `none`
  Any optional role this project promoted to required, in backticks, or `none`.
  `finish-task` reads this line -- see `.ai/profiles/README.md` for when a role is promoted.

## The three facts an agent must not get wrong

- Primary user: TBD: one segment, stated plainly. Full picture: `docs/product/vision.md`
- Most likely mistake: TBD: the thing most likely to be built even though it is out of scope.
  Full non-goals: `docs/product/vision.md`
- Hardest constraint: TBD: the one that shapes most decisions. Full list: `.ai/context/constraints.md`

## Rules for this file

- **Keep it under 45 lines.** It is loaded every session; depth belongs in `docs/`.
- Never restate a fact `docs/` owns. Link to it.
- Treat only completed entries as confirmed facts. Do not infer a missing one from an example, a
  template, or a conversation — record it in `.ai/memory/open-questions.md`.
- While any `TBD` remains here, the discovery gate is closed. See `.ai/contract/core.md` §0.
