# Operating Contract — Session Economy

Extends `core.md` §2 and §10 with the rules that keep token spend proportional to the work, and
the targets that make "efficient" a measured claim instead of a mood. Load on session start over a
defined project, when preparing a handoff, or when a budget question comes up.

## 1. The rules

1. **Sessions start from the ledger.** Read `.ai/context/current-state.md`, then act. Do not
   reconstruct project state from history, old handoffs, or a repository scan when a current
   ledger exists.
2. **Heavy files are read on trigger, with the reason stated.** Files that are large or rarely
   decisive load only when the task at hand needs them — say why in one line. That list, for this
   repository: deep `docs/` pages · `scripts/validation/README.md` · `blueprint.version` history ·
   `scripts/hooks/selftest.*` · `scripts/lib/blueprint-manifest.json` · `.ai/memory/` records
   other than the one relevant record.
3. **Every phase ends in durable state.** Before a session ends or a task closes, refresh the
   ledger: position, last validation, next action. Work that lives only in the conversation is
   work the next session pays for twice. The gate and the full what-goes-where table:
   `.ai/contract/reporting.md` §0.
4. **Decisions leave the conversation.** A decision that matters gets a record in
   `.ai/memory/decisions/` and one pointer line in the ledger — same session, not later.
5. **`build-context --minimal` is the default handoff** between sessions that both load this
   project's contract. Full mode is only for a receiver that cannot be trusted to read
   `CLAUDE.md`, `AGENTS.md`, and `.ai/context/` by itself — see `.ai/workflows/handoff.md`.
6. **No re-analysis past a valid pointer.** If the ledger or a status names the answer's home, go
   there directly. Re-deriving what a pointer already states is spend without information.
7. **The budget is measured, not asserted.** `scripts/validation/check-context-budget` reports the
   always-loaded total against the recorded budget on every `check-all` run.

## 2. Delivery targets

Recorded so progress is comparable across projects. Targets, not promises — each claim must cite
a measurement.

| Measure | Baseline | Target |
| --- | --- | --- |
| Token spend per delivered change | unmanaged AI workflow = 100% | **≤ 50%** |
| MVP / vertical slice of a documented project | months, unmeasured | **5–10 working days, measured** |
| Production first release | — | sized per project, but measured from day one |

The saving comes from removing waste — re-discovery, re-analysis, contract repetition in
handoffs — never from skipping validation, review, or gates. A number without a measurement
behind it is a claim this file forbids.

**Measured so far** (this repository, v1.12.0): always-loaded context ≈ 3.2k tokens where an
unmanaged session re-derives project state each time; a minimal handoff carries ~1–25% of the
bytes of a full package. The ≤ 50% end-to-end figure is a target until a managed and an
unmanaged run of the same scope have both been measured — no such comparison has been run yet.

## 3. Measurement method

- Tokens are estimated as characters ÷ 4; re-measure with `wc -c` before arguing with a number.
- The always-loaded set and its budget are data: `policy.contextBudget` in
  `scripts/lib/blueprint-manifest.json`. The meter is `scripts/validation/check-context-budget`,
  informational in `check-all` — it warns, it does not gate. The set is split into the platform
  floor (`CLAUDE.md` + `core.md`, the blueprint's to fix) and the project files (the project's
  to trim); the project's allowance is the target minus the measured floor, so an overrun is
  attributed to its owner.
- Package sizes come from `scripts/ai/build-context` (`--minimal` vs full), measured on stdout.
- Time-to-MVP is measured from the first discovery session to the accepted vertical slice, in
  working days, recorded in the project's `.ai/memory/`.
