# Project Intake And Forecast

Status: product direction for the next ForgeOS command layer.
Stage: slice 1 implemented as `forgeos intake` (read-only mode, forecast, and prompt family); slices 2 onward proposed.
Last updated: 2026-09-15.

ForgeOS must serve more than programmers. A founder, operator, product owner, designer, analyst, or
developer should be able to bring either a complete specification, a messy folder, a codebase, or
only an idea, and receive a safe engineering path that an AI agent can execute with bounded context.

This document defines the product behavior for the next layer above project ingestion: classify the
project, forecast its readiness and risks, and generate the next useful prompt from repository
state.

## Product Intent

The user should not need to know how to write a perfect prompt, how to divide an ERP into modules,
or which files an agent should read first. ForgeOS should turn project evidence into a compact
operating map:

- What kind of project is this?
- What proof already exists?
- What is missing before implementation is safe?
- What is the next useful session?
- What should the agent read, and what should it avoid reading?
- What will probably burn tokens if left unmanaged?

The output is guidance, not automatic authority. It may draft prompts, tasks, and forecasts, but it
must not authorize code, open governance windows, push, release, deploy, or invent missing product
truth.

## Users

ForgeOS should support at least these user roles:

| User | Need |
| --- | --- |
| Project owner | Understand what can be built next and which decisions are still needed. |
| Non-technical founder | Convert an idea or business file bundle into a professional project structure. |
| Product analyst | Extract requirements, decisions, risks, and module boundaries from source evidence. |
| Designer | See whether a project is ready for UI work or still missing product truth. |
| Developer | Start from the smallest sufficient context and avoid reading the whole repository. |
| AI coding agent | Receive bounded instructions, exact read targets, validation expectations, and prohibitions. |

## Project Modes

The first output is a mode. The mode is inferred from repository evidence and reported with
confidence and citations.

| Mode | Meaning | Typical next action |
| --- | --- | --- |
| `PROJECT_WITH_GOVERNING_DOCS` | The project has authoritative files such as signed specs, developer docs, architecture, data model, or requirements. | Build or refresh product intelligence maps, then plan from cited sections. |
| `PROJECT_DISCOVERY_REQUIRED` | The project has no adequate project files yet. | Run a discovery interview and create the missing context files before implementation. |
| `CODEBASE_RECONSTRUCTION_REQUIRED` | The project has code but weak or missing documentation. | Reconstruct product, architecture, domains, and risks from code plus owner confirmation. |
| `WEBSITE_PROJECT` | The project is primarily a website, landing page, docs site, or marketing/product surface. | Check design assets, content source, build/deploy path, and public surface risk. |
| `ENTERPRISE_SYSTEM` | The project is a large app, ERP, SaaS, portal, internal system, or multi-module platform. | Split modules, establish data/permission/operation boundaries, and require staged implementation. |

A project can carry a primary mode and tags. Example: a governed ERP project is both
`PROJECT_WITH_GOVERNING_DOCS` and `ENTERPRISE_SYSTEM`; a simple Astro site may be
`WEBSITE_PROJECT` with `PROJECT_DISCOVERY_REQUIRED` if it has no specs.

## Evidence Signals

Mode detection should stay cheap. It reads names, metadata, small indexes, and declared maps before
opening large files.

Signals that suggest governing documents:

- `docs/Client/`, `docs/Developer/`, `docs/data/`, `docs/architecture/`, `docs/product/`.
- Known source-authority files or an authority map.
- Files named like specification, cahier, requirements, architecture, data model, ADR, acceptance,
  verification, or traceability.
- Existing `.ai/product/` maps generated from sources.

Signals that suggest codebase reconstruction:

- Application directories exist, but product/architecture/domain docs are missing or mostly
  placeholders.
- Routes, modules, migrations, models, controllers, or UI components exist without a matching
  requirements map.

Signals that suggest a website:

- Static or web framework files such as `astro.config.*`, `next.config.*`, `vite.config.*`,
  `src/pages`, `public`, `dist`, content collections, or deployment workflows.

Signals that suggest an enterprise system:

- Multiple business modules, database migrations, role/permission models, queues, workers, audit
  trails, document generation, tenant/company settings, payment flows, or operational dashboards.

## Product Intelligence Maps

For projects with governing documents, ingestion should create compact maps under `.ai/product/`.
These maps are derived navigation, not the source of truth. They should cite source IDs and sections
instead of copying whole specs into always-loaded context.

Minimum maps:

- `authority-map.md`: source rank, ownership, digests if available, and conflict rule.
- `project-concept.md`: product identity, users, scope, non-goals, success conditions.
- `module-map.md`: modules, ownership, dependencies, and build order.
- `workflow-map.md`: core business flows, state transitions, and cross-module effects.
- `data-boundary-map.md`: data ownership, seeds vs runtime setup, immutability, ledgers.
- `decision-map.md`: open owner, legal, accounting, security, and infrastructure decisions.
- `execution-roadmap.md`: staged implementation plan with gates and validation expectations.

For projects without governing documents, ingestion should create discovery records instead:

- `idea-brief.md`
- `stakeholders.md`
- `questions.md`
- `assumptions.md`
- `scope-draft.md`
- `first-roadmap.md`

## Forecast Output

`forgeos forecast` should summarize readiness without pretending precision. It should produce a
scorecard, risk list, token-risk warning, and next action.

Suggested scorecard:

| Area | Score source |
| --- | --- |
| Product truth | Requirements, client docs, owner decisions, unresolved placeholders. |
| Architecture readiness | Module map, ownership boundaries, infrastructure choices, ADRs. |
| Data readiness | Data model, migrations, seed policy, validation evidence. |
| Governance readiness | Tasks, decisions, open questions, constraints, authorization state. |
| Implementation readiness | Codebase presence, tests, CI, application windows, blockers. |
| Token economy | Always-loaded context size, brief size, large-file risk, missing maps. |

The forecast should name:

- Highest risk.
- Next unblocker.
- Whether implementation is allowed.
- Whether the project needs owner decisions.
- Whether docs should be ingested before coding.
- Whether the next session should be read-only, documentation, migration, app code, website, review,
  release, or adoption.

## Next Prompt Generator

The prompt generator should turn the forecast into a paste-ready session package. It should support
non-programmers by naming the job in plain language and support engineers by listing exact files and
checks.

Prompt families:

| Situation | Prompt family |
| --- | --- |
| Governing docs exist but no maps | Extract project intelligence from source documents. |
| No docs exist | Run discovery and create the minimum project context. |
| Code exists without docs | Reconstruct requirements and architecture from code. |
| Website project | Review/build/deploy website safely, with design and hosting boundaries. |
| Enterprise system | Split into modules, phases, data model, permissions, and validation gates. |
| Blocked project | Record owner decision, resolve stale state, or prepare a safe alternative. |
| Ready implementation | Open the smallest scoped task with allowed paths and validation. |
| Release/adoption | Run a read-only push/release/adoption review before writing or publishing. |

Each generated prompt must include:

- Work location.
- Current HEAD and adoption version.
- Mode and confidence.
- Mission.
- Read-first list.
- Explicit prohibitions.
- Token-economy instructions.
- Validation plan.
- Commit/push/release policy.
- Final report format.

## Token Economy Rules

This layer exists to reduce session waste, not to add another large document agents always read.
The command output must stay compact and point to maps by path.

Rules:

- Do not load full specifications by default.
- Do not copy governing documents into always-loaded files.
- Prefer source IDs and section citations over long excerpts.
- Read a map before reading its source document.
- Ask the owner only after source recovery fails.
- Measure brief size and report token risk.
- Never claim whole-session token savings until measured on full sessions.

Target behavior:

- `forgeos brief` stays below its budget.
- Intake and forecast reports stay short enough to paste without crowding the next session.
- Large projects receive maps that reduce repeated document reading.
- The system reports token risks honestly instead of marketing a fixed multiplier.

## Command Shape

The first command layer should be read-only by default:

```text
forgeos intake
forgeos forecast
forgeos prompt --next
```

Expected behavior:

- `intake` detects mode, evidence, map coverage, and missing maps.
- `forecast` adds readiness, risks, token-risk, and next recommended session.
- `prompt --next` emits the smallest safe prompt for the next session.

Writing commands can come later:

```text
forgeos ingest --dry-run
forgeos ingest --apply
```

Even then, dry run is the default. Apply may create maps and discovery records, but it must not
modify source documents, application code, deployment config, or owner decisions unless the active
task explicitly authorizes that path.

## Professional Baseline

ForgeOS should make professional project construction accessible without hiding complexity. A
non-programmer should receive a clear path; a programmer should receive strict engineering
boundaries; an AI agent should receive enough context to act without wandering.

The system is successful when:

- A project with a signed specification is not treated like an empty idea.
- An empty idea is not treated like an approved build.
- A codebase without docs is reconstructed before major changes.
- A website is not governed like an ERP, and an ERP is not governed like a landing page.
- The next prompt is generated from evidence, not from memory.
- The owner sees the decisions they must make, not a fake implementation that guesses them.
- Token economy improves because the agent reads maps and sections, not whole archives every time.

## Delivery Slices

Recommended slices after v1.18.0:

1. **Forecast report, read-only.** Extend the existing ingestion check into an intake/forecast
   report available through the command layer.
2. **Next prompt generator.** Generate a prompt matched to the detected project mode and blocker.
3. **Project maps trial.** Run on at least three real adopters: a website, a governed enterprise
   project, and a codebase with weak docs.
4. **`forgeos ingest --dry-run`.** Show which maps would be created and from which evidence.
5. **`forgeos ingest --apply`.** Create maps only after the dry run is accepted.
6. **Gating policy.** Promote missing maps from informational to gating only after adopter evidence
   proves the rule is safe.

## Non-Goals

- No hosted project-management service.
- No telemetry.
- No automatic owner-decision generation.
- No automatic code authorization.
- No broad multi-agent orchestration.
- No framework-specific app templates in the core.
- No promise of a fixed token reduction multiplier.

## Open Product Questions

- Which command should own the first user-facing surface: `intake`, `forecast`, or an expanded
  `status`? Slice 1 answered `intake`: one read-only report carries the mode, the forecast, and the
  prompt family, so `forecast` stays unbuilt until it would say something `intake` does not.
- Should project-type tags live in `.ai/product/authority-map.md`, `blueprint.version`, or a new
  compact state file?
- What is the minimum map set that should become gating for projects with governing documents?
- How should a public adopters guide explain this to non-programmers without turning into a long
  manual?
