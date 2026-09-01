---
description: Run or resume the discovery interview that defines an undefined project. Fires automatically when .ai/context/ still has blocking TBD markers; invoke manually to revisit a phase after a pivot.
argument-hint: [--phase 1..6] [project idea]
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Task
---

Read `.ai/workflows/discovery.md` and follow it. The gate, the six phases, the interview rules, and
the completion criteria are in `.ai/contract/discovery.md`.

**Input:** $ARGUMENTS

Check the gate first:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-placeholders.ps1
```

```bash
bash scripts/validation/check-placeholders.sh
```

If `--phase <n>` was given, run that phase only. Delegate phase 5 to the `architect` subagent;
diagrams follow `.ai/rules/diagrams.md`. On completion, scaffold with `scripts/ai/scaffold`.

Reference depth: `examples/discovery-example.md`.
