# Lesson: A test that has never failed proves nothing

> **This is a reference example, not project work.** It shows the expected depth of a lesson.
> See `examples/README.md`.

## Metadata

- Date: `2026-03-11`
- Scope: `project`
- Source: `.ai/tasks/completed/2026-03-09-refund-rounding.md`
- Owners: `implementer, tester`

## Situation

While fixing the refund rounding defect, we found that `test/billing/refund.spec.ts` already
contained a test named `distributes refund across lines`. It had passed on every build since it was
written in 2024. It did not catch the defect that caused 41 incorrect refunds in production.

The test used a total of `$9.00` split across 3 lines — a case that divides evenly. It exercised the
code path without exercising the failure mode. It was, in effect, an assertion that the function
runs.

## Observation

A test's value is not that it passes. It is that it **would fail** for the defect it claims to
cover. We verified this directly on the new property test: we temporarily substituted the old
independent-rounding algorithm and confirmed the test failed. Only then did we trust it.

The same check applied to the pre-existing test showed it passed with the buggy algorithm — which
is exactly why the bug reached production behind a green suite.

## Why It Matters

- A green suite that contains untested tests produces **false confidence**, which is worse than no
  confidence. It is the reason a reviewer approved the original code.
- This is not rare. Any test whose inputs avoid the boundary has the same property.
- For an AI agent the risk is sharper: "the tests pass" reads as strong evidence, and it is trivial
  to write a test that passes for the wrong reason.

## Reusable Guidance

**Do:**

- For a regression test, observe it **fail** against the unfixed code before you fix anything.
  Report both observations. This is now a rule in `.ai/rules/testing.md` §5.
- For a test covering an algorithm, verify it fails when the algorithm is replaced with a plausible
  wrong one. Ten seconds of work, and it converts a claim into evidence.
- Choose inputs at the boundary: totals that do not divide evenly, empty sets, maximums,
  off-by-one values. A test with convenient inputs tests convenience.
- When inheriting a test suite, treat "it passes" as unverified until you know what it fails for.

**Do not:**

- Do not treat a passing suite as proof that a behavior is covered. Grep for the behavior, then read
  the test that claims to cover it.
- Do not write a test after the fix and report it as a regression test. It never demonstrated the
  regression.
- Do not use evenly divisible numbers in a test about division.

## Evidence

- The defect: `src/billing/refund.ts:88` before the fix
- The test that missed it: `test/billing/refund.spec.ts:44` (2024 version)
- The test that catches it: `test/billing/money.property.spec.ts`
- Production impact: 41 refunds, 3 customer reports, 3 accountant-hours of manual correction
- Task: `.ai/tasks/completed/2026-03-09-refund-rounding.md`

## Applicability

- Applies when: writing or reviewing any test that claims to prevent a specific defect; inheriting
  an unfamiliar test suite; judging whether coverage is real.
- Does not apply when: the test is a smoke test whose stated purpose is only "this wires up and
  runs". Those are legitimate — as long as nobody mistakes them for behavioral coverage.

## Follow-up

- `.ai/rules/testing.md` §5 — the fail-then-pass rule is now explicit
- `.claude/skills/test-generation/SKILL.md` — the rule is restated where the agent will meet it
- `.ai/workflows/review.md` — the reviewer now asks "what would this test fail for?"
- No automation added: whether a test has teeth cannot be checked mechanically. Mutation testing
  was considered and rejected for now — the suite is too slow to mutate on every build.
