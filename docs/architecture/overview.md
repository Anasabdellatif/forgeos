# Architecture Overview

**Source of truth for architecture.** Components, boundaries, data stores, integrations,
deployment, and observability are decided here. `.ai/context/stack.md` carries the operational
summary an agent needs before it knows which section to open, and links back; it never restates
this file.

## Purpose

Describe the current system architecture, boundaries, responsibilities, data flow, integrations, and operational model.

## System Context

Describe users, external systems, trust boundaries, and the primary responsibilities of the product.

## Architectural Style

- Style: `[modular monolith / microservices / event-driven / other]`
- Status: `[proposed / approved / implemented]`
- Rationale: `[decision record path or concise explanation]`

## Quality Attributes

- Security: [requirements and approach]
- Reliability: [requirements and approach]
- Performance: [requirements and approach]
- Scalability: [requirements and approach]
- Maintainability: [requirements and approach]
- Observability: [requirements and approach]

## Major Components

### [Component Name]

- Responsibility: [owned capability]
- Inputs: [requests, commands, events, or data]
- Outputs: [responses, events, or data]
- Dependencies: [allowed dependencies]
- Data ownership: [owned data or none]
- Public contracts: [APIs, events, or interfaces]
- Failure impact: [expected impact]

## Module and Dependency Boundaries

- [Module A] may depend on [Module B] because [reason].
- [Module A] must not depend on [Module C] because [reason].

## Critical Data Flows

### [Flow Name]

1. [Actor or component performs an action]
2. [Processing and validation]
3. [Persistence, integration, or response]

## Data Architecture

- Primary data stores: [stores]
- Ownership boundaries: [rules]
- Consistency model: [approach]
- Migration strategy: [approach]
- Retention and deletion: [requirements]
- Backup and recovery: [approach]

## Trust and Security Boundaries

- Boundary: [name]
  - Assets: [protected assets]
  - Actors: [trusted and untrusted actors]
  - Controls: [authentication, authorization, validation, encryption]
  - Risks: [important threats]

## External Integrations

### [Integration Name]

- Purpose: [purpose]
- Contract: [API, event, file, or protocol]
- Authentication: [method]
- Timeout and retry: [policy]
- Idempotency: [policy]
- Failure behavior: [fallback or degradation]
- Data classification: [classification]

## Deployment Model

- Deployable units: [applications or services]
- Environments: [development, staging, production]
- Networking: [boundaries and exposure]
- Configuration: [management approach]
- Scaling: [strategy]
- Availability: [strategy]

## Reliability and Observability

- Logging: [approach and sensitive-data rules]
- Metrics: [important indicators]
- Tracing: [approach]
- Alerting: [ownership and thresholds]
- Health checks: [approach]
- Recovery: [approach]

## Architectural Constraints

- [Security, legal, technical, compatibility, or operational constraint]

## Known Risks and Technical Debt

- Risk or debt: [description]
  - Impact: [impact]
  - Mitigation: [treatment]
  - Related task: [path or none]

## Related Decisions

- [Decision record path]

## Maintenance

Update this document when system boundaries, ownership, contracts, data flows, deployment, security assumptions, or operational architecture change.
