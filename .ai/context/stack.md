# Technology Stack

**Operational summary. Loaded when the task touches code, tests, or tooling.**

`docs/architecture/overview.md` owns the architecture: components, data stores, integrations,
deployment topology, observability strategy. This file holds the short answers an agent needs to
act — what the runtime is, and what to type — and links back for depth.

Record versions from a lockfile, a manifest, or `--version` output. Never from memory.

## Runtime

- Language and version: TBD: exact, from the manifest or lockfile.
- Runtime and version: TBD: exact.
- Package manager: TBD: and the lockfile it maintains.

## Commands an agent will actually run

The single highest-value section in this file. Fill it before the first task.

| Purpose | Command |
| --- | --- |
| Test (narrowest) | TBD: how to run one test file |
| Test (full) | TBD: |
| Lint | TBD: |
| Format | TBD: |
| Type check | TBD: or `none` |
| Build | TBD: |
| Run locally | TBD: |
| Migrations | TBD: or `none` |

## Data and services

- Datastores: TBD: name and version. Ownership and consistency: `docs/architecture/overview.md`
- Cache / queue: TBD: or `none`
- External services: TBD: names only. Contracts, auth, timeouts, failure behavior:
  `docs/architecture/overview.md`

## Delivery

- CI system and required checks: TBD:
- Deployment model: TBD: summary only. Depth: `docs/operations/deployment.md`
- Observability: TBD: one line. Depth: `docs/architecture/overview.md`

## Dependency Policy

- Prefer existing platform capabilities and approved dependencies.
- Introduce a dependency only for a concrete present need, with security, maintenance, licensing,
  size, and operational impact considered.
- Verify the package exists and is the intended one before adding it — `.ai/rules/ai-safety.md` §5.
- Record a dependency that affects architecture or operations as a decision in
  `.ai/memory/decisions/`.

## Rules for this file

- Keep it short enough to load often. Depth belongs in `docs/architecture/overview.md`.
- Never restate an architectural fact this file only summarizes.
- An unverifiable version is written `unverified:`, never guessed.
