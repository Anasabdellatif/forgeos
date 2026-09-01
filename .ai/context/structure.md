# Repository Structure

**Navigation map. Loaded so an agent does not have to scan the repository.**

This file answers *where*. It does not answer *why* or *what it means*:

- What a module **means** — its bounded context, vocabulary, and business rules:
  `docs/domains/domain-map.md`
- Why a boundary **exists** — components, responsibilities, allowed dependencies:
  `docs/architecture/overview.md`

Keep this file accurate and short. A wrong entry here is worse than an empty one: every agent
trusts it without re-verifying.

## Main Paths

- `AGENTS.md` and `CLAUDE.md`: entry points for Codex and Claude Code. Pointers, not rules — the operating contract is `.ai/contract/core.md`.
- `.ai/`: AI task, plan, rule, workflow, skill, memory, and context system.
- `docs/`: product, architecture, domain, design, and operations source-of-truth documentation.
- `scripts/`: dependency-free helper and validation scripts for this blueprint.
- `templates/`: reusable templates for durable records.
- TBD: application source path.
- TBD: test path.
- TBD: deployment or infrastructure path.

## Module Map

One line per module: **where it lives** and **what it owns**. The domain meaning of each name, and
the dependency rules between them, live in `docs/domains/domain-map.md` and
`docs/architecture/overview.md` respectively — do not restate them here.

| Path | Owns |
| --- | --- |
| TBD: path | TBD: capability, in one line |

## Entry Points

- Application: TBD.
- Tests: TBD.
- Scripts: `scripts/`
- Deployment: TBD.

## Generated and Ignored Content

TBD: list generated directories, caches, build outputs, vendored files, local environment files, and files that agents should not edit manually.

## Navigation Guidance

- Read this map before searching. That is why it exists.
- Search by symbol, route, command, or responsibility before scanning entire trees.
- Read indexes and nearby tests before opening large implementation files.
- Prefer `rg --files` and targeted `rg` searches.
- Stop expanding context when enough evidence exists to act safely.
