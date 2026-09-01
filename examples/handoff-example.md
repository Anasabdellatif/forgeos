# Handoff: Refund minor-units migration, paused before the historical backfill

> **This is a reference example, not project work.** It shows the expected depth of a handoff.
> See `examples/README.md`.

## Metadata

- Date: `2026-03-10`
- From: `implementer (session 2)`
- To: `next session`
- Active task: `.ai/tasks/active/2026-03-09-refund-rounding.md`
- Active plan: `.ai/plans/active/2026-03-09-money-minor-units.md`

## Current Objective

Complete the migration of refund amounts to integer minor units. Steps 1–5 of the plan are done and
verified on staging. The remaining work is the historical backfill (step 6) and the invariant
trigger (step 7).

## Confirmed State

- `src/billing/money.ts` exists, is used by `refund.ts`, and its property test passes.
- Columns `refund.total_minor` and `refund_line.amount_minor` exist on **staging only**. Not yet
  applied to production.
- The write path computes in minor units and writes both the decimal and the minor columns.
- 41 historical refunds still have a line-sum mismatch. They are **untouched** — the backfill has
  not run anywhere, including staging.
- The finance lead has **not** yet signed off on the backfill. This is the reason work paused.

## Work Completed

- Reproduced the defect with a 3-way split of `$10.00` — lines summed to `$9.99`. Cause confirmed
  at `src/billing/refund.ts:88`.
- Added `allocate()` with a property test over 10,000 random triples. Verified the test has teeth:
  substituting the old independent-rounding algorithm makes it fail.
- Applied migration `0087` to staging, rolled it back, reapplied it. 41 seconds each time.
- Switched the write path to minor units. Existing integration tests pass unmodified.
- Recorded the decision at `.ai/memory/decisions/2026-03-10-money-as-integer-minor-units.md`.

## Files Changed

- `src/billing/money.ts`: new. `MinorUnits` branded type and the `allocate()` function.
- `src/billing/refund.ts`: distribution now delegates to `allocate()`; lines 84–101 rewritten.
- `src/billing/types.ts`: `Refund.totalMinor` and `RefundLine.amountMinor` added; decimal fields
  retained for one release.
- `migrations/0087_refund_minor_units.sql`: new. Adds nullable `BIGINT` columns.
- `test/billing/money.property.spec.ts`: new. The property test.
- `test/billing/refund.spec.ts`: added the 3-way-split regression case.

Not yet written: `migrations/0088_refund_check.sql`, `scripts/ops/revert-refund-backfill.sql`.

## Validation Performed

- Command: `npm test -- test/billing`
  - Result: `112 passed, 0 failed`
- Command: `npm run test:integration -- billing`
  - Result: `18 passed, 0 failed`
- Command: `npm run typecheck`
  - Result: `0 errors`
- Command: `psql $STAGING -f migrations/0087_refund_minor_units.sql`
  - Result: `applied in 41s; rollback verified; reapplied cleanly`
- **Not run:** production migration. Reason: waiting on finance sign-off for the backfill that
  follows it. Residual risk: production timing is unmeasured, though staging is a production-sized
  copy.

## Remaining Work

1. Obtain finance sign-off on the backfill dry-run output. **This blocks everything below.**
2. Run the backfill dry-run and review it line by line with the finance lead
   (plan step 6). Write the before-state to `refund_backfill_audit`.
3. Write `scripts/ops/revert-refund-backfill.sql` **before** running the real backfill, not after.
4. Run the real backfill; confirm the mismatch query returns 0.
5. Write and apply `migrations/0088_refund_check.sql` (the invariant trigger), after grepping every
   write to `refund_line` across the monorepo (plan risk 1).
6. Add the mismatch monitor and its alert.
7. Update `docs/operations/runbook.md` and `docs/domains/domain-map.md`.

## Blockers and Unresolved Decisions

- **Blocked on:** finance sign-off for mutating 41 historical financial records.
  - Owner: finance lead
  - Impact: steps 2–7 cannot start
  - Requested: 2026-03-10 16:20, no response yet
  - This is a genuine authorization gate, not a formality. Do not proceed without it.

## Risks and Warnings

- **Do not run the backfill without writing the reversal script first.** The audit table alone is
  not a rollback; it is only the data a rollback would need.
- The `CHECK` trigger in step 5 will reject any legacy write path that still uses decimal amounts.
  Grep for `refund_line.amount` across the whole monorepo before applying it — a missed write path
  means production refund failures.
- Step 8 of the plan (dropping the decimal columns) is **deliberately deferred** to release 2026.4.
  Do not fold it into this task; it is the point of no return for rollback.
- The invoice and payment services still use floating-point amounts. Out of scope here. Do not
  expand into them.

## Relevant References

- Task: `.ai/tasks/active/2026-03-09-refund-rounding.md`
- Plan: `.ai/plans/active/2026-03-09-money-minor-units.md` (steps 6–8 remain)
- Decision: `.ai/memory/decisions/2026-03-10-money-as-integer-minor-units.md`
- Cause: `src/billing/refund.ts:88` (before the fix)
- Allocation function and its property test: `src/billing/money.ts`,
  `test/billing/money.property.spec.ts`
- Follow-up task: `.ai/tasks/inbox/2026-03-11-minor-units-invoice-service.md`

## Exact Next Action

Check whether the finance lead has signed off on the backfill. If yes, run the dry-run from plan
step 6 and review its output with them before executing anything. If no, do not start step 2 —
instead write `scripts/ops/revert-refund-backfill.sql` (step 3), which is independent of sign-off
and is a prerequisite for the real backfill.
