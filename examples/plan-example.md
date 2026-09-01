# Plan: Move refund arithmetic to integer minor units

> **This is a reference example, not project work.** It shows the expected depth of a plan.
> See `examples/README.md`.

## Metadata

- Status: `completed`
- Owner: `architect`
- Created: `2026-03-09`
- Updated: `2026-03-11`
- Related task: `.ai/tasks/completed/2026-03-09-refund-rounding.md`
- Related decision: `.ai/memory/decisions/2026-03-10-money-as-integer-minor-units.md`
- Profile compliance: declared on the related task — scope tag `data`, `data-reviewer` evidence
  recorded there. `finish-task` reads the task's declaration, not the plan's.

## Objective

Eliminate the class of rounding defects in refunds by representing refund amounts as integer minor
units end to end — in the database, in the domain model, and in the distribution algorithm — and
enforcing the line-sum invariant in the schema rather than in application code.

## Scope

### In Scope

- `src/billing/refund.ts`, its callers, and a new `src/billing/money.ts`.
- Schema change on `refund` and `refund_line`.
- A database `CHECK` constraint enforcing the line-sum invariant.
- Backfill of the 41 historically mismatched refunds.

### Out of Scope

- Invoice and payment arithmetic. Same defect class, larger blast radius, separate task.
- Multi-currency rounding. No currency with other than 2 decimal places is enabled; verified in
  `config/currencies.json`.
- The API response shape. External contracts stay decimal strings.

## Confirmed Context

- Cause: `refund.ts:88` rounds each line independently, so N lines can drift up to N/2 cents from
  the requested total.
- Blast radius measured: 41 of 128,403 refunds have a line-sum mismatch.

  ```sql
  SELECT COUNT(*) FROM refund r
  WHERE r.total <> (SELECT SUM(l.amount) FROM refund_line l WHERE l.refund_id = r.id);
  -- 41
  ```

- `refund_line.amount` is `NUMERIC(12,2)`; 4.2M rows.
- Only two consumers read `refund_line.amount`: `reporting-etl` and `statement-pdf`. Both re-derive
  from the total. Verified at `reporting-etl/src/refunds.sql:22` and `statement-pdf/src/render.ts:140`.

## Assumptions

- The maintenance window is 5 minutes. **Validated:** measured migration time on a production-sized
  staging copy is 41 seconds.
- No third-party integration reads `refund_line` directly. **Validated:** no external grant on the
  table; checked `information_schema.role_table_grants`.

## Unresolved Questions

- Where does the remainder cent go? **Answered 2026-03-10 by the product owner:** the largest line,
  matching `src/billing/tax.ts:61`.

## Affected Components

- `src/billing/refund.ts` — distribution algorithm
- `src/billing/money.ts` — new; minor-unit type and allocation function
- `src/billing/types.ts` — `Refund` and `RefundLine` shapes
- `migrations/0087_refund_minor_units.sql`, `migrations/0088_refund_check.sql`
- `docs/domains/domain-map.md` — money representation
- `docs/operations/runbook.md` — backfill and rollback procedure

## Implementation Steps

Each step is independently verifiable and independently revertible.

1. **Measure the blast radius.** Run the mismatch query on a production replica and record the
   exact count and the affected refund IDs into the plan. *Verify:* the count is stable across two
   runs ten minutes apart.
2. **Add `money.ts`** with a `MinorUnits` branded type and a `allocate(total, weights)` function
   that provably sums to the total. *Verify:* a property test over 10,000 random triples finds no
   mismatch; the test fails if `allocate` is replaced with independent rounding.
3. **Add the columns** `total_minor BIGINT` and `amount_minor BIGINT`, nullable, alongside the
   existing decimal columns. *Verify:* migration applies and rolls back on staging; no application
   change is required yet.
4. **Backfill the new columns** from the existing decimal values, and confirm the two consumers are
   unaffected. *Verify:* `SELECT COUNT(*) WHERE amount_minor IS NULL` returns 0; both consumers'
   integration suites pass.
5. **Switch the write path** to compute in minor units and write both columns. *Verify:* a new
   refund written through the API has consistent decimal and minor values; existing integration
   tests pass unmodified.
6. **Correct the 41 historical refunds**, recording the before-state to `refund_backfill_audit`.
   *Verify:* the mismatch query returns 0; the audit table has exactly 41 rows; a spot-check of 3
   refunds matches the finance lead's expected values.
7. **Add the `CHECK` constraint** enforcing `total_minor = SUM(amount_minor)` via a trigger.
   *Verify:* an attempted inconsistent insert is rejected; the existing suite still passes.
8. **Drop the decimal columns** in a follow-up release, not this one. *Verify:* n/a — deliberately
   deferred one release so a rollback remains possible without data loss.

## Validation Strategy

- `npm test -- test/billing` after steps 2, 5, 7
- `npm run test:integration -- billing` after steps 4, 5, 6
- `npm run typecheck` and `npm run lint -- src/billing` before completion
- Migration applied → rolled back → reapplied on a production-sized staging copy
- Backfill dry-run reviewed with the finance lead before the real run

## Security and Privacy Impact

- No change to authorization or data exposure. The refund API surface is unchanged.
- `refund_backfill_audit` contains financial amounts and is subject to the same retention and
  access policy as `refund`. Grants copied explicitly, not inherited.

## Compatibility and Migration

- The API contract is unchanged: amounts remain decimal strings on the wire.
- Decimal and minor columns coexist for one release, so a rollback to the previous application
  version keeps working without data loss.
- Steps 3 through 5 are safe under mixed-version operation: the old code ignores the new columns.

## Rollback Strategy

| Step | Rollback |
| --- | --- |
| 2 | Revert the commit. No data touched. |
| 3, 4 | `ALTER TABLE ... DROP COLUMN`. Decimal columns are still authoritative. |
| 5 | Deploy the previous application version. Decimal columns remain correct. |
| 6 | Restore from `refund_backfill_audit`; the reversal script is `scripts/ops/revert-refund-backfill.sql`. |
| 7 | Drop the trigger. |

Point of no return: **step 8**, deliberately deferred to the next release.

## Operational Impact

- Migration runs inside the standard 5-minute window; measured at 41 seconds.
- The backfill is a one-off job, not a recurring one. Runbook entry added.
- Add a monitor on the mismatch query; alert if it ever returns non-zero. This is the regression
  detector for the whole defect class.

## Documentation Impact

- `docs/domains/domain-map.md` — money is represented as integer minor units inside billing
- `docs/operations/runbook.md` — backfill procedure and its reversal
- `.ai/memory/decisions/2026-03-10-money-as-integer-minor-units.md`

## Risks

- Risk: `the CHECK trigger rejects a legacy write path that was missed`
  - Likelihood: `medium`
  - Impact: `high` — refunds would fail in production
  - Mitigation: `grep every write to refund_line across the monorepo before step 7; run step 7 on
    staging for 48 hours first`
- Risk: `the backfill corrects a refund that finance already manually reconciled, double-correcting it`
  - Likelihood: `low`
  - Impact: `high`
  - Mitigation: `dry-run reviewed line by line with the finance lead before the real run; the audit
    table makes it reversible`
- Risk: `migration exceeds the maintenance window on a larger production table than staging`
  - Likelihood: `low`
  - Impact: `medium`
  - Mitigation: `staging copy is production-sized; adding nullable columns is not a table rewrite
    in PostgreSQL 11+`

## Completion Criteria

- [x] The mismatch query returns 0 and a monitor alerts if it ever does not.
- [x] The property test fails when `allocate` is replaced with independent rounding.
- [x] The 41 historical refunds are corrected and the correction is reversible.
- [x] Migration verified apply → rollback → reapply on a production-sized copy.
- [x] Documentation and the decision record are updated.

## Progress

- [2026-03-09] Steps 1–2 complete. Property test catches the original defect when the old algorithm
  is substituted — the test is proven to have teeth.
- [2026-03-10] Steps 3–5 complete on staging. Decision recorded. Session ended; handoff written.
- [2026-03-11] Steps 6–7 complete. Finance sign-off obtained. Step 8 deferred to release 2026.4 by
  design.

## Outcome

Completed. The defect class is now structurally prevented rather than fixed case by case: the
invariant lives in the database, and the property test fails if the algorithm regresses. Step 8
(dropping the decimal columns) is scheduled for release 2026.4 and tracked in
`.ai/tasks/inbox/2026-03-11-drop-refund-decimal-columns.md`.
