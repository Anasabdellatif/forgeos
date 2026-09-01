# Operating Contract — Validation and Evidence

Load before claiming that anything works. Referenced by `.ai/contract/core.md` §7.

## 1. The Evidence Rule

A check is "passed" only if it was **executed in this session** and its **output was observed**.

Forbidden phrasings unless backed by observed output:

- "Everything works."
- "Tests should pass."
- "This is a safe change."
- "The build succeeds."

Required phrasing when a check was not run:

> Not run: `<exact command>`. Reason: `<reason>`. Residual risk: `<what could still be broken>`.

## 2. Escalation Ladder

Run checks in this order and stop when the risk is covered:

1. The single unit test or function covering the changed behavior.
2. The test file or module.
3. The affected package or service suite.
4. Type check and lint on changed files.
5. Full build.
6. Integration or end-to-end suite.
7. Security, dependency, and license checks.

Escalate only when the change's blast radius justifies it. A one-line copy fix does not need the
full suite; a schema change does.

## 3. Behavior Coverage

For any behavior change, validate both:

- The intended path — the thing the task asked for.
- The important failure and edge paths — invalid input, missing permission, empty set, boundary
  value, concurrent access, and downstream failure.

For a bug fix, add or update a regression test that **fails before the fix and passes after it**.
Confirm both directions when practical; a regression test never observed failing proves nothing.

For configuration or infrastructure changes, validate syntax, validate against a non-production
target, and state the rollback path.

## 4. Diff Review

Before declaring completion, inspect the complete final diff and confirm:

- Every changed file is required by the active task.
- No secret, credential, token, or personal data was introduced.
- No debug statement, commented-out block, `TODO` without an owner, or temporary file remains.
- No generated artifact, lockfile churn, or unrelated reformatting was included.
- No dependency was added without justification.
- Public contracts changed only as the task requires, with compatibility assessed.

## 5. Acceptance Criteria Verification

Verify criteria **individually**, never as a group. For each criterion record one of:

| Status | Meaning |
| --- | --- |
| `passed` | Verified by observed evidence. Name the evidence. |
| `failed` | Verified as not met. Name the observed failure. |
| `blocked` | Cannot be verified. Name the blocker and the owner. |
| `n/a` | Not applicable. Name why. |

A criterion that was not checked is `blocked`, not `passed`.

## 6. Testing Standard

Full rules: `.ai/rules/testing.md`. The contract-level obligations:

- Never delete, weaken, skip, or bypass a test to obtain a passing result.
- Never change production behavior to satisfy an incorrect test without first identifying the true
  source of truth and reporting the conflict.
- Prefer deterministic tests with a clear setup, action, and assertion.
- Test observable behavior rather than incidental implementation detail.
- Cover security boundaries, permissions, validation, error handling, and critical business rules.
- Record known coverage gaps and their impact rather than hiding them.

## 7. Reporting Validation

In the final report, list the **exact commands** and their **observed results**:

```
npm test -- src/billing        → 14 passed, 0 failed
npm run typecheck              → 0 errors
npm run lint -- src/billing    → 0 errors, 2 warnings (pre-existing)
npm run build                  → not run (no build impact; residual risk: none identified)
```

Never summarize as "all checks passed" without the list.
