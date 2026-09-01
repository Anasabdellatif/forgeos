# Start Task Workflow

## Objective

Convert a request into a clear, bounded, and executable active task.

## Steps

1. Read `.ai/contract/core.md`, `.ai/context/project.md`, and `.ai/context/constraints.md`.
2. Identify the requested outcome, user value, and explicit constraints.
3. Separate confirmed facts from assumptions and unresolved questions.
4. Determine whether the work is a task, bug, investigation, documentation change, or architectural decision.
5. Create or refine the task using the appropriate template.
6. Define scope, non-scope, acceptance criteria, risks, dependencies, and validation requirements.
7. Place the task in `.ai/tasks/active/` only when it is ready to execute.
8. Create a plan in `.ai/plans/active/` if the work is complex, risky, cross-cutting, or multi-session.

## Acceptance Criteria Must Be Observable

A criterion you cannot fail is not a criterion. Write each one so that a second person could run it
and disagree with you.

| Bad | Good |
| --- | --- |
| "authentication works properly" | "a request with an expired token receives 401 and no session is created — covered by a test" |
| "the import is fast" | "a 10,000-row import completes in under 30 seconds on the staging dataset" |
| "errors are handled" | "a failed payment webhook is retried three times, then written to the dead-letter queue" |

## Stop Conditions

Stop and request clarification when the objective, source of truth, destructive impact, authorization, or acceptance criteria cannot be established safely.

## Output

An active task that another agent can execute without rereading the entire conversation.
