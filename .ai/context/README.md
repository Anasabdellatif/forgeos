# Project Context Index

**Operational summaries, not sources of truth.** `docs/` owns the facts. These files hold what an
agent needs before it knows which document to open, and link back for depth.

## Files

| File | Summarizes | Source of truth |
| --- | --- | --- |
| `project.md` | Identity, primary user, the top non-goal, the hardest constraint | `docs/product/vision.md` |
| `stack.md` | Runtime, versions, **the commands to run**, datastore and service names | `docs/architecture/overview.md` |
| `structure.md` | Where things live — the navigation map | `docs/domains/domain-map.md` (meaning) · `docs/architecture/overview.md` (boundaries) |
| `constraints.md` | Hard constraints that apply to every task | Itself — constraints have no deeper home |
| `current-state.md` | The state ledger: position, last known good, gates, next action | Itself — refreshed at every close, rules in `.ai/contract/economy.md` |
| `scaffold.json` | The directory structure discovery produced | Itself |

`constraints.md` is the one file here that **is** a source of truth: a constraint is a decision
about limits, not a summary of something written elsewhere.

## Context budget

Measured at v1.9.0, so it is a floor to hold, not a target to aim at. Tokens estimated at
four characters each; re-measure with `wc -c` before arguing with a number.

| Layer | Target | Warn at |
| --- | --- | --- |
| Always loaded -- `CLAUDE.md` + `core.md` + `project.md` + `constraints.md` + `current-state.md` | 3,500 | 3,200 |
| One scenario -- discovery, implementation, review, closure | 12,000 | -- |
| One role file in `.ai/agents/` | 900 | -- |
| One profile in `.ai/profiles/` | 1,100 | -- |
| Any single file an agent may load | 2,200 | -- |

The margin is deliberately thin. This layer is near its natural ceiling, so an addition
should displace something rather than accumulate. Since v1.12.0 the always-loaded row is data
-- `policy.contextBudget` in `scripts/lib/blueprint-manifest.json` -- and
`check-context-budget` reports against it on every `check-all` run. It warns; it does not gate.
Since v1.12.3 the row is split: `CLAUDE.md` + `core.md` are the platform floor the blueprint
imposes, the three context files are the project's, and the project's allowance is the target
minus the measured floor -- so an overrun is attributed to whichever side actually owns it.

## Rules

- Keep each file brief enough to load without hesitation. Depth belongs in `docs/`.
- **Never restate a fact that `docs/` owns.** Link to it. A fact with two homes will diverge.
- Separate confirmed facts from assumptions. Assumptions and unanswered questions go to
  `.ai/memory/open-questions.md`, with an owner.
- Do not fill an unknown fact with a guess. Record it as an open question instead.
- While any `TBD` remains in `project.md`, the discovery gate is closed — `.ai/contract/core.md` §0.
