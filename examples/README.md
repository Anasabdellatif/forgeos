# Filled Examples

Templates show the shape of a record. These show the **depth**. For an AI agent, a worked example
drives behavior far more reliably than a rule does, because it demonstrates the standard rather
than describing it.

## Files

| Example | Demonstrates |
| --- | --- |
| `discovery-example.md` | How far the interview goes, what "concrete" means, how an unknown gets recorded instead of guessed |
| `task-example.md` | Observable acceptance criteria, honest separation of fact from assumption, real completion evidence |
| `plan-example.md` | Ordered steps that are each independently verifiable, with migration and rollback |
| `decision-example.md` | Real alternatives with real trade-offs, and a falsifiable "how we'd know this was wrong" |
| `handoff-example.md` | Enough for a cold-start agent to continue without rereading anything |
| `lesson-example.md` | A generalizable rule extracted from one incident, not a war story |

## The scenario

**Every scenario in this directory is invented.** The people, products, markets, numbers, brands,
and channels are fiction, written only to demonstrate depth — none of it describes a real project.

Five records describe **one coherent piece of work** on a fictional B2B invoicing product:
a rounding defect in partial refunds, its investigation, the durable decision it forced, the
handoff when it spanned two sessions, and the lesson that came out of it. The discovery example
is a second, unrelated fiction — a hobbyist course platform — invented for the same reason.

Read them in that order and the whole lifecycle becomes concrete.

## How to use them

- Before writing your first record of a given type, read the matching example.
- Judge your own record against it: is it as specific? As falsifiable? As honest about what was
  not verified?
- When a record you wrote is vaguer than the example, the record is wrong — not the example.

## What makes these examples, and not filler

Each one demonstrates a behavior that is hard to get from rules alone:

- **Criteria you can fail.** "Rounding is correct" is not a criterion. "A 3-way split of $10.00
  refunds exactly $10.00, with the remainder cent assigned to the first line — covered by a test"
  is one.
- **Named uncertainty.** Every record says what was *not* checked and what risk that leaves.
- **Evidence, not adjectives.** Commands and their observed output, not "tested and working".
- **Falsifiability.** The decision record states what observation would prove the decision wrong.

## Maintenance

These are reference material, not project data. Keep them consistent with the templates in
`templates/` and with `.ai/contract/`. If a template changes, update the example in the same change.
