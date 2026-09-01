# Review Workflow

## Objective

Evaluate whether a change is correct, safe, maintainable, and aligned with the active task.

## Review Order

1. Task objective and acceptance criteria.
2. Final diff and changed-file scope.
3. Correctness and important edge cases.
4. Security, privacy, permissions, and trust boundaries.
5. Backward compatibility, data migration, rollback, and operational impact.
6. Test quality and validation evidence.
7. Documentation and memory updates.
8. Unrelated changes, temporary files, secrets, or generated artifacts.

## Findings

Classify findings as:
- `Critical`: data loss, security breach, destructive behavior, or unusable core functionality.
- `High`: likely incorrect behavior, serious regression, or missing required control.
- `Medium`: maintainability, incomplete validation, edge-case, or documentation risk.
- `Low`: minor clarity, consistency, or non-blocking improvement.

## Independence

**The agent that wrote the change must not be its only approver.** Where the tool supports separate
contexts, delegate the review to a fresh one:

| Lens | Runs when |
| --- | --- |
| `reviewer` | Always — correctness, scope, regressions, evidence |
| `security-reviewer` | Auth, tenancy, input, secrets, execution, integrations, infrastructure |
| `data-reviewer` | Schema, migration, backfill, retention, hot-path query |

They are independent and can run in parallel. The specialized lenses run **alongside** `reviewer`,
never instead of it.

Self-review catches typos. It structurally cannot catch the assumption the author never questioned.

## Rules

- Support findings with exact files, behavior, or evidence.
- Do not approve based only on appearance.
- Do not invent failures or claim tests were run when they were not.
- Distinguish blocking findings from optional improvements.
- Treat "the tests pass" as a claim to verify, not a fact to accept. Ask which command was run and
  what its output said.
- Verify each acceptance criterion individually as `passed`, `failed`, `blocked`, or `n/a`, and
  name the evidence. A criterion nobody checked is `blocked`, never `passed`.
- Check the task's `Scope tags` against what the diff actually touched. A missing tag is a review
  that will never be demanded; an unearned tag is a review with nothing to examine. Both are
  findings.
- Where a scope tag demands a specialized role, write that role's evidence under `Role evidence:`
  in the task — what was examined, what was found, and where the detail lives. `finish-task`
  refuses to close without it, and since `1.14.1` refuses placeholder text in its place: do the
  review before closing, not after. A closed task is an immutable archive and cannot be reopened
  to record what the review found.

## Output

A factual review with findings, validation gaps, residual risks, and approval status.
