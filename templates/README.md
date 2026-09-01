# Templates

Reusable templates for records that need consistent structure and evidence.

**Templates set the shape. `examples/` sets the depth.** Read the matching example before writing
your first record of a given type.

## Available Templates

| Template | Destination | Filled example |
| --- | --- | --- |
| `.ai/tasks/templates/task-template.md` | `.ai/tasks/inbox/` or `active/` | `examples/task-example.md` |
| `.ai/tasks/templates/bug-template.md` | `.ai/tasks/inbox/` or `active/` | — |
| `plan-template.md` | `.ai/plans/active/` | `examples/plan-example.md` |
| `decision-template.md` | `.ai/memory/decisions/` | `examples/decision-example.md` |
| `handoff-template.md` | `.ai/memory/handoffs/` | `examples/handoff-example.md` |
| `lesson-template.md` | `.ai/memory/lessons/` | `examples/lesson-example.md` |
| `incident-template.md` | `.ai/memory/incidents/` | — |
| `project-context-template.md` | `.ai/context/project.md`, **placed by sync** | — |
| `governance-template.json` | `.ai/context/governance.json`, **placed by sync** | — |

One template is never copied by hand: `project-context-template.md` is what `sync-blueprint`
seeds into a new project as `.ai/context/project.md`. This repository fills that path with the
blueprint's own identity, and an adopting project must start undefined instead of inheriting it.
The mapping lives in `scripts/lib/blueprint-manifest.json` under `distribution.seedTemplates`.

Task and bug templates live under `.ai/tasks/templates/` so `new-task` can find them; the rest live
here.

## Rules

- Copy into the destination before editing. Never edit a template in place to record real work.
- Replace every placeholder with a **verified fact**, an **explicit assumption**, or a **named
  unresolved question**. A placeholder left in a real record is a defect — `finish-task` blocks on
  the common ones.
- Date every record, and use the `YYYY-MM-DD-short-slug.md` naming convention.
- Link to the related task, plan, decision, test, code, and documentation. A record with no links
  is an orphan nobody will find.
- Keep it concise. These are working records, not narratives.
- Never store secrets, credentials, private data, or raw unbounded logs.

## Changing a template

A template change silently changes every future record. If a template gains or loses a section,
update the matching example in `examples/` in the **same change**, and check whether
`scripts/ai/new-task` or `finish-task` depends on the text you edited — both match on literal
strings from these files.
