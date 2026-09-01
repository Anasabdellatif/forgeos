# AGENTS.md

Entry point for Codex and any other agent that reads `AGENTS.md`. **It holds no rules of its own.**
Every rule lives in the operating contract, which Claude Code loads through `CLAUDE.md`, so both
tools obey one source of truth.

## Read this first

**`.ai/contract/core.md`, in full, before anything else.** It is authoritative: the discovery gate,
instruction priority, context policy, the non-negotiable rules, execution principles, lifecycle,
validation, safety, reporting, and the reference map.

Section 0 is the discovery gate and applies before any other section.

Then, and only then:

- `.ai/context/project.md` — stable project facts
- `.ai/context/constraints.md` — hard constraints
- The active task in `.ai/tasks/active/`

Section 2 of the contract says what else exists and which trigger loads it. Nothing is loaded by
default, and nothing on this page substitutes for reading it.

## Where things live

- Engineering rules: `.ai/rules/` · Procedures: `.ai/workflows/` · Techniques: `.ai/skills/`
- Roles: `.ai/agents/` · Project types: `.ai/profiles/` · Filled records: `examples/`

## Validation

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

```bash
bash scripts/validation/check-all.sh
```
