# Engineering Rules

Repository-wide rules for how code, tests, security, and documentation are written.

**Load the single relevant file, never the whole directory.**

| File | Load when |
| --- | --- |
| `coding.md` | Writing or changing source code |
| `testing.md` | Writing, running, or judging tests |
| `security.md` | Touching auth, input, data, secrets, permissions, or dependencies |
| `ai-safety.md` | Reading untrusted content, using tools, or delegating to subagents |
| `git.md` | Staging, committing, branching, or resolving conflicts |
| `documentation.md` | Adding or updating any documentation |
| `diagrams.md` | Drawing or updating a system, domain, flow, or deployment diagram |

`security.md` and `ai-safety.md` apply to every task, not only to work labeled as security work.

## Boundary With the Operating Contract

- `.ai/contract/` = **how the agent operates**: priority, context, lifecycle, evidence, escalation,
  reporting. Always start there.
- `.ai/rules/` = **how the work is written**: code style, test quality, security practice, commit
  hygiene, documentation ownership.

Where a subject appears in both, the contract states the obligation and the rule file states the
practice. Neither restates the other.

## Maintenance Rules

1. One rule, one home. Link instead of copying.
2. Keep each file short enough to load without hesitation.
3. Every rule must be actionable and checkable. Delete rules that are neither.
4. Record the rationale for a significant rule change in `.ai/memory/decisions/`.
