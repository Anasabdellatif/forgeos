# Operating Contract — Task Lifecycle, Planning, and Definition of Done

Load when starting, planning, or closing a task. Referenced by `.ai/contract/core.md` §5, §6.

## 1. States

`inbox → active → completed`

- `inbox/`: captured but not ready to execute. Objective or acceptance criteria still incomplete.
- `active/`: ready or in progress. Exactly the work currently owned.
- `completed/`: closed and satisfying the Definition of Done. **Immutable archive** — never edit.
- Abandoned plans go to `.ai/plans/abandoned/` with a one-line reason.

Blocked work does **not** get its own state. It stays in `active/` with the `Blocked` section
filled: reason, impact, owner, and the exact next action.

## 2. Task Execution Sequence

1. Confirm the objective, the user or business value, and the acceptance criteria.
2. Create or move the task into `.ai/tasks/active/` using `.ai/tasks/templates/`.
3. Load only the context the task proves it needs.
4. Create a plan in `.ai/plans/active/` if the planning triggers apply.
5. Confirm current behavior and the source of truth before editing.
6. Implement in small, cohesive, independently reviewable steps.
7. Validate each meaningful step with the narrowest relevant check.
8. Review the complete final diff.
9. Update affected documentation and durable memory.
10. Produce the final report.
11. Move the task and its plan to `completed/` only when the Definition of Done is satisfied.

## 3. Planning Triggers

Create a plan when the work:

- Changes architecture, public or internal APIs, data models, authentication, authorization,
  billing, deployment, or infrastructure.
- Affects multiple modules, packages, or services.
- Requires a migration, a rollback strategy, or a coordinated release.
- Has unclear dependencies, significant risk, or more than one valid implementation path.
- Is expected to span multiple sessions or multiple agents.

## 4. Plan Contents

A plan is incomplete without all of the following:

- Objective and explicit scope boundary.
- Assumptions and unresolved questions.
- Affected components, contracts, and consumers.
- Ordered implementation steps, each independently verifiable.
- Validation strategy per step.
- Security, migration, rollback, and documentation impact.
- Completion criteria that map one-to-one onto the task's acceptance criteria.

Do not plan a trivial, isolated, low-risk change unless the user requests one.

## 5. Architecture and Data Changes

Before changing architecture, schemas, contracts, or persistent data:

1. Identify the current source of truth.
2. Assess backward compatibility for users, clients, APIs, data, and integrations.
3. Enumerate all consumers and integrations.
4. Define forward migration and rollback steps.
5. Consider partial deployment, mixed-version operation, and failure recovery.
6. Record a decision in `.ai/memory/decisions/` when the choice has long-term consequences.
7. Update the affected architecture, domain, and operations documentation.

Do not introduce a new dependency, service, framework, pattern, or abstraction without a concrete
present need and a documented justification.

## 6. Definition of Done

A task is complete only when every applicable condition holds:

- [ ] The requested outcome is implemented.
- [ ] Every acceptance criterion has been verified individually, not collectively.
- [ ] Relevant tests, builds, linters, type checks, and security checks were executed and passed.
- [ ] Every check that could not be run is documented with the reason and the residual risk.
- [ ] The final diff has been reviewed in full.
- [ ] No unrelated change, secret, temporary artifact, debug code, or accidental dependency remains.
- [ ] Backward compatibility, migration, rollback, and operational impact were considered.
- [ ] Affected product, architecture, domain, design, security, and operations docs were updated.
- [ ] Durable decisions, lessons, incidents, or handoff context were recorded where warranted —
      the persistence gate, `reporting.md` §0.
- [ ] No known critical defect and no unresolved blocker remains.
- [ ] The completion report is factual and supported by evidence.

If completion is prevented, keep the task in `active/`, fill the `Blocked` section, and say so
plainly. A blocked task honestly recorded is a success; a task closed without evidence is a defect.

## 7. Memory Policy

`.ai/memory/` holds only durable knowledge that will help future work.

| Directory | Contents |
| --- | --- |
| `decisions/` | Architectural or product decisions and their rationale. The ADR store. |
| `lessons/` | Reusable lessons from debugging, delivery, or maintenance. |
| `incidents/` | Production or significant operational incidents and their follow-up. |
| `handoffs/` | Continuation context for unfinished or transferred work. |
| `open-questions.md` | **The single register of assumptions and unanswered questions**, with owners. A task or plan may state one locally; anything that outlives the task is promoted here. |

Never store transient conversation, raw logs, speculation, secrets, or facts that are cheap to
rediscover. Every record must be concise, dated, scoped, and linked to its task, plan, code, or
documentation. Use the templates in `templates/`.

Filled reference examples: `examples/`.
