# Implementation Workflow

## Objective

Apply the smallest complete change that satisfies the active task.

## Steps

1. Read the active task and relevant plan.
2. Load only the required context, rules, skills, code, tests, and documentation.
3. Inspect repository status and preserve unrelated changes. Branch first when the branch rule
   below says to.
4. Confirm the current behavior and source of truth before editing.
5. Implement in small, cohesive, reviewable steps.
6. Validate each meaningful step with the narrowest relevant check.
7. Update tests and documentation when behavior, contracts, configuration, or operations change.
8. Review changed files for scope, security, compatibility, and accidental artifacts.
9. Update the task's `Progress` section with a dated factual line.
10. Record durable decisions or lessons only when they will help future work.

## The Branch Rule

**Branch off the default branch when either is true:**

- The repository has a remote — history is shared, so someone else may pull it.
- The change touches anything other than documentation, task records, plans, or memory — any
  source, configuration, schema, dependency, or infrastructure file.

**Otherwise commit on the default branch. That is not a deviation and must not be reported as one.**

Both conditions are checkable before starting: `git remote` and the list of paths about to change.

The rule protects two things: history other people depend on, and changes that can break something.
A documentation edit in a local repository with no remote threatens neither. Requiring a branch
there produced a deviation line in every report, on every task, carrying no information — and a
warning that always fires is a warning nobody reads.

When in doubt, branch. The cost is one command; the cost of the opposite mistake is rewritten
shared history.

## When to Hand Off to a Specialized Role

Implementation is not always the right next move. Delegate when:

| Signal | Role |
| --- | --- |
| The change touches structure, contracts, data models, or has more than one valid path | `architect` — **before** implementing, not after |
| Validation design is non-trivial, or a bug needs a regression test | `tester` |
| The change touches auth, data, input, secrets, execution, or infrastructure | `security-reviewer` — before completion |
| The change touches a schema, migration, backfill, retention, or a hot-path query | `data-reviewer` — before completion |
| The change is ready and needs an independent correctness check | `reviewer` — and it must not be you |
| The change is about to ship, deploy, or run a migration | `release-manager` — it decides go or no-go on evidence |

Role definitions: `.ai/agents/`.

## Rules

- Do not expand scope silently.
- Do not introduce new dependencies or abstractions without a concrete need.
- Do not claim success without observed validation evidence.
- Keep the task and plan status current when work becomes blocked or assumptions change.

## Output

A focused implementation ready for independent review and final validation.
