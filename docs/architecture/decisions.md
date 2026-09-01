# Architecture Decisions Index

**This file is an index. It holds no rationale.**

The record — context, alternatives, rationale, consequences, rollback, and how you would know the
decision was wrong — lives in `.ai/memory/decisions/`. One home per decision; this file only points
at it.

Create a record with `/adr`, or from `templates/decision-template.md`. Reference depth:
`examples/decision-example.md`.

## Accepted

Decisions accepted before the public launch are indexed by date, title, and scope; their full
records live in the private development line, and their operative substance is stated where it
applies — the adapter constraint in `CLAUDE.md` and `check-policy`, the channel ladder in
`docs/roadmap.md`. Decisions from this point forward land as records in `.ai/memory/decisions/`
and are linked from this table.

| Date | Decision | Scope | Record |
|---|---|---|---|
| `2026-08-02` | Keep the operating contract in `.ai/`, with thin per-tool adapters | blueprint | pre-launch |
| `2026-08-03` | Place each control where it costs least, and re-test controls that move | enforcement | pre-launch |
| `2026-08-12` | Enforce thin tool adapters for agents and skills | blueprint | pre-launch |
| `2026-08-12` | Keep Claude slash commands as workflow adapters | blueprint | pre-launch |
| `2026-08-29` | Installable means verifiable, not convenient — the channel ladder and what each rung costs | distribution | pre-launch |
| TBD: `YYYY-MM-DD` | TBD: title | TBD: scope | TBD: `.ai/memory/decisions/...` |

## Proposed

| Date | Decision | Owner | Scope | Record |
|---|---|---|---|---|
| TBD: `YYYY-MM-DD` | TBD: title | TBD: owner | TBD: scope | TBD: `.ai/memory/decisions/...` |

## Superseded

| Date | Decision | Superseded by | Record |
|---|---|---|---|
| TBD: `YYYY-MM-DD` | TBD: title | TBD: `.ai/memory/decisions/...` | TBD: `.ai/memory/decisions/...` |

## Rejected

| Date | Decision | Reason | Record |
|---|---|---|---|
| TBD: `YYYY-MM-DD` | TBD: title | TBD: one line | TBD: `.ai/memory/decisions/...` |

## Rules

- **Record a decision when it has long-term consequences** — when someone six months from now would
  otherwise ask "why on earth is it built this way?"
- **Do not record** an implementation detail obvious from the code, a reversible preference, or
  something the git history already explains.
- Add a row here the moment a decision is proposed, accepted, rejected, or superseded.
- **Never delete or rewrite a previous rationale.** Mark it superseded and write a new record. The
  reasoning that turned out wrong is often the most valuable thing in the file.
- Record rejections too. "We considered X and rejected it because Y" prevents the same proposal
  from returning every year.
- Link each decision to the requirement, task, plan, migration, test, or document it affects.
