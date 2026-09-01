# Documentation Rules

Ownership, writing standard, and update triggers for documentation.

## 1. Ownership — One Subject, One Home

| Subject | Owner | Never duplicated in |
| --- | --- | --- |
| Product intent, requirements, scope | `docs/product/` | task files, code comments |
| System structure, technical rationale | `docs/architecture/overview.md` | `.ai/context/structure.md` |
| **Individual decisions and their rationale** | `.ai/memory/decisions/` (the ADR store) | anywhere |
| Decision index and status board | `docs/architecture/decisions.md` | — |
| Domain vocabulary and business rules | `docs/domains/` | code comments, product docs |
| Interface and design system | `docs/design/` | component files |
| Deployment, recovery, operations | `docs/operations/` | README |
| Fast navigation map for agents | `.ai/context/structure.md` | architecture docs |
| Agent operating rules | `.ai/contract/` and `.ai/rules/` | `CLAUDE.md`, `AGENTS.md` |

`docs/architecture/decisions.md` is an **index only** — one row per decision, linking to the record
in `.ai/memory/decisions/`. Never write the rationale in two places.

## 2. Writing Standard

- Factual, concise, current, and actionable. If a sentence does not change what a reader does,
  delete it.
- One canonical source; link to it instead of copying. Copied documentation is guaranteed to drift.
- Separate confirmed facts from assumptions, proposals, and unresolved questions — explicitly.
- Include exact commands only when they have been verified in this repository.
- Show the shape of things: a table, a short example, a directory tree beats a paragraph.
- Never include secrets, private data, internal hostnames, or production credentials.
- Write for the reader who arrives with no context and needs to act in five minutes.

## 3. Update Triggers

Update documentation in the same change that alters:

- User-visible behavior
- A public or internal API, contract, or event schema
- Setup, configuration, or environment variables
- Architecture, data flow, or a domain rule
- Deployment, monitoring, recovery, or an operational procedure
- A security assumption or a permission model
- A reusable developer workflow

Documentation updated later is documentation never updated.

## 4. Maintenance

- Replace stale guidance; do not append a correction beneath it.
- Move superseded documents to `docs/archive/` with a header stating what replaced them and when.
- Record a significant long-term choice as a decision record, then link to it.
- Delete documentation that no longer has an owner or a reader.

## 5. Code Comments

- Comment **why**, not what. The code already says what.
- Document non-obvious constraints, invariants, and the reason a surprising approach was chosen.
- Every `TODO` carries an owner and a task reference, or it does not get committed.
- Keep public API documentation adjacent to the API and accurate about failure modes.
