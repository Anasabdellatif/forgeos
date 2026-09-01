# Architecture Documentation

Architecture documents define system structure, boundaries, contracts, data flow, operational model, and durable technical decisions.

## Files

- `overview.md`: current architecture, components, trust boundaries, data architecture, integrations, deployment model, and risks.
- `decisions.md`: index of durable product and architecture decisions stored in `.ai/memory/decisions/`.

## Usage

- Read `overview.md` before changing module boundaries, data models, public APIs, integrations, deployment, or security assumptions.
- Create a decision record when a choice has long-term impact or meaningful trade-offs.
- Update this area when implementation changes the architecture source of truth.

## Quality Standard

- Architecture guidance must describe responsibilities and allowed dependencies.
- Decisions must include alternatives, consequences, compatibility, rollback, and validation impact.
- Do not introduce new services, dependencies, or patterns without a concrete need and recorded rationale when durable.
