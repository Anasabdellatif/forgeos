# Git and Change Management Rules

Practice for staging, committing, and branching. Authorization classes for destructive Git
operations are in `.ai/contract/safety.md` §3.

## 1. Before Editing

- Run `git status` and `git branch --show-current`. Know what is already modified and where you are.
- Never start work on top of unrelated uncommitted changes without acknowledging them.
- Never work directly on the default branch. Branch first.

## 2. Branching

```
<type>/<short-kebab-summary>
```

`feat` · `fix` · `refactor` · `perf` · `test` · `docs` · `chore` · `hotfix`

Example: `fix/invoice-rounding-on-partial-refund`

One branch, one coherent objective. If the branch name needs "and", split it.

## 3. Staging

- Stage only files required by the active task. Review each with `git diff --staged`.
- Never stage: secrets, `.env` files, generated output, caches, lockfile churn unrelated to the
  change, editor configuration, or unrelated reformatting.
- Separate broad refactoring from behavior changes into distinct commits so each is reviewable.

## 4. Commit Messages

```
<type>(<scope>): <imperative summary, <=72 chars>

<why the change was needed, and what changed at a level a reviewer needs>

Refs: .ai/tasks/active/2026-08-02-invoice-rounding.md
```

- Describe intent and outcome, not a file listing.
- Never claim validation in a commit message unless it was performed and observed.
- Keep each commit logically cohesive and independently reviewable.
- Reference the task, plan, or decision record.

## 5. Destructive Operations

Never without explicit authorization in the current conversation:

`git reset --hard` · `git clean -fd` · `git checkout -- .` · `git push --force` ·
`git rebase` on shared history · `git stash drop` · branch or tag deletion · history rewriting

Prefer the reversible alternative: `git stash push` over discard, `git revert` over reset,
`git push --force-with-lease` over `--force` when a force push has been authorized.

## 6. Conflict Resolution

Do not resolve a meaningful conflict by guessing or by taking "ours" or "theirs" wholesale.

1. Identify the competing intent behind each side.
2. Inspect the history and the relevant documentation for each.
3. Reconstruct the correct combined behavior.
4. Re-run the tests covering both sides.
5. Request clarification when the intended outcome cannot be established.

## 7. Before Reporting Completion

- [ ] Full final diff reviewed — `git diff` and `git diff --staged`.
- [ ] `git status` clean of unintended files.
- [ ] No secret, temporary file, or debug code staged.
- [ ] Commit messages accurate and non-overclaiming.
- [ ] The branch contains only work belonging to this task.
