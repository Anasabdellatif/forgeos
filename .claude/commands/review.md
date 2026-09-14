---
description: Independently review the current change for correctness, safety, scope, and evidence
argument-hint: [diff range or paths, e.g. main..HEAD]
allowed-tools: Read, Grep, Glob, Bash, Task
---

Read `.ai/workflows/review.md` and follow it. It holds the review order, the severity scale, the
independence requirement, and the rules.

**Scope:** $ARGUMENTS (default: the working diff plus staged changes)

Get the diff:

```bash
git status && git diff && git diff --staged
```

Build the subagent role packet (saves ~75% context tokens):

```bash
powershell -File scripts/ai/build-context.ps1 -Role reviewer
bash scripts/ai/build-context.sh --role reviewer
```

Pass the packet and diff when delegating to the `reviewer` subagent. Delegate to `security-reviewer`
when the change touches auth, data, input, secrets, execution, or infrastructure.
