---
description: Validate blueprint structure, empty files, placeholders, and hook behavior
allowed-tools: Read, Grep, Glob, Bash
---

Run the suite and report the result under the evidence rule in `.ai/contract/validation.md` §1: a
check is "passed" only if it ran and its output was observed.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

```bash
bash scripts/validation/check-all.sh
```

What each check covers, and why each exists: `scripts/validation/README.md`.

`check-placeholders` is expected to report findings in an unadopted blueprint — every `TBD` marks a
fact the adopting project must supply. That is a readiness score, not a defect. Report the count
and what remains.

Do not summarize as "validation passed" unless every gating check exited 0. If one failed, quote
the failing lines.
