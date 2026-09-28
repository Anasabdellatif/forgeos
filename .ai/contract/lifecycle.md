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

The supported closure sequence, in this order: the record is active → validation evidence is
**observed and written into the record** → the closure checks pass → the record's own `Status`
becomes `completed` and it moves to `completed/` in one step → the forward links are verified. Use
`scripts/ai/finish-task`; it performs the transition so that status and location cannot disagree.

What the tool checks mechanically and what remains yours: it reads the record and refuses on
unchecked criteria, pending or unobserved evidence, an active blocker, template placeholders,
missing role evidence, and an ambiguous or out-of-scope related plan. **It cannot prove that a
test you describe was ever run.** That claim is agent-supplied evidence, and the Definition of Done
above is what governs it.

Closure rules the tool enforces, so an archive cannot lie about itself:

- A task names its plan in **one** metadata line. `none` means no plan; a path must be backticked
  and must live under `.ai/plans/`. Anything else refuses instead of guessing — a line reading
  ``Related plan: `docs/roadmap.md` §M-0`` once archived a project's roadmap as a plan.
- A plan another active task still names is **not** archived; it stays active and the closure says so.
- Nothing is edited or moved when a check refuses, and a failed plan move puts the task back.
- Closing an already closed task is safe and changes nothing.

**What closure guarantees, and what it does not.** Both archives are written from staged copies
before either original is removed, so a refusal or a failed write leaves both records byte for
byte — never an active record marked `completed`, never a link to a plan that was not archived.
That is recoverable-failure safety, **not crash atomicity**: a process killed between two file
operations can leave a copy in `completed/` while the original is still in `active/`. That state is
visible and safe to resolve — re-running answers `already closed`, and the destination is never
overwritten. If an original cannot be removed after its archive was written, the closure says so
and names the file to delete.

**Containment.** The task must resolve inside `.ai/tasks/` and the plan inside `.ai/plans/` — the
*resolved* path, not the text, so `..` and links cannot reach out. A file outside those roots is
never archived, whatever a record claims.

**References.** Closure updates only the two records it is closing. A completed record elsewhere
that names the same plan keeps its own text: `completed/` is immutable, and this tool does not
rewrite archives. Those links can therefore point at a plan that has since moved, which is a
reader's problem to notice, not a file to silently edit.

**Who retires a plan.** A plan is archived only when no other *active* task names it and it carries
no unchecked items of its own. Otherwise it stays active and the closure says why. No other task
naming it is not proof its own criteria are done.

**Waivers.** Section 6 above allows one exception and no other: *a check that could not be run is
documented with the reason and the residual risk*. That exception is written in one line, in
`Commands executed`, `Results`, or `Final diff reviewed`:

```
waived: scope=<this field>; reason=<why it could not run>; risk=<what may go unnoticed>; ref=<a file in this repository>
```

All four parts are required. The scope must name the field the waiver sits on, so one waiver never
covers another field. The reference must resolve to an existing file here — a decision record, an
open question, a task — and nothing is fetched from anywhere. A bare marker, a reason that restates
pending work, a missing reference, and a mismatched scope are each refused by name.

**What that verification is worth.** The tool checks *structure and resolution*: the parts are
present, the scope matches, the file exists. It **cannot authenticate who allowed the exception and
cannot prove any command ran**. A waiver makes a claim reviewable; it does not make it true.
Unchecked criteria, an active blocker, and template placeholders are never waivable, and a waiver
never rescues them.

**Forwarding records.** Several tasks may share one plan. The plan is archived when the last active
task closes — by then, earlier completed records already name it at its old active path, and a
completed record is never rewritten. So the old path keeps a forwarding record: a file carrying
`Status: `moved`` and the archived location. Historical references keep resolving, the status
readers skip it so it is never counted as an active plan, and a task that names a forwarding record
archives nothing — the plan it points to is already closed.

*Compatibility:* a forwarding record is a file shape introduced in this version. A project running
an **older ForgeOS** will count it as an active plan, because the status readers there do not know
the `moved` marker yet. The record is still only a pointer — nothing reads it as work — so the
consequence is a plan count one too high until that project updates.

**Interrupted closure.** A record can exist in both `active/` and `completed/` if a closure was
interrupted. `finish-task` tells the two possible situations apart by content, not by filename:

| Situation | How it is recognised | What happens |
| --- | --- | --- |
| Interrupted closure | The archive is this record plus exactly what a closure changes | The active copy is removed and the closure finishes; `--check` reports it and changes nothing |
| Conflict | Anything else differs | Exit `2`, both copies untouched, both paths named — you decide which is right |
| Already closed | No active copy remains | Reported, nothing touched |

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
