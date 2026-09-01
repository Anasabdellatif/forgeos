# Incidents Memory

An incident is an event where **something that should have held, did not** — and the fact has
durable value beyond the task that hit it.

## The four kinds

| Kind | The thing that failed | Examples |
| --- | --- | --- |
| **Production** | The running system | An outage, corrupted output, a failed deploy, a runaway job |
| **Security** | A boundary | Exposed credentials, an authorization bypass, an unreviewed dependency executing |
| **Data** | Integrity or reversibility | A migration that could not be rolled back, a backfill that wrote wrong values, lost records |
| **Process / control** | A rule or guard the project relies on | A gate that was bypassable, a check that passed while examining nothing, a required review that never happened |

A process incident is not a lesser kind. A control that silently fails to fire is exactly as
dangerous as a system that silently returns wrong data — and it is harder to notice, because
everything looks green.

## Is this an incident?

Record one only when **all three** hold:

1. **A control, guarantee, or expectation failed** — not merely that work was hard or a first
   attempt was wrong.
2. **It could recur.** The same conditions would produce the same failure for someone else.
3. **The record changes future behaviour** — a rule, a guard, a check, or a procedure should move
   because of it.

If only 3 holds, it is a lesson: `.ai/memory/lessons/`.
If only the immediate work was affected, it is a line in the task's `Progress`.

## Not an incident

- An **ordinary task mistake**: a wrong approach, a failing test, a typo, a misread requirement,
  something caught and fixed within the task. Normal work is not an incident, and treating it as
  one empties the word.
- A tool or environment quirk with no bearing on the project's controls.
- A disagreement about design. That is a decision — `.ai/memory/decisions/`.
- Anything unverified. Suspicion is not an incident until it is confirmed.

## Store here

- Verified impact and affected scope.
- Detection and response timeline.
- Sanitized technical evidence.
- Root cause and contributing factors when confirmed.
- Containment, recovery, and resolution evidence.
- Corrective actions and reusable lessons.
- Links to related tasks, changes, monitoring, and documentation.

For a process incident specifically: **which control failed, why it did not fire, and what now
makes it fire.** A process incident with no corrective control is an anecdote.

## Do not store

- Unverified blame or speculation.
- Secrets, credentials, personal data, or unsafe exploit details.
- Raw unbounded logs.
- Minor development errors with no durable operational value.

## Naming

Use a stable name such as `YYYY-MM-DD-short-incident-title.md`.

## Template

Use `templates/incident-template.md`.

## Maintenance

Keep status and corrective actions current until the incident is fully closed. Do not alter the
historical timeline to hide mistakes or uncertainty.
