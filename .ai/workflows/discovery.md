# Discovery Workflow

## Objective

Turn an idea into a defined project — one a stranger could scope, and an agent could build without
inventing a single requirement.

## When It Runs

Automatically, on the first turn of any session where `.ai/context/project.md` still contains
`TBD`. Not on request. The gate is in `.ai/contract/core.md` §0 and in `CLAUDE.md` / `AGENTS.md`,
all of which are read every session.

Also on request, to revisit one phase after a pivot: `/discovery --phase 3`.

## Steps

1. Run `scripts/validation/check-placeholders` and report the blocking count to the user, plainly:
   this project is undefined, here is what is missing, no code until it is not.
2. Load `.ai/contract/discovery.md`.
3. Run the six phases **in order**, one topic at a time:

   | Phase | Produces |
   | --- | --- |
   | 1 Idea | `docs/product/vision.md` |
   | 2 Requirements | `docs/product/requirements.md` |
   | 3 Technology | `.ai/context/stack.md` + `.ai/memory/decisions/` record |
   | 4 Brand and interface | `docs/design/design-system.md` |
   | 5 Architecture | `docs/architecture/overview.md`, `docs/domains/domain-map.md`, `.ai/context/scaffold.json` |
   | 6 Constraints | `.ai/context/constraints.md` |

4. Write each document at the **end of its own phase**. A crashed session must not lose the
   interview.
5. Play the phase back to the user in their own terms. Get a correction or a confirmation before
   moving on.
6. Record anything the user does not know in `.ai/memory/open-questions.md` — the single register —
   with an owner and what it blocks. Never resolve it silently.
7. Delegate Phase 5 to the `architect` subagent. Diagrams follow `.ai/rules/diagrams.md`.
8. Re-run `check-placeholders` until blocking reaches 0.
9. Fill `.ai/context/project.md` — it is the last file, because it summarizes the rest.

## Handover

1. `scripts/ai/scaffold.ps1 -Apply` — creates the directory structure from
   `.ai/context/scaffold.json`. Never overwrites.
2. Fill `.ai/context/structure.md` from what was created.
3. Write the initial backlog into `.ai/tasks/inbox/`, ordered so each task is independently
   shippable, each with observable acceptance criteria.
4. Report and get approval.

## Stop Conditions

Stop and hold the interview when:

- The user asks for code while blocking markers remain. Name what is missing, ask the next
  question, continue.
- A phase depends on an answer the user does not have. Record it as `undecided`, note what it
  blocks, and move to the next topic — not the next phase, if the phase output depends on it.
- The answers contradict each other. Surface both, ask which holds.

## Rules

- Never fill a gap with a plausible default.
- Never choose a technology, pattern, or data model on the user's behalf. Offer, recommend, wait.
- Never start Phase N+1 before the user confirms Phase N.
- Never write source code, install a dependency, or run a framework generator during discovery.
- Separate what the user said from what you inferred, and get inferences confirmed.

## Output

A defined project: 0 blocking markers, every document filled from stated facts, every unknown
recorded with an owner, a directory structure created, and a backlog ready to execute.
