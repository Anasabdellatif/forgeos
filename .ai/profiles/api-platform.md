---
profile: api-platform
requiredRoles: [product-analyst, architect, implementer, tester, reviewer, security-reviewer, data-reviewer, release-manager]
optionalRoles: []
---

# Profile: API Platform

## When to use

**The contract is the product.** Software you do not control depends on it, and you cannot deploy a
fix to your consumers. Public or partner APIs, webhooks you emit, SDKs, and any interface with
versioning obligations.

Not this profile for an internal API consumed only by your own frontend within the same
deployment — that is an implementation detail, and `saas.md` or `erp.md` already covers it.

## The defining risk

**You cannot take a change back.** Once a consumer depends on a field, removing it breaks their
software at a time you do not choose. Every other concern here follows from that one.

## Roles

| Role | Why it is required here |
| --- | --- |
| `product-analyst` | An API's shape is its user interface. Endpoint and field decisions are product decisions |
| `architect` | Versioning strategy, deprecation policy, and error model are decided once and lived with |
| `implementer` | — |
| `tester` | Contract tests, not only unit tests. The suite must fail when the contract changes shape |
| `reviewer` | Independent check; must not be the author |
| `security-reviewer` | This is the public attack surface: authentication, authorization, rate limits, input validation |
| `data-reviewer` | Required when the platform owns storage. If it owns none it is a proxy — say so and mark the role optional in that project |
| `release-manager` | Consumers cannot roll back with you. A release is one-way from their perspective |

## Required documents

- `docs/architecture/overview.md` — versioning strategy, deprecation policy, error model,
  idempotency, rate limits, and every integration contract
- `docs/product/requirements.md` — what each endpoint guarantees, and what it does not
- `docs/operations/runbook.md` — how to detect a consumer breaking, and how to communicate a
  deprecation
- `.ai/context/constraints.md` — the compatibility window you are promising

## Expected gates

| Gate | Must hold before release |
| --- | --- |
| Breaking change detected mechanically | A removed field or narrowed type fails the build, not review |
| Contract tests run both directions | The implementation matches the published contract |
| Versioning honored | Additive within a version; anything else needs a new one |
| Deprecation has a stated window | And a way to see who is still calling the old path |
| Errors are stable and documented | An error shape is part of the contract |
| Idempotency defined | For every non-safe method a consumer may retry |
| Rate limits and payload bounds | On every public entry point |

## Security · data · release concerns

- **Security:** everything is untrusted input, arriving at volume, from clients you cannot patch.
  Authentication, object-level authorization, quotas, and abuse resistance are baseline, not
  hardening.
- **Data:** the response shape is a promise. Serializing an entity because it is convenient exposes
  fields you will be unable to remove later.
- **Release:** measure adoption before deprecating. A deprecation without usage data is a guess
  about who you are about to break.

## What this profile does not mean

- It does not require REST, GraphQL, gRPC, or any specific schema language. If you use OpenAPI or a
  schema registry, breaking-change detection becomes mechanical rather than manual — that is a
  conditional benefit, not a requirement.
- It does not imply public availability. A partner-only API has the same one-way property.
- It does not cover industry rules. Payments, health, and telecom each add obligations as overlays.
- It is not an implementation order.

## Sources

Roles: `.ai/agents/` · Security practice: `.ai/rules/security.md` ·
Contracts and versioning: `docs/architecture/overview.md` · Testing: `.ai/rules/testing.md`
