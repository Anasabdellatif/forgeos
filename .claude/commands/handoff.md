---
description: Write a continuation record so another agent or session can resume safely
argument-hint: [reason: blocked | interrupted | transferred | continuing]
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

Read `.ai/workflows/handoff.md` and follow it. The required contents and the standard a handoff
must meet are in `.ai/contract/reporting.md` §4.

**Reason:** $ARGUMENTS

Write to `.ai/memory/handoffs/YYYY-MM-DD-<slug>.md` using `templates/handoff-template.md`.
Reference depth: `examples/handoff-example.md`.
