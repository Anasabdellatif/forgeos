# ForgeOS

**An engineering operating system for governed software delivery across Claude Code, Codex, and
similar CLI-based coding tools.**

[![Validate Blueprint](https://github.com/Anasabdellatif/forgeos/actions/workflows/validate.yml/badge.svg)](https://github.com/Anasabdellatif/forgeos/actions/workflows/validate.yml)
[![release](https://img.shields.io/badge/release-latest-1f6feb)](https://github.com/Anasabdellatif/forgeos/releases/latest)
![status: public preview](https://img.shields.io/badge/status-public%20preview-6e7781)
![licence: MIT](https://img.shields.io/badge/licence-MIT-blue)
![platforms: Windows + POSIX](https://img.shields.io/badge/platforms-Windows%20%C2%B7%20POSIX-555)

Coding agents are good at writing code and bad at remembering why. ForgeOS gives them what a
serious codebase already assumes: a durable project memory, write permissions a human opens
deliberately, and validation that has to produce evidence before anything may be called done.
The rules are not advice in a document — where it matters, a machine enforces them.

Current version: **`1.15.30`** · MIT · Windows PowerShell 5.1 and POSIX bash

**[Quick start](#quick-start)** · **[Commands](#commands)** · **[What is
enforced](#what-is-enforced)** · **[Roadmap](#roadmap)** · **[useforgeos.com](https://useforgeos.com)**

## Why ForgeOS

Five things go wrong on long-lived projects driven through coding agents, whichever tool drives
them:

| The pain | The ForgeOS answer |
| --- | --- |
| The agent re-derives the same context every morning, and a decision survives only in a chat log | **Durable project memory** — decisions, lessons, incidents, handoffs, and open questions as files in the repository, plus a one-screen state ledger every session starts from |
| Rules and memory drift between Claude Code, Codex, and whatever comes next | **One operating contract** — a single authoritative rule set in `.ai/contract/`, read by every tool through thin adapters that are checked for duplication |
| Implementation outruns approval — code appears that nobody authorized | **Governance windows** — application paths stay closed until a human opens a named, narrow window for one slice of work |
| "Done" becomes narrative instead of evidence | **Validation gates** — a closure gate refuses unchecked criteria and placeholder evidence; eleven checks run by one command on both platforms and in CI |
| Handoffs between sessions are fragile | **The command center** — `forgeos status` and `forgeos next` read the project's own files and answer *where are we, and what is the next safe thing to do?* |

It is deliberately **not** an app framework, a prompt collection, an autonomous development team,
or a replacement for the coding tool you already use.

## Core ideas

- **Project memory.** `.ai/memory/` holds decisions, lessons, incidents, handoffs, and an
  open-questions register — so nothing important lives only in a conversation. The always-loaded
  context is small and metered (five files, ≈ 3.5k tokens, reported against a recorded budget);
  everything else loads on a named trigger.
- **Governance windows.** A project's `governance.json` keeps application code closed until a
  human authorizes it. A narrow `implementationWindow` opens one slice, not the codebase; the
  refusal names the open window so the agent knows what is and is not in scope.
- **Lifecycle.** Work moves `inbox → active → completed`, and the closure gate refuses a task
  carrying unchecked criteria or placeholder review evidence — with exit `2`, not with a warning.
- **Validation gates.** Every check exists as `.ps1` and `.sh` with identical behaviour, and CI
  fails if the two self-test suites diverge by a single case.
- **The command center.** A read-only engine reports status, a map of the system as it actually
  is, the next safe slice, a draft of the governance window that slice would need, and a copyable
  implementation prompt. It writes nothing and can never authorize code — `canModifyFiles`,
  `canAuthorizeCode`, and `canOpenGovernanceWindow` are all `false`, and a self-test case fails
  if any is not.
- **A portable blueprint.** Adoption copies the portable half — contract, rules, workflows,
  agents, skills, adapters, scripts, templates — while project-owned files are never touched.
  Internal paths keep the engineering name (`blueprint.version`, `sync-blueprint`,
  `blueprint-manifest.json`): adopting projects invoke them by path, so renaming them would be a
  breaking change.
- **Adapters, not forks.** `CLAUDE.md` and `.claude/` serve Claude Code; `AGENTS.md` serves Codex
  and compatible tools. Both are pointers into the same contract, and a policy check fails if a
  rule is restated in an adapter instead of referenced.

## Quick start

Two ways in. Both end at the same place: your project carries the portable half of the blueprint
and passes its own validation suite. There is no `curl`-into-a-shell — this project's own hook
refuses that command shape, and it will not be added.

### 1. From the release artifact (recommended)

Download both files from the [latest release](https://github.com/Anasabdellatif/forgeos/releases/latest)
— for `v1.15.30` that is
[`forgeos-1.15.30.tar.gz`](https://github.com/Anasabdellatif/forgeos/releases/download/v1.15.30/forgeos-1.15.30.tar.gz)
and
[`forgeos-1.15.30.tar.gz.sha256`](https://github.com/Anasabdellatif/forgeos/releases/download/v1.15.30/forgeos-1.15.30.tar.gz.sha256).

POSIX:

```bash
sha256sum -c forgeos-1.15.30.tar.gz.sha256     # verify before you trust it
tar -xzf forgeos-1.15.30.tar.gz

# dry run first — it writes nothing and reports what it would do
bash forgeos-1.15.30/scripts/blueprint/sync-blueprint.sh --source forgeos-1.15.30 --target <project>
# then apply
bash forgeos-1.15.30/scripts/blueprint/sync-blueprint.sh --source forgeos-1.15.30 --target <project> --apply
```

Windows PowerShell:

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

There is also a local `forgeos` command and an installer for each platform — both **Proven** on
the platforms they claim, and neither is required for the routes above. The installers
(`scripts/install/`) are scripts you download, **read**, then run: they fetch nothing, never
change `PATH`, verify a checksum when one sits beside the source, and fail closed on a mismatch.

### 2. From a clone

```bash
git clone https://github.com/Anasabdellatif/forgeos.git my-project   # then make the history yours
cd my-project && rm -rf .git && git init -b main
```

For an existing project, point sync at the clone instead:

```bash
bash scripts/blueprint/sync-blueprint.sh --source <blueprint> --target <project>
bash scripts/blueprint/sync-blueprint.sh --source <blueprint> --target <project> --apply
```

### 3. Then, in either case

```bash
bash scripts/validation/check-all.sh
```

The first run is expected to report unfilled markers: those are the facts your project must
supply. **The adoption step is the product** — an unadopted blueprint gives an agent structure
with no knowledge. Full procedure: [`docs/adoption.md`](docs/adoption.md). Already adopted and
upgrading: [`docs/adoption-upgrade-guide.md`](docs/adoption-upgrade-guide.md).

## Commands

The local `forgeos` command wraps the same engine the scripts expose. Reading commands answer;
writing commands are dry runs until `--apply` is typed; `--force` is never passed and never
exposed.

| `forgeos …` | Purpose |
| --- | --- |
| `status` | Where the project is, read from its own files — `--json` for machines |
| `next` | The next safe slice, the governance window it would need, a validation plan, and a copyable implementation prompt |
| `doctor` | Whether this installation can run: nine prerequisite rows — shell, JSON reader, git, hook wiring, line endings |
| `version` | Which ForgeOS this is; a release is reported unknown rather than inferred from a tag |
| `adopt --target <path>` | Bring the blueprint into a project — dry run first, `--apply` to write |
| `update --target <path>` | Refresh an adopted project; refuses a target that never adopted |

Exit codes are uniform: `0` reported · `1` could not run · `2` refused by a gate.

Inside a project, the work itself runs through workflows the adapters expose as slash commands:

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

Eight roles each own a different question — *what is being asked · what shape should this take ·
what is the smallest complete change · what evidence proves it · is it correct and in scope · what
is the worst reachable outcome · is it safe to reverse · is the evidence enough to ship*. Five
profiles bind a system's kind to the roles and gates it cannot skip.

## What is enforced

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
| `check-public-surface` | **This page** disagrees with what the tools report: a stated version, a check count, a claim the repository contradicts |
| `check-placeholders` | *Informational:* an adoption-readiness score, weighted by impact |
| `check-context-budget` | *Informational:* the always-loaded context against its recorded budget, attributed to its owner |
| `check-state-freshness` | *Informational:* how far the state ledger lags HEAD — and it refuses to answer at all under a shallow clone rather than guess |

Every number on this page is either checked mechanically or printed by a command you can run:

| Claim | How to verify it yourself |
| --- | --- |
| Eleven checks, eight of them gating | `bash scripts/validation/check-all.sh` — the summary names each row and its class |
| 202 self-test cases, identical on both shells | The same run prints the total; CI's parity job compares the two lists case by case |
| 144 policy controls | `bash scripts/validation/check-policy.sh` |
| Every referenced path resolves | `bash scripts/validation/check-links.sh` — 517 references across 134 files, 0 broken, 0 unportable |
| This page agrees with the repository | `bash scripts/validation/check-public-surface.sh --fail-on-drift` |
| Eight CI jobs, green on the pushed commit | `.github/workflows/validate.yml`, and the Actions tab |
| The release artifact is what it claims | `sha256sum -c` against the published `.sha256`, then `tar -tzf` to read it before extracting |

## Safety model

- **Dry run is the default** on every command that writes; `--apply` must be typed, every time.
- **`--force` is never exposed.** It is the flag that would overwrite a file the adopting project
  customized, and a wrapper quietly offering it would undo the guarantee the sync engine exists
  for.
- **Project-owned files are never touched.** `.ai/context/`, tasks, plans, memory, `docs/`,
  `README.md`, and `blueprint.version` belong to the adopting project from the moment they land.
- **Local modifications are detected, not destroyed.** `blueprint.version` records a SHA-256 per
  synced file; a file you edited no longer matches, so it is reported and skipped rather than
  overwritten.
- **Dangerous operations are guarded.** Force pushes, hard resets, recursive force deletes,
  database drops, and remote-script pipes are refused by hooks before they run, with the reason.
  Writes into an undefined project and unauthorized application code are refused with exit `2`.
- **Task closure requires evidence.** The closure gate refuses unchecked criteria and ten
  placeholder shapes, in two languages, identically on both platforms.
- **Hooks are a safety net against accidents, not a security boundary** —
  [`.github/SECURITY.md`](.github/SECURITY.md) says exactly where they stop.

## Platform support

| Environment | Status |
| --- | --- |
| Windows PowerShell 5.1 | **CI on every push** |
| Ubuntu / Linux, bash 4+ with GNU coreutils | **CI on every push**, twice: with `jq` and with it hidden |
| WSL, Git Bash on Windows | Exercised by hand during development. No CI job |
| Stock macOS | **Not proven** — bash 3.2 and BSD utilities; expected to need `brew install bash coreutils findutils` |

POSIX scripts choose their JSON reader by **capability, not presence**: `jq` first, then a
`python3` that can actually parse, then `python`, then a clear fail-closed message. There is no
`npx`, no `brew`, no Scoop or Winget — each deferred on the roadmap with its blocker named — no
Docker image (declared, low priority), and no package-manager channel of any kind yet: the
installers and the archive are the supported routes today.

## Releases

A version tag builds a checksummed `forgeos-<version>.tar.gz` through a workflow that is declared
**source-only**: it never lands in an adopting project, so it can never try to release one. The
published archive carries the portable half and the scaffolding a new project needs — none of this
repository's own answers or release tooling — and the same tag builds a byte-identical archive on
Windows and on POSIX. Verify before use, always:

```bash
sha256sum -c forgeos-1.15.30.tar.gz.sha256
tar -tzf forgeos-1.15.30.tar.gz | head
```

The changelog lives in `blueprint.version`, one prose entry per version;
[`docs/changelog.md`](docs/changelog.md) explains how to read it and where the history starts.

## Roadmap

**Now** — public preview: a clean, verified snapshot, with the trust surface and this page both
checked rather than asserted.
**Next** — driving a real project end to end through the full work loop, and the field reports
that come out of it.
**Later** — the website at [useforgeos.com](https://useforgeos.com), package-manager channels
(each currently deferred with its blocker named), a macOS proof, and a read-only dashboard on top
of the status contract.

Full version, including what is deliberately not being built:
[`docs/roadmap.md`](docs/roadmap.md).

## Status

### Proven

- **Both platforms.** Every gating check passes on Windows PowerShell 5.1 and on POSIX bash.
- **CI.** Eight jobs, green on the latest push — ShellCheck over every tracked shell script, a
  line-ending policy check, a job that fails if the two hook self-tests ever diverge by one case,
  and an install matrix that builds a release artifact, refuses a corrupted one, installs from
  it, and runs the full validation suite inside the project that install created.
- **Adoption, not only self-test.** Real adoptions found defects no check inside this repository
  could see; each is closed and guarded by a permanent case, and the anonymized reports are
  published in [`docs/field-reports.md`](docs/field-reports.md). A freshly synced project passes
  the whole suite on its first run.
- **Release, end to end.** A version tag builds a checksummed artifact and publishes it; the
  published archive was downloaded, verified, synced into a fresh repository, and that project
  passed its own validation suite.
- **The gates are enforced, not stated.** The discovery gate, the governance gate, and the
  closure gate all refuse with exit `2` and are covered by self-test cases on both platforms.

### Not proven

- **The full work loop has never run end to end.** `/start-task → /implement → /review →
  /finish-task` has not been exercised on a single real task from open to close.
- **Three roles have never been dispatched** — `product-analyst`, `data-reviewer`,
  `release-manager`.
- **A task can still under-declare its scope.** The closure gate checks the declared scope tags;
  the declaration is the task's own. Catching a wrong one is `/review`'s job.
- **Discovery has been run through phase 1 only.** Phases 2 to 6 are untested.
- **The gate hooks are Claude Code only.** Codex reads the same rules in `AGENTS.md`, where they
  remain prose.
- **macOS.** Unverified, as above.
- **The token target is unmeasured.** Recorded as an open assumption.
- **The Command Center engine has run on this repository and one adoption only.** Surfaces built
  on its status contract — a dashboard among them — do not exist.

Project-specific context, requirements, architecture, domain, and operations facts must still be
supplied by each adopting project — [`docs/adoption.md`](docs/adoption.md).

## Security, contributing, licence

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
| Readiness review summary | [`docs/public-preview-readiness.md`](docs/public-preview-readiness.md) |
| Changelog | [`docs/changelog.md`](docs/changelog.md) |

MIT — see `LICENSE`. Copy it, adopt it, adapt it, use it commercially; keep the copyright notice.
`LICENSE` is treated as project-specific: sync never copies it into an adopting project, and
`check-structure` never requires one. A project's licence is its own decision, not something a
blueprint should inherit into it.
