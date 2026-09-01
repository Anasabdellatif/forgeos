# Decision: Represent money as integer minor units inside the billing domain

> **This is a reference example, not project work.** It shows the expected depth of a decision
> record. See `examples/README.md`.

## Metadata

- Status: `accepted`
- Date: `2026-03-10`
- Owners: `architect, product owner, finance lead`
- Related task: `.ai/tasks/completed/2026-03-09-refund-rounding.md`
- Supersedes: `none`
- Superseded by: `none`

## Context

Billing carries monetary amounts as JavaScript `number` and stores them as `NUMERIC(12,2)`. Every
conversion between the two is a rounding opportunity, and the code rounds in several places
independently. This produced a real, customer-visible defect: partial refunds split across multiple
invoice lines can sum to a different total than the amount actually refunded — 41 occurrences in
production.

Forces:

- **Correctness is not negotiable.** A billing system that loses a cent loses trust entirely, and
  the reconciliation feature planned for Q3 depends on exact sums.
- **JavaScript `number` is IEEE-754 binary floating point.** It cannot represent `0.1` exactly.
  Every fix that keeps decimals is a mitigation, not a solution.
- **The wire format cannot change.** Three external integrations consume decimal strings.
- **The team is small.** Whatever we choose has to be hard to use incorrectly by someone who has
  not read this document.

## Decision

Inside the billing domain, money is an **integer count of minor units** (cents for USD), carried in
a branded `MinorUnits` type and stored as `BIGINT`. Conversion to and from decimal happens only at
the system boundary — the API serializer and the PDF renderer — and nowhere else.

Distribution of a total across lines uses a single `allocate(total, weights)` function that is
guaranteed by construction to sum to the total, with the remainder assigned to the largest weight.

The invariant `total_minor = SUM(amount_minor)` is enforced by the database, not by application
code.

## Alternatives Considered

### Option 1: Keep decimals, round once at the end

- Advantages:
  - Smallest change. No migration, no type changes, no backfill.
  - Ships in a day.
- Disadvantages:
  - Fixes this instance, not the class. The next developer who rounds in a new place reintroduces it.
  - Still floating point. `0.1 + 0.2 !== 0.3` remains true everywhere in the domain.
  - Nothing detects a regression; the invariant lives only in a reviewer's memory.
- Reason not selected:
  - It leaves the defect class fully reachable. We would be choosing to fix this bug and accept the
    next one.

### Option 2: A decimal library (`decimal.js`, `big.js`)

- Advantages:
  - Exact decimal arithmetic without a schema change.
  - Well-tested, widely used.
- Disadvantages:
  - Correctness depends on every developer remembering to use it. A plain `+` still compiles and
    still silently produces a float.
  - Adds a runtime dependency to the hottest path in the service.
  - Serialization boundaries multiply: `Decimal` to JSON, to SQL, to the queue payload.
- Reason not selected:
  - It makes correct code *possible* rather than *default*. Integers make the incorrect version
    impossible: you cannot express a fractional cent in a `BIGINT`.

### Option 3: Integer minor units (selected)

- Advantages:
  - Exact by construction. There is no fractional cent to lose.
  - Native to the database, the language, and JSON. No dependency.
  - The invariant can be enforced in the schema, so it survives any application bug.
  - Standard practice in payment systems; every payment provider we integrate with already
    speaks minor units.
- Disadvantages:
  - Requires a migration and a backfill of 4.2M rows.
  - A branded type is needed to stop a raw `number` from being passed as `MinorUnits`.
  - Currencies with other than 2 decimal places need explicit handling if we ever enable one.

## Consequences

### Positive

- The rounding defect class is structurally prevented in refunds, not patched.
- Reconciliation against payment-provider records becomes a direct integer comparison.
- The database rejects an inconsistent refund even if application code is wrong.

### Negative or Trade-offs

- Invoice and payment arithmetic still use floats. **The system is now inconsistent** until those
  are converted — tracked in `.ai/tasks/inbox/2026-03-11-minor-units-invoice-service.md`. This
  inconsistency is the real cost of this decision and must not be forgotten.
- Every boundary needs an explicit conversion. A missing one is a 100× error, not a rounding error.
  Mitigated by the branded type and by boundary tests.
- Zero-decimal (JPY) and three-decimal (KWD) currencies will need a per-currency exponent. Deferred
  because no such currency is enabled; `config/currencies.json` verified.

## Compatibility and Migration

- The external API contract does not change. Amounts remain decimal strings on the wire.
- Decimal and minor columns coexist for one release so a rollback loses no data.
- Migration path and rollback are in `.ai/plans/completed/2026-03-09-money-minor-units.md`.

## Rollback

Reversible until the decimal columns are dropped in release 2026.4. Until then: deploy the previous
application version; the decimal columns remain authoritative and correct.

After the columns are dropped, reversal means a new migration and a backfill in the other
direction — possible, but no longer cheap.

## Validation

**How we would know this decision was wrong:**

- The mismatch monitor fires after the change — meaning the invariant is not actually enforced.
- A 100× or 0.01× amount error appears in production — meaning a boundary conversion was missed,
  and the branded type is not doing its job.
- The team routinely fights the branded type and adds casts to get around it — meaning the
  ergonomics are wrong and Option 2 was the better trade.

Evidence collected so far: the mismatch query returns 0; the property test fails when the old
algorithm is substituted; no boundary error has appeared in 3 weeks of production traffic.

## Follow-up

- `.ai/tasks/inbox/2026-03-11-minor-units-invoice-service.md` — extend to the invoice service
- `.ai/tasks/inbox/2026-03-11-drop-refund-decimal-columns.md` — release 2026.4
- `docs/domains/domain-map.md` — money representation documented
- `.ai/rules/coding.md` — no new rule added; the branded type enforces this better than prose would
