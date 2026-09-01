# Product Requirements

## Purpose

Define authoritative product behavior, business requirements, non-functional expectations, and acceptance criteria.

## Requirement States

- `proposed`: discussed but not approved for implementation.
- `approved`: accepted source of truth for planning and implementation.
- `implemented`: delivered and validated.
- `deprecated`: intentionally replaced or removed.

## Requirement Format

Each requirement should include:

- Identifier.
- Title.
- Description.
- User or business value.
- Priority.
- Acceptance criteria.
- Dependencies.
- Risks or constraints.
- Status.

## Functional Requirements

### REQ-001: TBD Title

- Status: `[proposed / approved / implemented / deprecated]`
- Priority: `[critical / high / medium / low]`
- Description: TBD required behavior.
- Value: TBD why it matters.
- Dependencies: TBD requirement, system, or `none`.
- Constraints: TBD security, legal, operational, or technical constraint.

#### Acceptance Criteria

- [ ] TBD observable outcome.
- [ ] TBD observable outcome.

## Non-Functional Requirements

### Performance

- TBD: response time, throughput, scale, or resource target.

### Availability and Reliability

- TBD: availability, resilience, recovery, or durability target.

### Security and Privacy

- TBD: authentication, authorization, data protection, audit, tenancy, abuse resistance, or compliance requirement.

### Accessibility and Usability

- TBD: accessibility, language, device, or usability requirement.

### Compatibility

- TBD: browser, platform, API, data, or integration compatibility.

## Out of Scope

- TBD: explicit exclusion.

## Traceability

Link requirements to tasks, plans, decisions, tests, releases, and operational documentation.

## Change Control

- Do not silently change approved requirements.
- Record meaningful changes, impact, rationale, and authorization.
- When requirements and implementation disagree, identify the source of truth before editing.

## Agent Guidance

- Implement only approved requirements unless the active task explicitly authorizes discovery or proposal work.
- Treat acceptance criteria as observable behavior, not implementation preference.
- Escalate conflicts between requirements, architecture, security, and user requests before editing.
