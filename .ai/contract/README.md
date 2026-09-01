# Operating Contract

The single source of truth for how AI agents work in this repository. `CLAUDE.md` and `AGENTS.md`
are thin pointers into this directory; they contain no rules of their own.

## Files

| File | Load when | Size discipline |
| --- | --- | --- |
| `core.md` | **Always.** First thing read in any session. | Keep under 150 lines. |
| `discovery.md` | The discovery gate fires — `.ai/context/` still has blocking `TBD`. | The six-phase interview, the gate, and its completion criteria. |
| `lifecycle.md` | Starting, planning, or closing a task. | Task states, planning triggers, Definition of Done, memory policy. |
| `validation.md` | Before claiming anything works. | Evidence rule, escalation ladder, diff review, criteria verification. |
| `safety.md` | Before any risky or destructive action. | Action classes, pre-action checklist, escalation triggers. |
| `reporting.md` | Closing, pausing, or transferring work. | Final report format, handoff standard. |

## Design Rules for This Directory

1. **One rule, one home.** A rule is written once. Everywhere else links to it.
2. **`core.md` is always-loaded and therefore expensive.** Anything that is not needed in every
   session belongs in a detail file, not in `core.md`.
3. **Detail files are pull, not push.** They are loaded when their trigger fires, never by default.
4. `.ai/rules/` holds *engineering* rules (how to write code, tests, docs, commits).
   `.ai/contract/` holds *operating* rules (how to work, decide, verify, and report).
5. Changing this directory changes agent behavior across every project that adopts the blueprint.
   Record the rationale in `.ai/memory/decisions/`.
