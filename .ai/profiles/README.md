# Project Profiles

A profile answers one question: **given what kind of system this is, which roles are mandatory,
which gates must pass, and which risks are not optional to think about?**

It is not a plan, not an architecture, and not a stack. It is the shortest honest answer to
*"what does a project like this always need?"*

## Selecting one

`.ai/context/project.md` carries a `Profile:` field. Discovery phase 1 sets it, because the answer
changes which questions the later phases must press on.

A project may declare `none`. That is a valid answer for something genuinely unusual, and an
honest one — but it means no profile is enforcing anything, and the agent should say so.

## The five

| Profile | Use when |
| --- | --- |
| `saas.md` | Multiple customers share one deployment, and their data must never meet |
| `erp.md` | The data model *is* the product: many modules, long-lived records, hard integrity |
| `crm.md` | Customer and contact data drives the product, with heavy integration and personal data |
| `api-platform.md` | The contract is the product; other people's software depends on it |
| `content-site.md` | Published content, marketing, documentation, brochure — low write volume |

## What a profile contains

Frontmatter declares the roles, so a guard can check them exactly rather than guess from prose:

```yaml
requiredRoles: [product-analyst, architect, implementer, tester, reviewer]
optionalRoles: [data-reviewer]
```

The body covers: when to use it · required and optional roles with *why* · required documents ·
expected gates · security, data, and release concerns · **what the profile does not mean**.

## Promoting an optional role — the general rule

An optional role becomes **required** the moment the project acquires the thing that role exists to
examine. This is one rule, not five; each profile only names the triggers that are likely for its
kind of system.

| Role | Becomes required when the project acquires |
| --- | --- |
| `security-reviewer` | A login, a form that stores data, user-supplied content or files, or an external integration |
| `data-reviewer` | A database with migrations, a backfill, retention rules, or a hot-path query |
| `architect` | A second module that depends on the first, a build pipeline others rely on, search, or personalisation |
| `product-analyst` | Requirements that outlive one conversation, or a second stakeholder |
| `release-manager` | Anything that ships to someone else |

Record the promotion in `.ai/context/project.md` on its own structured line:

```markdown
- Promoted roles: `security-reviewer`
```

Say why beside it. `finish-task` reads that field first. The older prose form -- a sentence
containing the word *promoted* and the role in backticks -- is still honoured, in either word
order, but only for names that are actually roles. Write the structured line.

Silently skipping a role that has become relevant is how a content site turns into an
application nobody reviewed.

## How compliance is enforced

A profile that only declares roles is a recommendation. Since v1.9.0 it is checkable, without
demanding a review of every task:

1. **The task declares what it touches** — `Scope tags:` in its `## Profile Compliance` section,
   from `security` `data` `release` `product` `architecture` `domain`, or `none`.
2. **The profile decides which of those demand a role** — its `requiredRoles`, plus anything the
   project promoted.
3. **`finish-task` refuses to close** a task whose declared scope demands a role that left no
   evidence.

A docs-only task tagged `none` owes nothing, and that is the point: a role summoned to review
something it has no stake in teaches people to sign off without looking. An unrecognised tag is a
failure, not a skip — a typo must never silently disable a security review.

Declaring `none` as the profile disables all of it. That is a legitimate answer for something
genuinely unusual, and it is visible in `project.md` where anyone can challenge it.

## Rules

1. **A profile links; it never restates.** Roles live in `.ai/agents/`, rules in `.ai/rules/`,
   procedures in `.ai/workflows/`, facts in `docs/`. A profile that explains *how* to review has
   become a second copy of the reviewer.
2. **No technology.** A stack appears only as a conditional — "if you use X, then Y also applies" —
   never as a requirement. This blueprint stays independent of language and framework.
3. **No implementation plan.** A profile says what must be true, never what to build first.
4. **Every role named must exist** in `.ai/agents/`. Enforced by `check-policy`.
5. **Every profile must reference `docs/`.** A profile that never points at a source of truth has
   started to become one. Enforced.

## Honest limitation

Four of the five profiles require the same eight roles. That is not an oversight and not padding:
a multi-tenant SaaS, an ERP, a CRM, and a public API are all serious business systems, and all four
need product analysis, architecture, independent review, security review, data review, and a
release gate. **They diverge in gates, emphasis, and risk — not in who is at the table.**

`content-site` is the only genuinely lighter profile, and it says so.

## Not here yet: domain overlays

An industry is not a profile. Tourism, healthcare, industrial, education, e-commerce — each adds
*domain* obligations on top of a structural profile: booking inventory and cancellation windows;
patient data and regulated retention; device telemetry; accreditation; payment and refund law.

A hospital SaaS is `saas.md` **plus** healthcare obligations. Collapsing the two would force a
choice between duplicating the SaaS profile per industry, or losing the industry rules. Overlays
are a later phase, deliberately.
