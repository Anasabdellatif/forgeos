---
profile: content-site
requiredRoles: [product-analyst, implementer, tester, reviewer, release-manager]
optionalRoles: [architect, security-reviewer, data-reviewer]
---

# Profile: Content Site

## When to use

Published content is the product: marketing, documentation, a blog, a portfolio, a brochure. Read
volume is high, write volume is low and comes from a small, trusted group.

Not this profile the moment it grows accounts, payments, or per-user data. A "site with a login and
a customer area" is an application — use `saas.md`.

## The defining risk

**Being wrong in public, at scale, in a search index.** The failures that matter are a broken page,
a mistranslation, an inaccessible component, or a slow first load — not a data breach.

## Why this profile is lighter

The only profile here with genuinely fewer required roles, and the reason is structural, not
budgetary: with no per-user data and few write paths, the isolation and integrity risks the other
profiles are built around do not exist. Adding roles that have nothing to examine teaches a team to
ignore roles.

| Role | Status | Why |
| --- | --- | --- |
| `product-analyst` | required | Content scope and audience are still product decisions |
| `implementer` · `tester` · `reviewer` | required | The core loop and independent review never lapse |
| `release-manager` | required | Anything hosted ships, and a bad deploy is public immediately |
| `architect` | **optional** | Becomes required if you add search, personalization, or a build pipeline others depend on |
| `security-reviewer` | **optional** | Becomes required the moment there is a login, a form that stores data, or user-supplied content |
| `data-reviewer` | **optional** | Becomes required if a CMS database appears with migrations |

Promote an optional role to required in `.ai/context/project.md` and say why. Silently skipping one
that has become relevant is how a content site turns into an application nobody reviewed.

## Required documents

- `docs/design/design-system.md` — **the primary document for this profile.** Typography, spacing,
  colour, contrast, direction, and language handling
- `docs/product/vision.md` — audience and voice
- `docs/operations/deployment.md` — how a page is published and how a bad publish is reverted

## Expected gates

| Gate | Must hold before release |
| --- | --- |
| Accessibility | Contrast, keyboard navigation, headings, alternative text — checked, not assumed |
| Language and direction | Every supported language rendered in both directions where applicable |
| Links resolve | Internal links and assets, on every published page |
| Performance budget | A stated first-load target, measured on a realistic connection |
| Content review | Someone other than the author read it before it went public |
| Rollback named | How to unpublish or revert a page, and how long it takes to propagate |

## Security · data · release concerns

- **Security:** the realistic risks are the build pipeline, the dependency chain, and the CMS login
  — not the pages. Treat a third-party script as code you did not review.
- **Data:** usually none. If forms collect anything, personal-data rules apply immediately and
  `security-reviewer` stops being optional.
- **Release:** caches and CDNs mean a mistake stays visible after it is fixed. Know the
  invalidation path before you need it.

## What this profile does not mean

- It does not require a static generator, a CMS, or any framework.
- It does not mean "low quality" or "no review". It means fewer *kinds* of risk, not a lower bar.
- It does not cover commerce. A catalogue with a checkout is not a content site.
- It is not an implementation order.

## Sources

Roles: `.ai/agents/` · Design system: `docs/design/design-system.md` ·
Publishing and rollback: `docs/operations/deployment.md`
