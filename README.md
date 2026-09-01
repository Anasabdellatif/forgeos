# ForgeOS

**An engineering operating system for governed software delivery.**

[useforgeos.com](https://useforgeos.com)

[![Validate Blueprint](https://github.com/Anasabdellatif/forgeos/actions/workflows/validate.yml/badge.svg)](https://github.com/Anasabdellatif/forgeos/actions/workflows/validate.yml)
[![release](https://img.shields.io/badge/release-latest-1f6feb)](https://github.com/Anasabdellatif/forgeos/releases/latest)
![status: public preview](https://img.shields.io/badge/status-public%20preview-6e7781)
![licence: MIT](https://img.shields.io/badge/licence-MIT-blue)
![platforms: Windows + POSIX](https://img.shields.io/badge/platforms-Windows%20%C2%B7%20POSIX-555)

Coding agents are good at writing code and bad at remembering why. ForgeOS gives them what a serious
codebase already assumes: a durable project memory, write permissions a human opens deliberately,
and validation that has to produce evidence before anything may be called done. The rules are not
advice in a document. Where it matters, a machine enforces them.

Current version: **`1.15.30`** · MIT · Windows PowerShell 5.1 and POSIX bash · adopted by copying a
checksummed release artifact or a clone into your project — [Quick start](#quick-start).

> **ForgeOS is the product name; the blueprint is the engineering core** that implements it. The
> repository is [`Anasabdellatif/forgeos`](https://github.com/Anasabdellatif/forgeos); the paths
> and filenames inside it — `blueprint.version`, `sync-blueprint`, `blueprint-manifest.json` —
> deliberately keep the engineering name, because adopting projects already depend on them and
> renaming a path is a breaking change a rename of the page is not.

## Who it is for

Teams and individual builders using AI coding tools on work that has to survive: long-lived
codebases, real users, and more than one session.

| If this happens to you | ForgeOS answers with |
| --- | --- |
| The agent re-derives the same context every morning | A durable memory and a one-screen state ledger, metered against a token budget |
| It writes application code nobody authorized | A governance gate that keeps application paths closed until a human opens a named window |
| It reports "done" without running anything | A closure gate that refuses unchecked criteria and placeholder evidence |
| A decision survives only in a chat log | Decisions, lessons, incidents and open questions as files, in the repository |
| The rules drift between Claude Code and Codex | One contract, two thin adapters, checked for duplication |

It is deliberately **not** an app framework, a prompt collection, an autonomous development team, or
a replacement for the agent you already use.

## Quick start

Two ways in. Both end at the same place: your project carries the portable half of the blueprint and
passes its own validation suite. There **is** a local `forgeos` command and an installer for each
platform — both **Proven** on the platforms they claim, and neither is required for the two routes below. There
is no `curl`-into-a-shell, which this project's own hook refuses and which will not be added.

### 1. From the release artifact (recommended)

Download both files from the [latest release](https://github.com/Anasabdellatif/forgeos/releases/latest)
— for `v1.15.30` that is
[`forgeos-1.15.30.tar.gz`](https://github.com/Anasabdellatif/forgeos/releases/download/v1.15.30/forgeos-1.15.30.tar.gz)
and
[`forgeos-1.15.30.tar.gz.sha256`](https://github.com/Anasabdellatif/forgeos/releases/download/v1.15.30/forgeos-1.15.30.tar.gz.sha256)
— then:

```bash
sha256sum -c forgeos-1.15.30.tar.gz.sha256     # verify before you trust it
tar -xzf forgeos-1.15.30.tar.gz

bash forgeos-1.15.30/scripts/blueprint/sync-blueprint.sh --source forgeos-1.15.30 --target <project>
bash forgeos-1.15.30/scripts/blueprint/sync-blueprint.sh --source forgeos-1.15.30 --target <project> --apply
```

```powershell
(Get-FileHash -Algorithm SHA256 forgeos-1.15.30.tar.gz).Hash   # compare with the .sha256 file
tar -xzf forgeos-1.15.30.tar.gz

powershell -NoProfile -ExecutionPolicy Bypass -File forgeos-1.15.30/scripts/blueprint/sync-blueprint.ps1 -Source forgeos-1.15.30 -Target <project>
powershell -NoProfile -ExecutionPolicy Bypass -File forgeos-1.15.30/scripts/blueprint/sync-blueprint.ps1 -Source forgeos-1.15.30 -Target <project> -Apply
```

The archive is a **sync source, not a product bundle**: it carries what sync copies plus the
scaffolding a new project needs, and none of this repository's own answers, history, or release
tooling. The same tag builds a byte-identical archive on Windows and on POSIX, so the published
checksum is reproducible rather than merely recorded.

### 2. From a clone

```bash
git clone https://github.com/Anasabdellatif/forgeos.git my-project   # then make the history yours
cd my-project && rm -rf .git && git init -b main
```

```bash
# existing project — point sync at the clone instead
bash scripts/blueprint/sync-blueprint.sh --source <blueprint> --target <project>
bash scripts/blueprint/sync-blueprint.sh --source <blueprint> --target <project> --apply
```

### 3. Then, in either case

```bash
bash scripts/validation/check-all.sh
```

The first run is expected to report unfilled markers: those are the facts your project must supply.
**The adoption step is the product** — an unadopted blueprint gives an agent structure with no
knowledge. Full procedure: [`docs/adoption.md`](docs/adoption.md). Already adopted and upgrading:
[`docs/adoption-upgrade-guide.md`](docs/adoption-upgrade-guide.md).

## Proof

Every number on this page is either checked mechanically or printed by a command you can run. The
check that enforces the first group exists because this page once announced a version four releases
stale while the repository mechanically verified everything else and never looked at its own
front page.

| Claim | How to verify it yourself |
| --- | --- |
| Eleven checks, eight of them gating | `bash scripts/validation/check-all.sh` — the summary names each row and its class |
| 202 self-test cases, identical on both shells | The same run prints the total; CI's parity job compares the two lists case by case |
| 144 policy controls | `bash scripts/validation/check-policy.sh` |
| Every referenced path resolves | `bash scripts/validation/check-links.sh` — 528 references across 134 files, 0 broken, 0 unportable |
| This page agrees with the repository | `bash scripts/validation/check-public-surface.sh --fail-on-drift` |
| Eight CI jobs, green on the pushed commit | `.github/workflows/validate.yml`, and the Actions tab |
| The release artifact is what it claims | `sha256sum -c` against the published `.sha256`, then `tar -tzf` to read it before extracting |

## What it does today

| Capability | What it means in practice |
| --- | --- |
| **Operating contract** | One authoritative rule set in `.ai/contract/`, loaded by both Claude Code and Codex through thin adapters that are checked for duplication |
| **Project memory** | Decisions, lessons, incidents, handoffs, and an open-questions register in `.ai/memory/` — so a decision never lives only in a chat log |
| **Governance windows** | Application paths stay closed until a human opens them; a narrow `implementationWindow` authorizes one slice rather than the whole codebase |
| **Safety hooks** | Destructive commands, writes into an undefined project, and secret-shaped strings are refused before they run, with the reason |
| **Lifecycle discipline** | `inbox → active → completed`, with a closure gate that refuses a task carrying unchecked criteria or placeholder review evidence |
| **Validation gates** | Eleven checks run by one command on both platforms and in CI |
| **Cross-shell parity** | Every script exists as `.ps1` and `.sh`, and CI fails if the two self-test suites diverge by a single case |
| **Context-budget attribution** | The always-loaded set is metered against a recorded budget, and an overrun names its owner — the platform floor or the project's own files |
| **Adoption safety** | Sync is a dry run by default, never touches a project's own files, and skips local customizations instead of overwriting them |
| **Release-based adoption** | A checksummed artifact built from a tag by a workflow that is declared source-only, so it never lands in an adopting project and tries to release theirs |
| **Public trust surface** | Security, support, contributing, conduct, templates, roadmap — and a check that audits this page against what the tools actually report |

## What it does not do yet

Stated plainly, because a preview that oversells is worse than one that waits:

- **No package managers.** The installers are scripts you download, read, then run. There is no
  `npx`, no `brew`, no Scoop or Winget — each deferred on the roadmap with its blocker named — no
  Docker image (declared, low priority), and no `curl`-into-a-shell, which is refused by this
  project's own hook and will not be added.
- **No dashboard.** A read-only local one comes after a stable machine-readable status contract.
- **No hosted service, no paid edition, no telemetry.** Nothing is collected or transmitted.
- **macOS is not proven.** The POSIX half needs bash 4+ and GNU tools; stock macOS ships bash 3.2
  and BSD utilities. It should work with modern bash and coreutils ahead of `PATH`, but no CI job
  runs there, so it is documented as unverified rather than supported.
- **Parts of the work loop are unexercised.** See [Status](#status).

## What is actually enforced

Rules that depend only on good intentions get followed until the first deadline. These do not.

**Eight gating checks and three informational reports**, all run by `check-all` on both platforms
and in CI:

| Check | Fails when |
| --- | --- |
| `check-structure` | A declared path is missing or empty, or a file exists undeclared |
| `check-empty-files` | A file is empty, whitespace-only, or carries a UTF-8 BOM where one breaks tooling |
| `check-policy` | 144 controls: permission rules, hook wiring **by script name**, entrypoint and adapter thinness, source-of-truth summaries, role/adapter pairing, profile integrity, the open-questions register, the source-only classification |
| `check-links` | Any referenced repository path does not resolve, or a file that lands in an adopting project references one that does not travel with it |
| `check-blueprint-version` | The version file is missing, unparseable, or the synced set has drifted |
| `scan-secrets --scan-tree` | Ten secret patterns across every tracked file. Reports file, line, and pattern name — **never the value** |
| `selftest` | The safety hooks themselves stop blocking what they must block — 202 cases per shell |
| `check-public-surface` | **This page** disagrees with what the tools report: a stated version, a check count, a claim the repository contradicts, or a public trust file that could reach an adopting project |
| `check-placeholders` | *Informational:* an adoption-readiness score, weighted by impact |
| `check-context-budget` | *Informational:* the always-loaded context against its recorded budget, attributed to its owner |
| `check-state-freshness` | *Informational:* how far the state ledger lags HEAD — and it refuses to answer at all under a shallow clone rather than guess |

**Runtime controls**, placed by measured cost:

| Control | Mechanism | Cost |
| --- | --- | --- |
| No force push, hard reset, recursive force delete, DB drop, infra destroy, remote-script pipe | `guard-bash` hook — blocks with the reason | ~280 ms per `Bash` call |
| Completed tasks and plans are an immutable archive | `deny` permission | zero |
| No secrets or key material written into the tree | `deny` permission + `scan-secrets` on `Stop` | zero + once per turn |
| No code is written into an undefined project | `guard-discovery` hook — blocks the write with exit `2` | one scan per write |
| No application code until a human authorizes it | `guard-governance` hook — reads the project's `governance.json`, blocks protected paths, names the open gates | one JSON read per write |
| A task cannot close with unchecked criteria or placeholder review evidence | `finish-task` gate, exit `2` | on demand |
| N projects stay on one blueprint | `sync-blueprint` + `check-blueprint-version` | on demand |

Anything a permission glob can express is a `deny` rule, because the harness enforces those at zero
latency and they cannot fail open. **Hooks are a safety net against accidents, not a security
boundary** — [`.github/SECURITY.md`](.github/SECURITY.md) says exactly where they stop.

## Upgrading

Re-run the same sync from a newer source. Three guarantees make that safe, and each is pinned by
self-test cases that replay the failure that produced it:

- **Blueprint-managed files update.** The portable half — contract, rules, workflows, agents,
  skills, `.claude/`, scripts, templates — is replaced with the newer version.
- **Project-owned files are never touched.** `.ai/context/`, tasks, plans, memory, `docs/`,
  `README.md`, and `blueprint.version` belong to the adopting project from the moment they land.
- **Local modifications are detected, not destroyed.** `blueprint.version` records a SHA-256 per
  synced file; a file you edited no longer matches, so it is **reported and skipped** rather than
  overwritten. Diff it, decide, then re-run with `--force` if you want the upstream copy after all.

A version bump signals that the portable half changed in a way projects should take. The full
procedure — reading the sync counters, resolving a local customization, what each report means,
and what changes between 1.14.x and 1.15.x — is
[`docs/adoption-upgrade-guide.md`](docs/adoption-upgrade-guide.md). Engine details:
[`scripts/blueprint/README.md`](scripts/blueprint/README.md). What changed:
[`docs/changelog.md`](docs/changelog.md).

## Cross-platform

Every script exists as `.ps1` and `.sh` with identical behaviour, and CI runs both. `.gitattributes`
pins line endings so a shell script cannot arrive on POSIX with CRLF. The POSIX suite runs twice —
once with `jq` present, once with it hidden — because the scripts read JSON through either `jq` or
`python3`, and both branches deserve proof rather than assumption.

| Environment | Status |
| --- | --- |
| Windows PowerShell 5.1 | **CI on every push** |
| Ubuntu / Linux, bash 4+ with GNU coreutils | **CI on every push**, twice: with `jq` and with it hidden |
| WSL, Git Bash on Windows | Exercised by hand during development. No CI job |
| Stock macOS | **Not proven** — bash 3.2 and BSD utilities; expected to need `brew install bash coreutils findutils` |

POSIX scripts choose their JSON reader by **capability, not presence**: `jq` first, then a `python3`
that can actually parse — on Git Bash a Microsoft Store stub sits on `PATH` and cannot — then
`python`, then a clear fail-closed message.

## How the work runs

| Command | Purpose |
| --- | --- |
| `/discovery` | Define an undefined project — six phases, fires automatically |
| `/adopt` | Fill the blueprint from an existing codebase |
| `/start-task` | Turn a request into a bounded task with observable criteria |
| `/implement` | Apply it as the smallest complete change |
| `/review` | Independent correctness, safety, and evidence check |
| `/finish-task` | Close only after the full Definition of Done |
| `/handoff` | Continuation record for another agent or session |
| `/adr` | Record a durable decision |
| `/build-context` | Package deterministic context for transfer |
| `/blueprint-validate` | Run every check |

And beside the workflows, a local `forgeos` command wraps the same engine — reading commands answer,
writing commands dry-run by default and write only under `--apply`, and `--force` is never exposed:

| `forgeos …` | Purpose |
| --- | --- |
| `status` · `next` | Where the project is, and the next safe slice — `--json` for machines |
| `doctor` | Nine prerequisite rows: shell, JSON reader, git, hook wiring, line endings |
| `version` | Which ForgeOS this is; a release is reported unknown rather than inferred from a tag |
| `adopt` | Bring ForgeOS into a project — dry run first, `--apply` to write |
| `update` | Refresh an adopted project; refuses a target that never adopted |

Eight roles each own a different question — *what is being asked · what shape should this take · what
is the smallest complete change · what evidence proves it · is it correct and in scope · what is the
worst reachable outcome · is it safe to reverse · is the evidence enough to ship*. Five profiles bind
a system's kind to the roles and gates it cannot skip. Codex reads the identical contract through
`AGENTS.md`.

## Token economy

A governance layer that made every session more expensive would be self-defeating, so the spend is
engineered and measured:

- **The always-loaded set is small and metered.** Five files, ≈ 3.5k tokens, reported against a
  recorded budget on every run. Everything else loads on a named trigger.
- **State survives sessions.** `.ai/context/current-state.md` answers "where are we, what was
  decided, what runs next" in one screen, so no session reconstructs state from history.
- **Handoffs default to a minimal context package** — the work itself, not a repeat of the contract
  the next session loads anyway.
- **Targets are recorded, not promised.** The ≤ 50% figure against an unmanaged session is a target
  with a measurement still owed — it is listed as an open assumption, not as a result.

## What real adoption taught it

The hardest defects in this repository were not found by its own tests. They were found by using it
on real work, and each one is now a permanent check. The reports are written to describe what broke
in ForgeOS — never what the adopting project does, and never with a client, customer, or repository
name attached. The full index is [`docs/field-reports.md`](docs/field-reports.md).

- A closure gate accepted **placeholder text** as evidence that a security review had happened. It
  now refuses ten placeholder shapes, in two languages.
- The same gate then answered **differently on Windows and POSIX**, because one regex treated a
  newline as ordinary whitespace. A gate whose verdict depends on the platform is not a gate.
- A sync **laundered a local customization's hash**, so the edit survived exactly one upgrade and
  was silently overwritten by the next. Six cases replay that sequence now.
- A freshness meter reported **OK under CI's shallow clone**, where it could not see enough history
  to know anything. It now says what it cannot measure.
- Building a release artifact and then **using** it showed that sync seeded from the target path
  rather than the file it copies from — so a project adopted from an artifact started with no
  identity, constraints, or governance. Inspection would never have found it.
- This page claimed a version **four releases old**, and nothing noticed. That is why
  `check-public-surface` exists.

## Project Command Center

ForgeOS enforces the floor — memory, governance, validation, release, and adoption safety — and
answers *may this happen* and *did it actually work*. The command layer answers the question a
person asks at the start of a session: **where is this project, and what is the next safe thing
to do?**

Its read-only engine is shipped: `forgeos status` and `forgeos next` read the project's own truth —
the state ledger, the open questions, the task and plan state, the governance windows, the
validation output — and produce a **status** answer, a **map** of the system as it actually is, the
**next safe slice** of work, a **draft** of the governance window that slice would need, and a
**copyable implementation prompt** for the agent that will do it.

Two constraints are part of the design, not caveats added later:

- **Read-only.** The command layer writes nothing. It reads project state and reports; a layer that
  proposes work has no business also performing it. Surfaces built on top of it — a dashboard among
  them — stay on the roadmap until the status contract has proven stable.
- **It never authorizes code by itself.** Opening a governance window stays a human act. The command
  layer *drafts* the window it thinks a slice needs — `canApplyAutomatically` is `false` and a
  self-test case fails if it is not; a person still opens it.

The order is deliberate, and it is the same order the roadmap already follows: machine-readable
status before any interface built on top of it. [`docs/roadmap.md`](docs/roadmap.md) carries the
full version, including what is deliberately not being built.

## Public trust

| | |
| --- | --- |
| Website | [useforgeos.com](https://useforgeos.com) |
| Security policy and disclosure | [`.github/SECURITY.md`](.github/SECURITY.md) |
| Support scope and how to ask well | [`.github/SUPPORT.md`](.github/SUPPORT.md) |
| Contributing rules | [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md) |
| Code of conduct | [`.github/CODE_OF_CONDUCT.md`](.github/CODE_OF_CONDUCT.md) |
| Bug report · feature request | [`.github/ISSUE_TEMPLATE/bug_report.md`](.github/ISSUE_TEMPLATE/bug_report.md) · [`.github/ISSUE_TEMPLATE/feature_request.md`](.github/ISSUE_TEMPLATE/feature_request.md) |
| Pull request template | [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md) |
| Upgrade guide for adopters | [`docs/adoption-upgrade-guide.md`](docs/adoption-upgrade-guide.md) |
| Field reports | [`docs/field-reports.md`](docs/field-reports.md) |
| Roadmap | [`docs/roadmap.md`](docs/roadmap.md) |
| Public preview readiness review | [`docs/public-preview-readiness.md`](docs/public-preview-readiness.md) |
| Changelog | [`docs/changelog.md`](docs/changelog.md) |

## Structure

```
CLAUDE.md · AGENTS.md          Entry points. Pointers only — no rules of their own.

.ai/
  contract/                    The operating contract. core.md is always loaded; the rest is pulled.
  context/                     Operational summaries: project, stack, structure, constraints, state.
  rules/                       How work is written: coding, testing, security, ai-safety, git, docs.
  workflows/                   Repeatable procedures: discovery, start, implement, review, finish.
  skills/                      Reusable techniques: debugging, navigation, tests, refactoring.
  agents/                      Eight roles, each owning a different question.
  profiles/                    Five project types binding a system's kind to mandatory roles.
  tasks/  plans/               Work state: inbox → active → completed.
  memory/                      decisions · lessons · incidents · handoffs · open-questions.md

.claude/                       Claude Code adapter: subagents, slash commands, skills, hooks.
docs/                          Source of truth: product, architecture, domains, design, operations.
examples/                      Six filled reference records. These set the depth bar.
scripts/                       Task helpers, validation, enforcement hooks, distribution, release.
templates/                     Record templates.
```

## Roadmap

**Now** — public launch: a clean, verified snapshot, with the trust surface and this page both
checked rather than asserted. The release path is proven: a version tag builds a checksummed
archive through a workflow that never reaches an adopting project.
**Next** — driving a real project end to end through the full work loop, and the field reports
that come out of it.
**Later** — package-manager channels (each currently deferred with its blocker named), a
read-only dashboard on top of the status contract, and the website at
[useforgeos.com](https://useforgeos.com).

Full version, including what is deliberately not being built:
[`docs/roadmap.md`](docs/roadmap.md).

## Status

The changelog lives in `blueprint.version`; see [`docs/changelog.md`](docs/changelog.md) for how to
read it.

### Proven

- **Both platforms.** Every gating check passes on Windows PowerShell 5.1 and on POSIX bash.
- **CI.** Eight jobs, green on the latest push — ShellCheck over every tracked shell script, a check
  that the committed tree matches the line-ending policy, a job that fails if the two hook
  self-tests ever diverge by one case, and an install matrix that builds a release artifact,
  refuses a corrupted one, installs from it, and runs the full validation suite inside the project
  that install created.
- **Adoption, not only self-test.** Real adoptions found defects no check inside this repository
  could see; each is closed and guarded by a permanent case. A freshly synced project passes the
  whole suite on its first run.
- **Release, end to end.** A version tag builds a checksummed artifact and publishes it; the
  published archive was downloaded, verified, synced into a fresh repository, and that project
  passed its own validation suite.
- **The gates are enforced, not stated.** The discovery gate, the governance gate, and the closure
  gate all refuse with exit `2` and are covered by self-test cases on both platforms.

### Not proven

- **The full work loop has never run end to end.** `/start-task → /implement → /review →
  /finish-task` has not been exercised on a single real task from open to close.
- **Three roles have never been dispatched** — `product-analyst`, `data-reviewer`, `release-manager`.
- **A task can still under-declare its scope.** The closure gate checks the declared scope tags;
  the declaration is the task's own. Catching a wrong one is `/review`'s job, and review is
  procedure, not a gate.
- **Discovery has been run through phase 1 only.** Phases 2 to 6 are untested.
- **The gate hooks are Claude Code only.** Codex reads the same rules in `AGENTS.md`, where they
  remain prose.
- **macOS.** Unverified, as above.
- **The token target is unmeasured.** Recorded as an open assumption.
- **The Command Center engine has run on this repository and one adoption only.** Surfaces built
  on its status contract — a dashboard among them — do not exist.

Project-specific context, requirements, architecture, domain, and operations facts must still be
supplied by each adopting project — [`docs/adoption.md`](docs/adoption.md).

## Licence

MIT — see `LICENSE`. Copy it, adopt it, adapt it, use it commercially; keep the copyright notice.

`LICENSE` is treated as project-specific: sync never copies it into an adopting project, and
`check-structure` never requires one. A project's licence is its own decision, not something a
blueprint should inherit into it.
