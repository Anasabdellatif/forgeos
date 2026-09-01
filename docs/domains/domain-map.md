# Domain Map

**Source of truth for the domain.** Bounded contexts, vocabulary, business rules, and ownership are
decided here. `.ai/context/structure.md` points at this file for the meaning of a module; it never
restates it.

This document is the canonical map of business concepts and domain boundaries for the adopting project.

## Domain Overview

- Core domain: TBD.
- Supporting domains: TBD.
- Generic domains: TBD.

## Bounded Contexts

### TBD Context

- Responsibility: TBD.
- Primary users or actors: TBD.
- Owned entities: TBD.
- External dependencies: TBD.
- Public contracts: TBD.
- Data classification: TBD.

## Core Entities

| Entity | Owner | Description | Key identifiers | Lifecycle |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

## Business Rules

| Rule ID | Context | Rule | Enforcement point | Tests |
|---|---|---|---|---|
| RULE-TBD | TBD | TBD | TBD | TBD |

## Workflows

### TBD Workflow

1. TBD actor initiates the workflow.
2. TBD validation occurs.
3. TBD state change, side effect, or integration occurs.
4. TBD completion, failure, or compensation behavior applies.

## Domain Events

| Event | Producer | Consumers | Payload summary | Reliability requirement |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

## Cross-Domain Dependencies

- TBD context may depend on TBD context because TBD.
- TBD context must not depend on TBD context because TBD.

## Open Questions

- TBD: unresolved domain question.

## Maintenance

- Update this file when domain language, ownership, lifecycle states, business rules, or cross-domain workflows change.
- Link approved domain decisions to `.ai/memory/decisions/`.
