---
description: Build a deterministic context package for handoff to another agent, tool, or session
argument-hint: [task path] [plan path]
allowed-tools: Read, Bash
---

**Arguments:** $ARGUMENTS

Flags, safety behavior, and when a package is worth building: `scripts/ai/README.md`.

Full package for session transfer:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/build-context.ps1 -TaskPath "<task>" -PlanPath "<plan>"
bash scripts/ai/build-context.sh --task "<task>" --plan "<plan>"
```

Subagent role packet (saves ~75% context tokens):

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/build-context.ps1 -Role <role>
bash scripts/ai/build-context.sh --role <role>
```

Do not build one inside a session where the files are already loaded — that is redundant context,
which `.ai/contract/core.md` §2 and §10 tell you to avoid. Packages are gitignored; never commit one.
