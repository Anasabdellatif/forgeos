# Domain Documentation

Domain documents define business language, bounded contexts, rules, ownership, and cross-domain workflows.

## Files

- `domain-map.md`: canonical map of domains, subdomains, entities, lifecycle states, rules, events, and dependencies.

## Usage

- Read this area before implementing business logic, permissions, workflow states, reporting, integrations, or data models.
- Keep domain vocabulary consistent across code, UI, APIs, tests, and documentation.
- Escalate conflicts between domain rules and product requirements before editing.

## Quality Standard

- Domain rules must be precise enough to test.
- Ownership boundaries must identify which module or service may change each concept.
- Cross-domain workflows must name the triggering event, validations, side effects, and failure behavior.
