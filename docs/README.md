# Documentation Index

Documentation is split by **source-of-truth responsibility** so an agent can load only what a task
needs, and so no fact has two homes.

## Start here

- **`adoption.md`** — how to take this blueprint into a real project. Read it first.

## Areas

| Directory | Owns | Load when |
| --- | --- | --- |
| `product/` | Vision, requirements, scope, users, acceptance expectations | Deciding *what* to build or whether a change is in scope |
| `architecture/` | System boundaries, data flows, integrations, quality attributes, technical constraints | Changing structure, contracts, or data models |
| `domains/` | Domain vocabulary, bounded contexts, business rules, ownership | Naming things, or implementing a business rule |
| `design/` | Design principles, UI patterns, accessibility, content and interaction standards | Building or changing a user interface |
| `operations/` | Deployment, configuration, environments, monitoring, incident response, backup, recovery | Deploying, diagnosing, or recovering |
| `archive/` | Historical material that is no longer authoritative | Understanding why something used to be different |

## Where decisions live

`architecture/decisions.md` is an **index only** — one row per decision, with a link. The record
itself, with its context, alternatives, rationale, and consequences, lives in
`.ai/memory/decisions/`.

There is exactly one place to read a decision's rationale, and it is not this directory.

## Boundary with `.ai/`

| Directory | Audience | Contains |
| --- | --- | --- |
| `docs/` | Humans and agents | What the system *is* and *does* |
| `.ai/contract/` | Agents | How to work, decide, verify, and report |
| `.ai/rules/` | Agents | How the work is written |
| `.ai/context/` | Agents | The compressed always-loaded facts, pointing here for depth |

`.ai/context/structure.md` is a fast navigation map. `docs/architecture/overview.md` is the
explanation. They are not duplicates and neither replaces the other.

## Rules

- One canonical source per fact. Link, never copy.
- Separate confirmed facts from assumptions, proposals, and unresolved questions.
- Update documentation in the **same change** that alters behavior, contracts, configuration,
  architecture, operations, or a security assumption.
- Replace stale guidance; do not append a correction beneath it. Move superseded documents to
  `archive/` with a header saying what replaced them.
- Never store secrets, credentials, personal data, internal hostnames, or raw unbounded logs.

Full rules: `.ai/rules/documentation.md`.
