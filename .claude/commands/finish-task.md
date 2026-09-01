---
description: Close the active task only after verifying the full Definition of Done
argument-hint: [task path]
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

Read `.ai/workflows/finish-task.md` and follow it. It holds the steps, what the closure script does
and does not check, and what to do when completion is blocked.

**Task:** $ARGUMENTS

Definition of Done: `.ai/contract/lifecycle.md` §6. Evidence standard: `.ai/contract/validation.md`.

Archive only after every applicable condition holds:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/finish-task.ps1 -TaskPath "<task path>"
```

```bash
bash scripts/ai/finish-task.sh --task "<task path>"
```

Add `-Check` / `--check` to report without moving anything.
