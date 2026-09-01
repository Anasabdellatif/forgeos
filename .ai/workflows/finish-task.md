# Finish Task Workflow

## Objective

Close work only after the Definition of Done is satisfied.

## Steps

1. Re-read the task objective and acceptance criteria.
2. Confirm each criterion as passed, failed, blocked, or not applicable.
3. Run the final relevant tests, builds, linters, type checks, security checks, or validation commands.
4. Inspect the final diff and repository status.
5. Confirm no unrelated changes, secrets, temporary files, debug code, or accidental dependencies remain.
6. Update affected product, architecture, domain, design, operations, or developer documentation.
7. Record durable decisions, lessons, incidents, or handoff context when applicable.
8. Refresh `.ai/context/current-state.md` — position, last validation, next action — so the next
   session starts from the ledger, not from history. See `.ai/contract/economy.md`.
9. Write the final report using the format in `.ai/contract/reporting.md` §1.
10. Move the task and completed plan to their `completed/` directories only when all applicable completion conditions are met.

## The Closure Script Is a Gate, Not a Verdict

`scripts/ai/finish-task` refuses to archive a task that still has unchecked criteria, pending
completion evidence, an active blocker, or an unreplaced template placeholder. It exits `2` — a
distinct state meaning "not ready", not an error.

It also refuses a task whose declared **scope tags** demand a role the profile requires, when that
role left no evidence. The task states what it touched; the profile decides what that owes. A task
tagged `none` owes nothing — see `.ai/profiles/README.md`.

**It checks five signals mechanically. The Definition of Done in `.ai/contract/lifecycle.md` §6 has
eleven conditions.** The other six — evidence observed, diff reviewed, docs updated,
compatibility considered, and the rest — cannot be checked by a script. They are yours, and they
belong in the final report with their evidence.

A green exit from that script is not permission to claim the task is done.

## Blocked Completion

If completion is blocked, keep the task active and record the blocker, impact, evidence, owner, and exact next action.

## Output

A verified completed task or an honestly documented active blocked task.
