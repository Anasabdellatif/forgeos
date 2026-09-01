# CLAUDE.md

Entry point for Claude Code. **It holds no rules of its own** — it imports the operating contract so
Claude Code and Codex obey the identical source of truth.

@.ai/contract/core.md

The import above is authoritative. Section 0 is the discovery gate and applies before any other
section; section 2 says what else exists and which trigger loads it. Nothing on this page restates
it.

## Project Entry Points

- Project facts: `.ai/context/project.md`
- Hard constraints: `.ai/context/constraints.md`
- Active work: `.ai/tasks/active/`, `.ai/plans/active/`

## Claude Code Surfaces

`.claude/` is an adapter layer. It duplicates no rules — every file points into `.ai/`.

| Surface | Location | Source |
| --- | --- | --- |
| Subagents | `.claude/agents/` | `.ai/agents/` |
| Slash commands | `.claude/commands/` | `.ai/workflows/` |
| Skills | `.claude/skills/` | `.ai/skills/` |
| Permissions and hooks | `.claude/settings.json` | `scripts/hooks/` |

`.claude/README.md` describes each surface and what it may contain. Permissions and hooks enforce a
subset of the contract mechanically — a safety net against accidents, not a substitute for the
contract and not a security boundary.
