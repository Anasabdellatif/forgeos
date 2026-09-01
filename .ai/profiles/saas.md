---
profile: saas
requiredRoles: [product-analyst, architect, implementer, tester, reviewer, security-reviewer, data-reviewer, release-manager]
optionalRoles: []
---

# Profile: Multi-Tenant SaaS

## When to use

Multiple customers share one deployment, and **their data must never meet**. Subscriptions, plans,
seats, per-tenant configuration, and a support path that can reach any tenant's records.

Not this profile if each customer gets a separate deployment — that is single-tenant hosting, and
the defining risk below does not apply.

## The defining risk

**Tenant isolation is not a feature; it is the product's licence to exist.** One query missing a
tenant predicate is a breach, not a bug. Every other concern in this profile is secondary to it.

## Roles

| Role | Why it is required here |
| --- | --- |
| `product-analyst` | Plans, limits, and seat rules are product decisions that get invented if nobody owns them |
| `architect` | Where the tenant boundary lives — row, schema, or database — is the decision everything else inherits |
| `implementer` | — |
| `tester` | Isolation must be **tested negatively**: the wrong tenant must fail, and that test must have been seen failing |
| `reviewer` | Independent check; must not be the author |
| `security-reviewer` | Tenant isolation, object-level authorization, and support-staff access are its core lens |
| `data-reviewer` | Every migration runs across all tenants at once. A backfill that assumes one tenant corrupts many |
| `release-manager` | A bad release reaches every customer simultaneously. There is no partial blast radius |

## Required documents

Beyond the blueprint baseline, these must be filled before the first tenant-facing release:

- `docs/architecture/overview.md` — where the tenant boundary sits, and how it is enforced
- `docs/domains/domain-map.md` — tenant, plan, seat, and their invariants
- `docs/operations/runbook.md` — how to investigate one tenant without reading another's data
- `.ai/context/constraints.md` — availability target, since one deployment serves everyone

## Expected gates

| Gate | Must hold before release |
| --- | --- |
| Negative isolation tests | Wrong tenant, wrong user, no token, expired token — each proven to fail |
| Object-level authorization | Checked on the record, not only on the route |
| Migration is tenant-safe | Runs across all tenants; backfill is idempotent and resumable |
| Support access is auditable | Who read what, when, for which tenant |
| Rollback named | Exact command, measured duration, what it does not restore |

## Security · data · release concerns

- **Security:** tenant identity comes from the session, never from a client-supplied parameter.
  Support and admin paths are the most common isolation leak — they are built to cross tenants by
  design, so they need the strictest checks.
- **Data:** shared tables mean shared locks. A migration's blast radius is the whole customer base.
- **Release:** no partial rollout means no partial failure. Feature flags and per-tenant enablement
  are the usual mitigation — decide before shipping, not during an incident.

## What this profile does not mean

- It does not require a specific database, tenancy strategy, or framework. Row-level, schema-level,
  and database-level tenancy are all valid; `architect` decides which, and records why.
- It does not imply subscription billing. A SaaS may be free or invoiced offline.
- It does not cover industry obligations. A healthcare SaaS is this profile **plus** a healthcare
  overlay — see `.ai/profiles/README.md`.
- It is not an implementation order. Nothing here says what to build first.

## Sources

Roles: `.ai/agents/` · Review order and severity: `.ai/workflows/review.md` ·
Security practice: `.ai/rules/security.md` · Architecture: `docs/architecture/overview.md`
