# Coding Rules

How source code is written here. Operating obligations (scope, evidence, escalation) live in
`.ai/contract/`.

## 1. Priorities, in order

1. **Correctness** — it does what the acceptance criteria say, including on the failure paths.
2. **Clarity** — the next reader understands it without explanation.
3. **Consistency** — it looks like the code around it.
4. **Reversibility** — it can be backed out without collateral damage.
5. **Performance** — measured, not assumed. Optimize when profiled, not when suspected.

Clever code that scores high on 5 and low on 2 is a defect.

## 2. Change Discipline

- Follow existing repository conventions before introducing a new pattern. If the convention is
  wrong, say so and propose changing it — do not fork it silently.
- Keep the change cohesive and limited to the active task. No opportunistic refactoring.
- Separate behavior changes from broad refactoring into distinct steps or commits.
- Remove dead code only when its lack of use is verified and removal is in scope.
- Preserve backward compatibility unless an approved change requires otherwise.

## 3. Design

- One responsibility per function, module, and class. If the name needs "and", split it.
- Preserve module boundaries. A dependency that crosses a boundary needs a reason.
- Do not create an abstraction for a hypothetical future need. Duplicate twice; abstract on the
  third occurrence, when the shape is known.
- Avoid hidden side effects and global mutable state. Make dependencies explicit at the boundary.
- Prefer pure functions for logic and push I/O to the edges.
- Make illegal states unrepresentable where the language allows it.

## 4. Naming

- Names reflect domain intent, not implementation mechanics. `pendingInvoices`, not `list2`.
- Use the vocabulary defined in `docs/domains/` — one concept, one word, everywhere.
- Booleans read as assertions: `isActive`, `hasAccess`, `canRetry`.
- Avoid abbreviations that are not already standard in the codebase.

## 5. Error Handling

- Handle expected failures explicitly; let unexpected failures surface.
- Never silently swallow an error. An empty `catch` is a defect.
- Fail fast at trust boundaries; validate type, format, length, range, and authorization.
- Error messages state what failed, what was expected, and what to do — without leaking internals
  or sensitive values.
- Preserve the original error as a cause when wrapping.

## 6. Concurrency and Resources

- Make shared-state access explicit and bounded.
- Every acquired resource has a defined release path, including on the error path.
- Set timeouts on every outbound call. An unbounded wait is an outage.
- Make retries bounded, backed off, and idempotent, or do not retry.

## 7. Dependencies

- Prefer platform capabilities and already-approved dependencies.
- Introduce a dependency only for a concrete present need. Assess: maintenance activity, security
  history, licensing, transitive weight, and operational impact.
- Verify the package exists and is the intended one before adding it — see `ai-safety.md` §5.
- Pin versions and commit the lockfile.
- Record a dependency that affects architecture or operations as a decision in
  `.ai/memory/decisions/`.

## 8. Observability

- Log at boundaries and at state transitions, not inside tight loops.
- Log structured fields, not interpolated prose.
- Never log secrets, credentials, tokens, or personal data.
- Include a correlation identifier where the system supports one.
- Every failure path a user can hit should be diagnosable from the logs alone.

## 9. Pre-Completion Checklist

- [ ] The change satisfies the task, with no unrelated edits.
- [ ] Failure paths and edge cases are handled.
- [ ] Names match the domain vocabulary.
- [ ] No secret, debug statement, or temporary artifact remains.
- [ ] Tests and documentation are updated where behavior or contracts changed.
- [ ] Rollback is practical, and the path is known.
