---
profile: erp
requiredRoles: [product-analyst, architect, implementer, tester, reviewer, security-reviewer, data-reviewer, release-manager]
optionalRoles: []
---

# Profile: Enterprise Resource Planning

## When to use

The data model **is** the product. Many modules — inventory, procurement, accounting, payroll,
production — write to overlapping records, and a document posted in one module changes balances in
another. Records live for years and are audited.

Not this profile if the system has one domain and few write paths. That is an application, and
`saas.md` or `content-site.md` probably fits better.

## The defining risk

**A transaction that is correct in one module and wrong in another.** ERP failures are rarely a
crash; they are a stock figure that no longer matches the ledger, discovered a quarter later. The
cost is reconciliation, not downtime.

## Roles

| Role | Why it is required here |
| --- | --- |
| `product-analyst` | Business rules here are accounting and legal rules. Inventing one is not a bug, it is a misstatement |
| `architect` | Module boundaries and who may write which record is the decision the whole system inherits |
| `implementer` | — |
| `tester` | Business-rule coverage matters more than line coverage. Posting, reversal, period close, partial states |
| `reviewer` | Independent check; must not be the author |
| `security-reviewer` | Segregation of duties, approval chains, and audit-trail integrity |
| `data-reviewer` | **The central role in this profile.** Long-lived records, large tables, migrations that must preserve historical postings |
| `release-manager` | ERP downtime stops invoicing and shipping. Windows are narrow and rollback must be real |

## Required documents

- `docs/domains/domain-map.md` — **the most important document in an ERP.** Modules, their
  vocabulary, the invariants between them, and who owns which record
- `docs/architecture/overview.md` — module boundaries, transaction boundaries, consistency model
- `docs/operations/runbook.md` — period close, failed posting recovery, reconciliation procedure
- `docs/operations/deployment.md` — the maintenance window, and what happens to in-flight documents

## Expected gates

| Gate | Must hold before release |
| --- | --- |
| Invariants enforced by the database | Not only by application code. A rule held in code alone will be broken by a script |
| Reversal path exists | Every posting that can be made can be corrected, without editing history |
| Audit trail is append-only | And the application's database role cannot drop or alter it |
| Migration preserves historical records | Old postings must still reconcile after the schema changes |
| Concurrency tested | Two writers on the same document, retried webhooks, duplicate submissions |
| Rollback named | With the state of in-flight documents stated explicitly |

## Security · data · release concerns

- **Security:** the threat is usually internal. Segregation of duties, approval limits, and an
  audit trail nobody can quietly edit matter more than perimeter defence.
- **Data:** integrity over availability. A brief outage is recoverable; a silently wrong balance
  may not be. Prefer a constraint that rejects over a default that guesses.
- **Release:** in-flight documents are the hard part. Decide what happens to a half-posted
  transaction during a deploy *before* deploying.

## What this profile does not mean

- It does not require a specific accounting standard, module set, or database.
- It does not imply multi-tenancy. If customers share a deployment, add `saas.md` obligations too.
- It does not cover industry rules — manufacturing, retail, and public sector each add their own.
  Those are overlays.
- It is not an implementation order.

## Sources

Roles: `.ai/agents/` · Data review method: `.ai/agents/data-reviewer.md` ·
Domain: `docs/domains/domain-map.md` · Architecture: `docs/architecture/overview.md`
