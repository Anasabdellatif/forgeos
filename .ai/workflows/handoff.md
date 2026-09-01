# Handoff Workflow

## Objective

Preserve only the context needed for another agent or session to continue safely and efficiently.

## When to Use

Create a handoff when work is unfinished, blocked, interrupted, transferred, or expected to continue in another session.

## Steps

1. Identify the active task and plan paths.
2. Summarize the current objective and confirmed state.
3. List completed work and changed files.
4. Record exact validation commands and observed results.
5. List remaining work in priority order.
6. State blockers, unresolved decisions, assumptions, warnings, and risks.
7. Provide the exact next recommended action.
8. Link to relevant code, documentation, decisions, lessons, or incidents.
9. Save the handoff in `.ai/memory/handoffs/` using the handoff template.
10. Refresh `.ai/context/current-state.md` so the next session starts from the ledger and finds
    the handoff through it — see `.ai/contract/economy.md`.

## Which Context Package

`scripts/ai/build-context` packages the work for transfer. Choose the mode by asking one
question: **can the receiving side be trusted to read `CLAUDE.md`, `AGENTS.md`, and
`.ai/context/` for itself?**

| Mode | Use when | Cost |
| --- | --- | --- |
| `--minimal` / `-Minimal` | A handoff inside this project, to a session or agent that loads the contract the same way every session does | roughly a quarter of full |
| full (default) | Transfer to a tool, model, or person whose environment will not load them | repeats the contract and context verbatim |

Full mode inside this project is redundant context: the receiving session has already loaded
every file it repeats. Prefer minimal and let the contract do its own job.

## Rules

- Keep the handoff concise and factual.
- Do not paste raw conversation history or large logs.
- Do not include secrets or speculative claims.
- Do not repeat information that is already available in a linked source.

## Output

A continuation record that allows safe progress without reloading the full repository or conversation.
