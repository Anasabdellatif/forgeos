# Roadmap

Where this project is going, and how far along each capability is. **`forgeos next` reads this
file** — it picks the next capability from the criteria table below, so a roadmap that is filled in
is the difference between a useful recommendation and `unknown`.

Replace every `TBD` with your own. The structure matters more than the wording: keep the criteria
table, keep its `Status` column, and keep the vocabulary below.

## How to read a status

| Status | Means |
| --- | --- |
| `not built` | No implementation exists yet |
| `partial` | Some of the criterion is met; the rest is named in the row |
| `done` | Every part of the criterion is met and was verified |

`forgeos next` recommends the **smallest incomplete row whose conditions are already satisfied**, so
order the table roughly by dependency: a row that needs another row first should come after it.

## Tracks

A track is a capability large enough to be finished in stages. Give each one a percentage so
progress is a measurement rather than a mood: **criteria met ÷ criteria declared**.

| Track | Today | Phase that raises it |
| --- | --- | --- |
| TBD: capability | TBD% | TBD |

## Phases

Each phase gets its own section and its own criteria table. The section heading is the subject
`forgeos next` matches prohibitions against — a phase about deployment is not told to avoid
deployment — so name the phase after what it builds.

## TBD: first phase

TBD: one paragraph on what this phase is for and what it must not become.

| # | Criterion | Met when | Status |
| --- | --- | --- | --- |
| 1 | TBD: capability | TBD: the observable condition that makes it true | not built |
| 2 | TBD: capability | TBD: the observable condition that makes it true | not built |

## Out of scope

Naming what a roadmap deliberately excludes is worth as much as naming what it includes: a reader
who cannot see the boundary assumes there is none.

- TBD: excluded capability, and the reason.

## Maintenance rule

Update a row's status in the same change that earns it. A roadmap edited later is a roadmap nobody
trusts, and `forgeos next` will recommend work that is already done.
