---
description: Turn a request into a bounded, executable task with acceptance criteria
argument-hint: <what needs to be done>
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

Read `.ai/workflows/start-task.md` and follow it. It holds the steps, the stop conditions, and the
standard for observable acceptance criteria.

**Request:** $ARGUMENTS

Create the record with:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/new-task.ps1 -Title "<title>" -Type task -Status inbox -Priority medium
```

```bash
bash scripts/ai/new-task.sh --title "<title>" --type task --status inbox --priority medium
```

Templates: `.ai/tasks/templates/`. Planning triggers: `.ai/contract/lifecycle.md` §3.
