# Decisions Memory — The ADR Store

**This directory is the single home for decision rationale.** `docs/architecture/decisions.md` is
an index that links here and holds no reasoning of its own.

Store durable product, architecture, data, security, integration, and operational decisions whose
consequences affect future work.

## Store here

- The precise decision, stated so a reader can act on it.
- The context and constraints that forced it.
- The alternatives considered — at least two, each with its real trade-off.
- Why the alternatives lose. This is the part future readers need most.
- Consequences: what becomes easier, what becomes harder, what is now irreversible.
- Compatibility, migration, rollback, and validation impact.
- **How you would know the decision was wrong.** A decision with no falsification criterion cannot
  be revisited honestly.
- Links to the related task, plan, code, and documentation.

## Do not store

- A reversible implementation preference.
- Anything obvious from reading the code.
- Anything the git history already explains.
- Raw conversations or meeting notes.
- An unapproved assumption presented as a decision.
- Secrets or private data.

## The test

Record it when someone six months from now would otherwise ask **"why on earth is it built this
way?"** — and no file in the repository would answer them.

## Naming

`YYYY-MM-DD-short-decision-title.md`

## Template and example

- Template: `templates/decision-template.md`
- Filled example: `examples/decision-example.md`
- Command: `/adr`

## Maintenance

Mark a replaced decision `superseded`, link both records in both directions, and add the row to
`docs/architecture/decisions.md`.

**Never silently rewrite historical rationale.** Reasoning that turned out to be wrong is often the
most valuable content in this directory — it prevents the same wrong turn from being taken again.
