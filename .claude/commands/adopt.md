---
description: Adopt this blueprint into a project by filling the context files from the real codebase
argument-hint: [project name]
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

**Project:** $ARGUMENTS

Read `docs/adoption.md` and follow it. It holds the full procedure, the order to fill things in,
and the checklist.

For an **empty** project this command is the wrong tool: the discovery gate fires by itself and
`.ai/contract/discovery.md` takes over. This command is for a project that already has code to
derive facts from.

Start with the readiness check:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-placeholders.ps1
```

```bash
bash scripts/validation/check-placeholders.sh
```

**The one rule that governs everything here:** every fact written into `.ai/context/` becomes a
fact every future agent trusts without re-verifying. Derive it from a manifest, a lockfile, or the
real tree — or ask. Never infer it from a filename or a convention.
