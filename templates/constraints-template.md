# Project Constraints

This file contains cross-cutting constraints that apply to every task. Keep detailed rationale in decision records and link to it rather than duplicating it here.

## Hard Constraints

- TBD: security, legal, compliance, or contractual constraint.
- TBD: technology, platform, hosting, or deployment constraint.
- TBD: compatibility requirement for users, clients, APIs, data, or integrations.

## Change Restrictions

- Do not introduce new dependencies without justification and approval when required.
- Do not change public contracts without assessing compatibility and migration impact.
- Do not perform destructive data, infrastructure, filesystem, or Git operations without explicit authorization.
- Do not expose secrets, credentials, private data, or production configuration.

## Quality Requirements

- Changes must satisfy explicit acceptance criteria.
- Relevant validation must be executed and reported with observed results.
- Important behavior changes require tests and documentation updates.
- Known limitations and skipped checks must be stated clearly.

## Operational Constraints

- TBD: availability target.
- TBD: performance or scale constraint.
- TBD: backup, recovery, or retention requirement.
- TBD: deployment window, approval gate, or release rule.

## Scope Boundaries

- TBD: out-of-scope area.

## Prompt Prohibitions

The `Do not:` list `forgeos next` / `forgeos prompt` writes into generated prompts. The entries below are generic; **add your own** — the repositories a slice must not touch, the environments it must not reach, the surfaces it must not start. Edit freely; read, never written. If this section is deleted, `forgeos next` falls back to a small built-in set. Two forms: `- when-not <regex>: text` and `- text`.

### Conditional

- when-not `release|launch|version`: create a tag or a release
- when-not `deploy|infrastructure|operations`: deploy, or run a migration against real data
- when-not `depend|package|upgrade`: add a new runtime dependency

### Always

- expand the scope beyond the capability named above
- weaken, skip, or delete a test to obtain a passing result
- disable or bypass a security control
- commit secrets, credentials, tokens, or personal data
- push
- spawn autonomous subagents or parallel review swarms
- unconstrained repo-wide file dumps

## Unresolved Constraints

- TBD: question requiring a durable decision.

## Maintenance Rule

Keep this file short. Store detailed rationale in decision records and link to it rather than duplicating it here.
