# Testing Rules

How tests are written and judged here. The obligation to run them and report observed results lives
in `.ai/contract/validation.md`.

## 1. Purpose

A test exists to provide **evidence** that required behavior works and that a specific regression
cannot return. A test that provides neither is cost without value — delete it or fix it.

## 2. Selecting the Level

| Level | Use for | Keep it |
| --- | --- | --- |
| Unit | Pure logic, branching, boundary values, error mapping | Fast, isolated, many |
| Integration | Real wiring across a boundary: DB, queue, HTTP client, filesystem | Focused, few, realistic |
| Contract | Agreements between services or between client and API | Versioned with the contract |
| End-to-end | The critical user journeys only | Very few, very stable |

Match the level to the failure mode you are preventing. An end-to-end test for a pure function is
waste; a unit test with a mocked database proves nothing about the query.

## 3. Quality

- Test observable behavior, not incidental implementation detail. A refactor that preserves
  behavior must not break the test.
- One reason to fail per test. Clear setup, one action, focused assertions.
- Deterministic: no wall-clock dependence, no real network, no random order coupling, no shared
  mutable fixture between tests.
- Name the test after the behavior and the condition:
  `rejects_withdrawal_when_balance_below_minimum`.
- Keep fixtures minimal and readable. A fixture nobody understands hides the bug.
- Assert on the meaningful value, not on a full serialized snapshot, unless the snapshot *is* the
  contract.

## 4. Required Coverage

Cover, at minimum:

- Every acceptance criterion of the active task.
- Security boundaries: authentication, authorization, tenant isolation, input validation.
- Error handling and the mapped user-facing failure.
- Boundary values: empty, one, many, maximum, negative, null, malformed.
- Critical business rules and money-, permission-, or data-integrity-affecting paths.

## 5. Regression Tests

For every bug fix, add a test that **fails before the fix and passes after it**. Observe both
directions when practical. A regression test never seen failing proves nothing.

## 6. Integrity

These are contract-level and non-negotiable:

- Never delete, weaken, skip, `@Ignore`, or bypass a test to obtain a passing result.
- Never loosen an assertion to accommodate a change without first establishing which side is wrong.
- Never change production behavior to satisfy an incorrect test without identifying the true source
  of truth and reporting the conflict.
- Never claim a test passed unless it was executed and its output observed.
- A flaky test is a defect. Quarantine it with an owner and a ticket, or fix it. Do not re-run
  until green.

## 7. Safety

- Never use real production services, credentials, or data.
- Never let a test create, mutate, or delete a real external resource without an isolated,
  disposable target.
- Use synthetic or sanitized data. Fixtures containing real personal data are a privacy incident.

## 8. Reporting

Record the exact commands, the observed results, the checks that were skipped, and the coverage
gaps that remain. Format: `.ai/contract/validation.md` §7.
