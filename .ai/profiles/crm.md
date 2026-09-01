---
profile: crm
requiredRoles: [product-analyst, architect, implementer, tester, reviewer, security-reviewer, data-reviewer, release-manager]
optionalRoles: []
---

# Profile: Customer Relationship Management

## When to use

Customer and contact records drive the product: pipelines, activities, communications, and
integrations with mail, telephony, or marketing systems. Sales and support staff read and write
other people's personal data all day.

Not this profile if contacts are incidental. A product that merely stores a billing email is not
a CRM.

## The defining risk

**Personal data, held at volume, touched by many people, and exported constantly.** The largest
CRM incidents are not breaches of the perimeter — they are an over-broad export, a merge that
destroyed history, or a sync that overwrote a customer's record with stale data from a third party.

## Roles

| Role | Why it is required here |
| --- | --- |
| `product-analyst` | Pipeline stages, ownership, and visibility rules are product decisions with legal consequences |
| `architect` | Integration boundaries and which system wins a conflict must be decided once, explicitly |
| `implementer` | — |
| `tester` | Merge, deduplicate, import, export, and sync conflict — the paths that lose data quietly |
| `reviewer` | Independent check; must not be the author |
| `security-reviewer` | Personal data, record-level visibility, export limits, and retention |
| `data-reviewer` | Merges and imports rewrite history in bulk. Reversibility is the whole question |
| `release-manager` | A bad sync is discovered days later, after it has propagated outward |

## Required documents

- `docs/domains/domain-map.md` — contact, account, activity, ownership, and what a "merge" means
- `docs/architecture/overview.md` — every integration: contract, direction, conflict resolution,
  and which system is authoritative for each field
- `docs/product/requirements.md` — visibility and sharing rules, stated before they are coded
- `.ai/context/constraints.md` — retention obligations and data residency

## Expected gates

| Gate | Must hold before release |
| --- | --- |
| Record-level visibility tested negatively | The wrong owner, the wrong team, the deactivated user |
| Merge and delete are reversible | Or explicitly one-way, stated, with the user warned before it runs |
| Export is bounded and audited | Who exported what, when, how much |
| Sync conflicts have a defined winner | Per field, not "last write" by accident |
| Personal data is not in logs | Including error payloads and integration traces |
| Retention and deletion honored | Deleting a contact deletes it everywhere it was copied |

## Security · data · release concerns

- **Security:** the realistic threat is a legitimate user with too much reach. Bound exports, scope
  visibility to ownership, and make bulk actions auditable.
- **Data:** bulk operations are the danger — import, merge, mass update, sync. Each must record a
  before-state or refuse to run.
- **Release:** integrations fail outward and silently. Ship with a way to detect a sync that has
  stopped, not only one that has errored.

## What this profile does not mean

- It does not require a specific integration platform, mail provider, or database.
- It does not imply multi-tenancy. If customers share a deployment, add `saas.md` obligations.
- It does not encode any jurisdiction's privacy law. Legal obligations are recorded in
  `.ai/context/constraints.md` by the project, and belong to a future compliance overlay.
- It is not an implementation order.

## Sources

Roles: `.ai/agents/` · Security practice: `.ai/rules/security.md` ·
Domain: `docs/domains/domain-map.md` · Integrations: `docs/architecture/overview.md`
