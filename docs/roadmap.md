# Roadmap

ForgeOS is in **public preview**. This page says what is being worked on, what is deliberately not
being built, and what would have to be true before anything on the "later" list starts.

It is a direction, not a set of dates. Nothing here is a commitment, and nothing here is for sale.

## Where the project actually is

The engineering core is the mature part: governed write permissions, narrow implementation windows,
cross-shell parity enforced by CI, a self-test suite whose two halves must run the same cases in the
same order, evidence-based validation, and a distribution model that has survived real adoptions
without overwriting a project's own work. That part is done, released, and green.

The younger part is the product surface. The command layer now answers the question a person asks
at the start of a session — *where is this project, and what is the next safe thing to do?* — and
two installer channels are Proven. What remains younger than the engineering is everything built on
top: package-manager channels, a dashboard, the website, and the proof that comes from driving many
projects rather than a few.

**The gap is the product, not the engineering.** That is what this roadmap is about.

## The bar for going public

The technical readiness review passed every criterion the launch contract names; the maturity bar
set after it is recorded in the project decision log.

**The visibility switch has been taken**, by an explicit owner decision: launch as a clean snapshot.
Development continues in a private repository, and the public repository carries a verified snapshot
with a fresh history. The switch changed where the code is visible, not what is proven — the three
capability tracks below are still tracked against their declared criteria:

| Track | Today | Phase that raises it |
| --- | --- | --- |
| Installability | ~85% | M-21, M-22 — installers Proven; package managers deferred with blockers named |
| Project Command Center | **100%** | M-20 — complete |
| Driving a real project end to end | ~60% | M-23 |

The percentages above are the **live** figures, updated as criteria are met; the decision record that set the bar defines the method and is dated history, not a tracker.

**How a percentage is computed, so it cannot become a mood:** each track below declares a fixed list
of criteria before its work starts. The percentage is **criteria met ÷ criteria declared**. 95% means
at most one declared criterion outstanding, and the roadmap must name which one.

## Done

- **Public preview surface.** Trust files, an audited front page, an upgrade guide, an anonymized
  field-reports index, and a public-surface checker promoted from advisory to gating.
- **Release packaging.** A source-only workflow that builds from a tag and publishes a checksummed
  artifact; exercised on real releases. The same tag builds byte-identical archives on Windows and
  POSIX, so a published checksum is reproducible rather than merely recorded.
- **Cross-platform consistency.** The discovery gate and the placeholder checker share one detector,
  and both shells report undeclared files.

Still outstanding from that work: a documented compatibility matrix — which adopted versions can
upgrade to which.

## M-20 — Project Command Center: contract and read-only status engine

**All sixteen declared criteria are met.** `scripts/command/README.md` is the contract.
`project-status` reports where the project is — the ten-section `map`, now with slice ages — and
what to do next: the recommendation, a governance-window draft, a validation plan, and a copy-paste
implementation prompt assembled from those three, all in both shells.

**16 of 16 is the declared list, not the finished product.** The percentage is criteria met ÷
criteria declared, against a list fixed before the work started; it says this phase delivered what
it promised, not that a command centre could not be better. What is honestly unproven here is the
same thing unproven everywhere else on this page: it has been exercised on this repository and on
one adoption, not on many projects with many shapes of roadmap.

Read-only throughout, including the drafts: it writes nothing, and it never authorizes code. Opening
a governance window stays a human act; the engine *drafts* the window a slice needs, and a person
opens it. That is asserted rather than promised — the JSON carries `canModifyFiles`,
`canAuthorizeCode` and `canOpenGovernanceWindow`, all `false`, plus `canApplyAutomatically` on the
draft itself, and a self-test case fails if any is not.

Machine-readable first — the status contract is the foundation every later surface reads, so it
stabilizes before anything is built on top of it.

Declared criteria:

| # | Criterion | Met when | Status |
| --- | --- | --- | --- |
| 1 | `status` command | Runs in both shells, reads project state without writing | **done** |
| 2 | JSON output contract | Versioned schema; `--json` puts JSON on stdout **alone**, human text to stderr | **done** |
| 3 | Human-readable output | The same facts, legible without a parser | **done** |
| 4 | Repository state summary | Branch, version, validation verdict, ledger freshness, drift | **done** |
| 5 | Project map | Directories and ownership as they actually are | **done** — ten sections |
| 6 | Architecture map | Read from `docs/architecture/` and the decision records | **done** |
| 7 | Data model map | Read from `docs/domains/`, reported as unknown when absent | **done** |
| 8 | Requirements map | Read from `docs/product/`, with unfilled markers counted | **done** |
| 9 | Task map | `inbox → active → completed`, with blocked work named | **done** — counts, active names, most recent completed |
| 10 | Active/completed slice map | Which slices are open, which closed, and since when | **done** — `activeAge`, `mostRecentCompletedAge` and `ageSource`, read from git and reported `unknown` when git cannot answer |
| 11 | Next-slice recommendation | The smallest slice whose preconditions are already met | **done** — partial rows before unstarted ones, lowest number within a status, rows with an unmet declared prerequisite skipped and each skip reported |
| 12 | Governance window recommendation | The narrow window that slice needs, drafted not opened | **done** — `governanceDraft`, with `canApplyAutomatically` false and every drafted path proven to exist |
| 13 | Validation plan | What must pass before that slice can be called done | **done** — narrow and full, each entry naming a script that exists |
| 14 | Copy-paste prompt | An implementation prompt generated from repository state | **done** — `generatedPrompt`, deterministic, with the prohibitions that never drop |
| 15 | Progress percentages | Computed from files, never typed by hand | **done** — read from the decision, never computed |
| 16 | No automatic code authorization | A self-test case proves the engine cannot open a window | **done** — asserted by a self-test case |

## M-21 — CLI and local command surface

**All eleven declared criteria are met.** A `forgeos` command wrapping the engine that already
exists, with dry-run as the default on everything that writes and JSON where a caller needs to parse.

The CLI wraps the sync engine, it does not replace it. That engine carries fifteen versions of
proven behaviour and the self-test cases that pin it; ergonomics are not a reason to discard that.
`status` and `next` route to `project-status` and are asserted byte-identical to it, which is what
keeps one answer in one place.

The declared criteria below were written as prose before the work started and are unchanged in
substance; they are a table now so the command centre can read their status the way it reads M-20's.

`status`, `next`, `doctor` and `version` read. **`adopt` and `update` are the two commands that can
write, and only when asked**: both delegate to `sync-blueprint`, whose own default has always been to
report rather than write, so a bare invocation of either is a dry run and `--apply` is the writing
mode. `--force` is never passed and never exposed — it is the flag that would overwrite a file the
adopting project had customized, and a wrapper quietly offering it would undo the guarantee the sync
engine exists for.

`adopt` brings ForgeOS into a project that does not have it; `update` refreshes one that does, and
**refuses a target that has never adopted** rather than quietly performing a first-time seeding under
a word that promises only a refresh. The two share one delegation block, so they cannot drift apart.

**11 of 11 is the declared list, not a finished CLI.** It is a local command surface that lives beside
what it wraps; putting a `forgeos` executable on a PATH is M-22's problem, not this one's.

| # | Criterion | Met when | Status |
| --- | --- | --- | --- |
| 1 | `status` command | Exists in both shells, wrapping the engine | **done** |
| 2 | `doctor` command | Exists in both shells | **done** |
| 3 | `version` command | Exists in both shells | **done** — reads blueprint.version, and reports the release as unknown rather than inferring it from a tag |
| 4 | `adopt` command | Exists in both shells, wrapping the sync engine | **done** — delegates to sync-blueprint, never passes `--force`, and copies none of its logic |
| 5 | `update` command | Exists in both shells, wrapping the sync engine | **done** — the same delegation as `adopt`, with a precondition: it refuses a target that has never adopted |
| 6 | Dry-run is the default | Every writing command reports before it writes | **done** — `adopt` is the only writing command and a dry run is what it does unasked; a case pins it, and `update` must inherit the same default |
| 7 | `--json` for `status` and `doctor` | Machine-parsable, on stdout alone | **done** — plus `next`, which the same wrapper exposes |
| 8 | House exit codes | `0` reported, `1` could not run, `2` refused by a gate | **done** — `2` is never emitted, and the contract says so |
| 9 | `doctor` reports its prerequisites | Shell version, JSON reader capability, git presence, hook wiring, line-ending policy | **done** — nine rows, five of them required |
| 10 | Clear first-run diagnostics | A failed prerequisite names itself and what to do about it | **done** — proven by a fixture with the engine removed |
| 11 | Self-test parity | Identical case labels and order on both shells | **done** |

## M-22 — Installability channels

**The architecture is decided; five channels are Proven, the rest deferred or declared.**
The architecture contract is recorded in the project decision log.

**Installable means verifiable, not convenient:** a user can obtain a specific version, confirm it is
the one published, and run `forgeos` against their own project — without executing anything they have
not had the chance to read. Convenience is not on that list; a channel that is convenient and
unverifiable is a liability with good ergonomics.

Each channel sits on one rung, and **the rung is a claim about evidence**: *Proven* (a job or case
fails if it breaks) · *Working* (done by hand, written down) · *Declared* (contracted, not built) ·
*Deferred* (not built, blocker named) · *Refused* (would break a rule).

| Channel | Rung | Blocker |
| --- | --- | --- |
| Release artifact — download, verify checksum, extract, sync | **Proven** | — |
| Source clone — clone, discard history, init | **Proven** | — |
| Local `forgeos` command | **Proven** | — |
| PowerShell installer — downloaded, **read**, then run | **Proven** | — |
| POSIX installer — downloaded, **read**, then run | **Proven** (Linux) | macOS still unclaimed — no macOS job (002) |
| Docker or devcontainer — pinned digest | Declared | none; low priority |
| npm / npx | **Deferred** | question 003 — the name is unchecked |
| Homebrew | **Deferred** | question 002 — no macOS CI job exists |
| Scoop · Winget | **Deferred** | no demand yet; Winget also needs a public release cadence |
| GitHub template · GUI installer | **Refused** | a template forks a repository, not a version; a dashboard is already declined below |

**The first public version needs the three Proven channels plus one documented, checksum-verifying
installer.** Everything else ships as *deferred with its blocker named*, because a channel silently
missing reads as an oversight while a channel named as deferred reads as a decision.

**Both installers exist and are Proven.** `scripts/install/install-forgeos.ps1` writes two shims on
Windows; `scripts/install/install-forgeos.sh` writes one executable launcher on Linux. Same contract
either way: they fetch nothing, never change PATH — the line is printed for you to add — verify a
`.sha256` when one sits beside the source and **fail closed on a mismatch**, refuse `--force` by
name, and remove only the file they wrote. Dry run is the default for both.

**The install matrix runs, and both channels are Proven.** `validate.yml` carries two jobs —
`install-windows` and `install-posix` — that build a release artifact, refuse a corrupted one,
install from the good one, answer `version` and `doctor` through the shim or launcher, adopt a
fresh project through it, run `check-all` inside that project, and require a customized file to
survive an update. That is all five conditions the ladder names, and the full matrix ran green on
all eight CI jobs.

The promotion was earned by that run rather than by writing the tests, which is the distinction the
ladder exists to keep. The matrix earned it the hard way too: it failed three times first, and each
failure was real — a POSIX builder invoked on a Windows runner producing a three-file artifact, a
quoting rule applied to the wrong invocation style, and finally a genuine product defect where the
installer's `Get-FileHash` is unavailable to a PowerShell 5.1 child launched from pwsh 7.

**macOS remains unclaimed**, because no job runs there. Condition 5 is *every platform the channel
claims*, and the POSIX installer claims Linux and says so in its own usage text. Open question 002.

**The POSIX half claims Linux and does not claim macOS.** Open question 002 records that it has
never run there and that CI has zero macOS jobs. It very probably works on macOS; "probably" is not
a rung, and the installer says so in its own usage text rather than leaving the reader to assume.

Safety criteria, non-negotiable and each pinned by a test:

- **No unsafe remote script pipe.** No `curl \| bash`, no `iwr \| iex`, at any layer. The project's
  own hook refuses that command shape and a product may not ask users to do what its hook refuses.
- **No silent overwrite of project-owned files.** The existing guarantee, extended to every channel.
- **Dry-run mode** on every channel that writes.
- **Rollback and backup**: adoption and upgrade land as one revertible commit, and the path back is
  documented rather than implied.
- **Checksum verification** available and documented for every downloadable channel.
- **No hidden telemetry.** Nothing is collected, so there is nothing to disclose or opt out of.
- **Upgrade flow for adopted projects** works from every channel, not only from a clone.

## M-23 — End-to-end field adoption

The proof that ForgeOS drives a project rather than only protecting one. A real project, adopted and
driven through the full loop, with the findings written up under the existing anonymization rule.

Declared criteria:

| # | Criterion |
| --- | --- |
| 1 | Project discovery from existing files, not from an interview alone |
| 2 | Requirements reconstructed into `docs/product/` from what the code and the owner actually say |
| 3 | Architecture documented in `docs/architecture/` and matching the code |
| 4 | A programmer specification a new contributor can implement from |
| 5 | Data model documented in `docs/domains/` |
| 6 | Work delivered as small implementation slices, each with acceptance criteria |
| 7 | Completion recorded per slice, with evidence, in the task record |
| 8 | **No context loss between sessions** — a new session resumes from files alone |
| 9 | The next prompt generated from repository state, not composed by hand |
| 10 | The full loop `/start-task → /implement → /review → /finish-task` run end to end on a real slice |
| 11 | The three never-dispatched roles exercised: `product-analyst`, `data-reviewer`, `release-manager` |

**Definition of done for the field adoption:** three consecutive real slices are opened, planned,
implemented, reviewed and closed through the loop, in separate sessions, with every session
resuming from the repository rather than from recollection — and the defects that surfaced are
closed and pinned by permanent cases, as every previous field finding has been.

## M-24 — Public launch hardening

The visibility switch was taken by an explicit, separately authorized owner decision — a clean
public snapshot with a fresh history, while development continues privately. Hardening continues
after it, not instead of it:

- Re-run the readiness review against the raised bar, not the original one.
- Re-check every public numeric claim: the checker already does this on every run.
- Confirm the three tracks' percentages from their declared criteria lists, naming any outstanding
  criterion.

## Not being built

Each of these was considered and declined; the reasoning is recorded in the project decision log
(records predating the public launch live in the development line):

- **Telemetry or analytics of any kind.** Nothing is collected, so there is nothing to opt out of.
- **An installer that executes remote code.** The project's own hook refuses that command shape.
- **A hosted service, paid tier, or team governance product.** Not while the open core is still
  proving itself in public.
- **Agent orchestration, app templates, or an integration marketplace.** Adjacent, and not this.
- **Renaming the paths.** The repository is now `forgeos`, decided before public visibility rather
  than after — a rename costs a redirect while a project is private and costs every adopter's URL
  once it is not. The paths inside it keep the engineering name: `blueprint.version`,
  `sync-blueprint`, `blueprint-manifest.json`. Adopting projects invoke those by path and record
  that filename, so renaming them is a breaking change that renaming the page never was.
- **Any public claim without an artifact behind it.** Including on this page.

## What is honestly unproven

- **macOS.** The POSIX half is expected to run there and has never been tested on it. CI runs
  Windows and Ubuntu.
- **The full work loop.** Parts of the task lifecycle have never been exercised end to end on a
  real task.
- **Scale.** This has been proven on real projects, not on many projects at once.

That list is kept current on purpose. A roadmap that only lists strengths is marketing.
