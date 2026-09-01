# Open Questions and Assumptions

**The single register of what this project does not yet know.**

Before this file existed, assumptions and open questions were recorded in six different section
types across five file classes — `docs/product/vision.md`, `docs/domains/domain-map.md`,
`.ai/context/constraints.md`, every task, and every plan — with no index. Nothing could answer
*"what are we still unsure about?"*, and `.ai/contract/discovery.md` §4.3 mandates recording
`undecided: <question>` with an owner while giving it nowhere to land.

That is what this file is for.

## What belongs here

| Kind | Meaning |
| --- | --- |
| `assumption` | Something being treated as true without proof. If it is wrong, work has to change. |
| `question` | Something nobody has decided yet, blocking or not. |

Anything that must be true for the current plan to hold, and that nobody has verified, is an
assumption — whether or not someone wrote it down as one.

## What does not belong here

- A decided matter. That is a decision — `.ai/memory/decisions/`.
- A task. If the answer is "someone must do work", open a task.
- A risk with a known cause and mitigation. That belongs in the plan's `Risks` section.
- A `TBD` in a template. That is an unfilled field, not an open question.

## Rules

1. **Never resolve an entry silently.** Closing one means linking the decision, the task, or the
   answer that closed it, and dating it.
2. **Every entry has an owner.** "The team" is not an owner. An entry with no owner is an entry
   nobody will answer.
3. **State what it blocks.** An open question that blocks nothing is a note; say so, and keep it
   short.
4. **A task or plan may state an assumption locally, but anything that outlives the task belongs
   here.** When a task closes, promote its surviving assumptions into this register.
5. Closed entries stay, with their outcome. The record of what we were once unsure about is the
   most useful part of this file.

## Register

Newest first. Status: `open` · `answered` · `superseded` · `dropped`.

| # | Kind | Question or assumption | Owner | Status | Raised | Source | Blocks | Closed by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TBD: 001 | TBD: `assumption` or `question` | TBD: state it so it can be answered yes or no | TBD: a person | TBD: `open` | TBD: YYYY-MM-DD | TBD: task, plan, discovery phase, or review | TBD: what waits on it, or `nothing` | TBD: decision path, or `—` |

## Example of a filled row

Not project data — a shape reference. See `examples/discovery-example.md` for two in context.

| # | Kind | Question or assumption | Owner | Status | Raised | Source | Blocks | Closed by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 004 | question | Which payment provider, given the region? | product owner | open | 2026-08-03 | discovery phase 3 | subscription billing task | — |
| 003 | assumption | No downstream consumer reads the per-line refund amounts | implementer | answered | 2026-08-01 | plan step 4 | schema change | verified in review, 2026-08-02 |
