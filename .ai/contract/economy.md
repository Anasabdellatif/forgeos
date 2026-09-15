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
8. **Documented projects are read through their maps.** Where `.ai/product/` holds an authority map
   and a source index, read those compact maps first and open an original document only to verify
   the one passage a citation names. Never copy a specification into always-loaded context, never
   re-read a whole document to answer what a map already cites, and never ask the owner for a value
   before the sources were searched — `.ai/workflows/ingest-project.md`.

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

## 4. Large-session protocol

A launcher under budget does not bound the session it launches. One large database-implementation
session on an adopted project (2026-09-12) started from a brief within budget and still reached
the usage limit: broad specification reads, four migrations, a rehearsal run twice, and full
validation run more than once. The brief is a launcher improvement; this section is the
whole-session bound. It applies to every implementation session, and `forgeos brief` and `forgeos
prompt` carry its one-line form. **None of it relaxes validation, review, safety, or a gate** — it
removes repetition, not evidence.

1. **Single agent.** No subagents, review swarms, background agents, or orchestration modes unless
   the user authorized them in this conversation (`core.md` §3 rule 9). An authorized reviewer
   gets a role packet (`build-context --role`), never the repository.
2. **Read by section, state the reason.** Open the specification sections the slice names —
   one table, one section, one route — never a whole chapter or data-model part. One line saying
   why, before any read over ~200 lines.
3. **Effort is per decision, not per session.** The policy table's effort names the depth for
   the hard decisions in the slice; it is not a licence for broad reads or repeated checks.
4. **Validate once per change.** Narrow check after each step; the full suite once, on the final
   diff. Re-run it only after a change to what it covers. No editing while a long check runs —
   the result would describe a tree that no longer exists.
5. **Cross-platform and selftest only on trigger.** The other shell's `check-all`, `selftest`,
   and the release selftest run only when shell scripts, hooks, or cross-platform tooling changed.
6. **Rehearse SQL once.** A migration or database rehearsal replays only when SQL changed after
   the last successful rehearsal. Record the rehearsal's commit in the task record.
7. **Compact output.** `--compact` where a check offers it; summarize a command's result in one
   or two lines instead of pasting the log. The observed exit code and count are the evidence.
8. **Stop in the usage-risk zone.** After the third full-suite run, the second rehearsal, or a
   context that has grown past the point of holding the diff, stop: refresh the ledger, write the
   handoff (`reporting.md` §0), report, and let the next session continue from files.

The protocol is itself unmeasured: it names the repetition that one incident showed, and the
whole-session comparison in `.ai/memory/open-questions.md` Q-006 remains open until a managed
run of a real slice has been measured against the same slice without it.
