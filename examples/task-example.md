# Task: Correct rounding on partial refunds of multi-line invoices

> **This is a reference example, not project work.** It shows the expected depth of a completed
> task record. See `examples/README.md`.

## Metadata

- Status: `completed`
- Priority: `high`
- Owner: `implementer`
- Created: `2026-03-09`
- Updated: `2026-03-11`
- Related plan: `.ai/plans/completed/2026-03-09-money-minor-units.md`
- Related decision: `.ai/memory/decisions/2026-03-10-money-as-integer-minor-units.md`

## Objective

A partial refund distributed across multiple invoice lines must refund exactly the requested
amount. Today the per-line amounts are rounded independently, so the sum can differ from the
requested total by up to one cent per line.

## User or Business Value

Finance reconciliation fails when a refund total does not match the sum of its lines. Three
customers reported unbalanced statements in February; each required manual correction by an
accountant. The defect also blocks the automated reconciliation feature planned for Q3.

## Confirmed Context

- `src/billing/refund.ts:88` rounds each line independently with `Math.round(amount * 100) / 100`.
- Amounts are stored as `NUMERIC(12,2)` in `invoice_line.amount`, but carried as JavaScript
  `number` throughout the billing service — verified in `src/billing/types.ts:14`.
- 41 refunds in production have a line-sum mismatch. Query and result recorded in the plan, step 1.
- `RefundService.distribute()` has no test covering a total that is not evenly divisible.

## Assumptions

- No downstream consumer depends on the current (incorrect) per-line values.
  **Validated** in step 4: the two consumers, `reporting-etl` and `statement-pdf`, both re-derive
  from the total. Confirmed by reading `reporting-etl/src/refunds.sql:22` and
  `statement-pdf/src/render.ts:140`.

## Unresolved Questions

- Should the remainder cent go to the first line, the largest line, or the last line?
  **Answered by product owner on 2026-03-10:** the largest line, matching the existing behavior of
  the tax allocator in `src/billing/tax.ts:61`. Consistency inside the product beat any external
  convention.

## Scope

### In Scope

- `RefundService.distribute()` and its callers in `src/billing/`.
- Conversion of refund arithmetic to integer minor units.
- Backfill of the 41 mismatched historical refunds.

### Out of Scope

- Converting invoice or payment arithmetic to minor units. Tracked separately as
  `.ai/tasks/inbox/2026-03-11-minor-units-invoice-service.md`.
- Multi-currency rounding rules. No non-2-decimal currency is enabled.

## Acceptance Criteria

- [x] A refund of `$10.00` split across 3 lines refunds exactly `1000` minor units, with the
      remainder cent assigned to the largest line.
- [x] The sum of `refund_line.amount_minor` equals `refund.total_minor` for every refund created
      after the change — enforced by a database `CHECK` constraint and covered by a test.
- [x] A property test over 10,000 random (total, line-count, weight) triples finds no case where
      the line sum differs from the total.
- [x] The 41 historical mismatched refunds are corrected, and the correction is reversible from a
      recorded before-state.
- [x] No public API response shape changes. Existing integration tests pass unmodified.

## Affected Areas

- Code: `src/billing/refund.ts`, `src/billing/money.ts` (new), `src/billing/types.ts`
- Tests: `test/billing/refund.spec.ts`, `test/billing/money.property.spec.ts` (new)
- Documentation: `docs/domains/domain-map.md` (money representation), `docs/operations/runbook.md`
  (backfill procedure)
- Data or migrations: `migrations/0087_refund_minor_units.sql`, `migrations/0088_refund_check.sql`
- Operations or deployment: backfill runs as a one-off job; rollback documented in the plan

## Profile Compliance

- Profile: `saas`
- Scope tags: `data`

- Role evidence:
  - `data-reviewer`: examined migrations `0087`/`0088` and the backfill for lock time,
    reversibility, and mid-deploy safety. The `CHECK` constraint is deploy-order-sensitive —
    it must land after the backfill, and the plan orders it so. Measured lock: 41 s on a
    production-sized staging copy, inside the window. Detail: rollback section of
    `.ai/plans/completed/2026-03-09-money-minor-units.md`.

## Risks and Constraints

- The backfill mutates historical financial records. Requires a before-state snapshot and finance
  sign-off. **Obtained 2026-03-11 from the finance lead.**
- `NUMERIC` to `BIGINT` migration on a 4.2M-row table. Measured at 41 seconds on a production-sized
  staging copy — inside the 5-minute maintenance window.
- The `CHECK` constraint will reject any legacy write path that still uses decimal amounts. All
  three write paths were converted; verified by grepping for `refund_line.amount` across the
  monorepo.

## Validation Plan

- `npm test -- test/billing` — unit and property tests
- `npm run test:integration -- billing` — end-to-end refund flow
- `npm run typecheck` and `npm run lint -- src/billing`
- Migration applied to a production-sized staging copy, then rolled back, then reapplied
- Backfill dry-run on staging, with the diff reviewed against the finance lead's expectation

## Blocked

- Status: `no`
- Reason: `none`
- Impact: `none`
- Owner: `none`
- Next action: `none`

## Progress

- [2026-03-09] Reproduced with a 3-way split of `$10.00`: lines sum to `$9.99`. Confirmed the cause
  at `refund.ts:88`. Plan created.
- [2026-03-10] Decision recorded on integer minor units. Product owner answered the remainder
  question. `money.ts` and its property test landed.
- [2026-03-10] Session ended mid-migration. Handoff written to
  `.ai/memory/handoffs/2026-03-10-refund-minor-units.md`.
- [2026-03-11] Migration, backfill, and constraint completed. Finance sign-off obtained.

## Completion Evidence

- Acceptance criteria: `5 of 5 passed, each verified individually`
- Commands executed:
  `npm test -- test/billing` ·
  `npm run test:integration -- billing` ·
  `npm run typecheck` ·
  `npm run lint -- src/billing` ·
  `psql -f migrations/0087_refund_minor_units.sql` (staging)
- Results:
  `112 passed, 0 failed` ·
  `18 passed, 0 failed` ·
  `0 errors` ·
  `0 errors, 0 warnings` ·
  `migration applied in 41s; rollback verified; reapplied cleanly`
- Final diff reviewed: `yes — 9 files, no unrelated changes, no secrets, no debug code`
- Documentation updated: `docs/domains/domain-map.md`, `docs/operations/runbook.md`
- Remaining risks: `the invoice and payment services still use floating-point amounts; the same
  defect class remains reachable there. Tracked in .ai/tasks/inbox/2026-03-11-minor-units-invoice-service.md.
  Load testing of the backfill job beyond 4.2M rows was not performed.`
