---
description: Record an architectural or product decision as a durable ADR
argument-hint: <the decision, e.g. "use outbox pattern for order events">
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

**Decision:** $ARGUMENTS

The rules for what belongs in an ADR, what does not, and how to supersede one are in
`.ai/memory/decisions/README.md`. When to record at all: `.ai/contract/lifecycle.md` §5 and §7.

Write to `.ai/memory/decisions/YYYY-MM-DD-<slug>.md` from `templates/decision-template.md`, then
add one row to `docs/architecture/decisions.md`. That index holds no rationale — the record does.

Reference depth: `examples/decision-example.md`. Note especially its **Validation** section: a
decision with no falsification criterion cannot be revisited honestly.
