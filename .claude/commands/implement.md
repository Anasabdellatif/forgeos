---
description: Implement the active task as the smallest complete change, validating each step
argument-hint: [task path, or leave empty to use the active task]
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, NotebookEdit
---

Read `.ai/workflows/implement.md` and follow it. It holds the steps, the rules, and when to hand
off to a specialized role instead of implementing.

**Target:** $ARGUMENTS

Subagents available here: `architect` · `tester` · `security-reviewer` · `reviewer`. The workflow
says which signal calls for which.

Report using `.ai/contract/reporting.md` §1.
