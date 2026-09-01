# Validation Scripts

Checks that the blueprint is structurally intact and that an adopting project has actually filled
it in. Available as `.ps1` and `.sh` with identical behavior.

## Scripts

| Script | Verifies | Gating |
| --- | --- | --- |
| `check-all` | Runs everything below and summarizes | — |
| `check-structure` | Every path in `scripts/lib/blueprint-manifest.json` exists and is non-empty; reports undeclared files | yes |
| `check-empty-files` | No empty or whitespace-only `.md`, `.ps1`, `.sh`, `.json`, `.yml`; no UTF-8 BOM in `.sh`, `.json`, `.yml`, `.yaml` | yes |
| `check-policy` | Required `deny` and `ask` rules are present in `.claude/settings.json`; every `.claude/` adapter references `.ai/`; adapters stay thin; `.ai/context/` summaries still point at `docs/`; assumptions and open questions point at the register | yes |
| `check-links` | Every repository path referenced from Markdown resolves, **and** a file that lands in an adopting project references only what lands with it | yes |
| `check-placeholders` | Remaining `TBD` markers, weighted by adoption impact | informational by default |
| `check-context-budget` | The always-loaded context against `policy.contextBudget` in the manifest — split into the platform floor and the project's own files, so an overrun names its owner | informational; `--fail-on-over` opts in |
| `check-state-freshness` | How far the state ledger lags HEAD — the persistence gate's advisory meter (`reporting.md` §0). Never fails, and never guesses: no ledger, or a history too shallow to measure, is reported rather than passed | informational, always |
| `check-public-surface` | The blueprint's own public launch page against what the tools report — the stated version, the check-row counts, the proof sections, every numeric claim the tools measure -- self-test cases, policy controls, link counts -- handed to it by `check-all` through `--measured`, whether every public trust file is DECLARED source-only rather than staying home by accident, and whether any could reach an adopting project. Audits the source repository only; an adopted project is reported as not applicable | **yes** — `check-all` runs it with `--fail-on-drift` |
| `check-selftest-parity` | The two hook self-tests ran the same cases, in the same order. CI only; it compares their published output | yes, in CI |

`scripts/hooks/selftest` is also run by `check-all` as a gating check: **202 cases** covering
`guard-bash`, `scan-secrets`, `guard-discovery`, `guard-governance`, the discovery gate on `new-task`, the closure
record written by `finish-task`, profile role evidence, the public-surface audit, and the adoption and context tooling --
`sync-blueprint` and `build-context` -- identical in both shells.

The last group exists because those two scripts were breakable in silence. `build-context.ps1` had
never run on Windows PowerShell 5.1 since v1.0.0, and `sync-blueprint` handed every new project the
blueprint's own identity including `Profile: none`, which disables the profile role evidence
`finish-task` enforces. Neither defect was reachable by any check: `check-all` never invoked either
script. Nine cases now do, and re-planting both defects in a throwaway copy fails four cases and
one case respectively. Cost: about three seconds on Windows, two on POSIX. Two more cases guard
the same trap for `constraints.md` since v1.12.1, when the blueprint filled in its own real
constraints: the seeded copy must match `templates/constraints-template.md` byte for byte and
must never carry the blueprint's answers.

Six of the sync cases replay a defect a real adoption found in v1.11.2: a customized file was
skipped as locally modified, correctly, and then its *customized* hash was recorded as if the tool
had written it — so the next sync saw record and target agree, classified the file as a plain
upgrade, and overwrote the customization in silence. The cases adopt a throwaway copy, customize
`.editorconfig`, sync twice more with upstream moving on, and assert that the recorded hash never
changes, the file stays `locally modified` instead of `updated`, the edit survives, and only
`-Force` writes the source and records the source hash. Re-planting the old recording block fails
three of them, on both shells. Cost: about five seconds on Windows and about fifteen on POSIX
through WSL's `/mnt/c`, where the repository copy the cases make dominates.

Six further cases cover `check-context-budget`, against the same throwaway copy. The meter
splits the always-loaded set into the platform floor — `CLAUDE.md` + `core.md`, the blueprint's
to fix — and the project files, whose allowance is the target minus the measured floor. One
budget, blind to the split, was unfair by construction: the floor consumes ~59% of the target,
so a large project was told to trim files that were not the problem. The cases assert the
subtotals are reported, a fixture within its allowance is OK, a project-caused overrun says
PROJECT OVER, a target below the floor itself says PLATFORM OVER without blaming the project,
`--fail-on-over` turns an OVER into exit 1, and a missing manifest fails closed rather than
reporting a clean result it did not compute.

Three more pin `build-context` to UTF-8, on both shells. Windows PowerShell 5.1 reads a BOM-less
UTF-8 file as CP1252 unless told the encoding, so until v1.12.2 a package left an em-dash as
three characters and Arabic as ruins — valid UTF-8 bytes, wrong text, found by a real adoption's
measurement. The cases build a fixture carrying an em-dash, a section sign, Arabic, and accented
French, package it, and assert every character survives, no mojibake signature appears, and the
package carries no BOM.

Five cover `check-state-freshness`: it reports this repository's ledger, and a copy with the
ledger deleted reports the absence as a NOTE with exit 0 — the meter advises the persistence
gate, it never blocks an old adoption that has no ledger yet. The other three build a real
two-commit fixture and then a depth-1 clone of it: a ledger written by the latest commit
reports OK, a ledger one commit behind reports a NOTE, and **a shallow clone refuses to
claim OK at all**. `git log -1 -- <ledger>` walks only the commits that were fetched, so
under a truncated history it returns HEAD for any ledger — which is how CI reported
"updated by the latest commit" on every push while running at `fetch-depth: 1` (fixed in
v1.15.1: the checker says what it cannot measure, and the jobs that run `check-all` fetch
full history so the answer stays useful).

Three pin `../../` normalisation in `check-links`, on both shells. POSIX collapsed
`docs/architecture/../../x` to `docs/x` — `${out%/*}` cannot strip a segment with no slash
left — so a valid reference was reported broken while PowerShell resolved it fine; found by a
real adoption, fixed in v1.13.1. The cases prove a parent-parent reference resolves, a single
parent still resolves, and a genuinely broken parent-parent reference still fails.

Three prove a fresh adoption is complete enough to validate, since v1.13.2. `.gitattributes` was
the one policy file sync did not distribute: an adopter received the CI job that enforces line
endings and the LF-dependent shell scripts, but not the policy either one assumes. The cases
assert both policy files arrive byte-identical to the source and the identity files come from
`templates/`, never from this repository's filled copies.

**That parity is enforced since v1.10.4.** No single CI job can run both scripts — the Windows
job runs the `.ps1` and the Ubuntu jobs run the `.sh`, and neither host can run the other half:
Git Bash on Windows keeps its fixtures under a POSIX `/tmp` that native Windows tools cannot
open, and Windows PowerShell is absent from a Linux runner. So each suite publishes its printed
case list as an artifact and a sixth job, `selftest-parity`, diffs the two. It fails on a
different count, a different order, or a single label present on one side only — and refuses to
judge parity at all if either suite reported a failing case.

**The first run of that job failed, and the reason is now part of the design.** Windows
PowerShell 5.1 writes UTF-16LE when output is redirected with `>`, so the Windows case list
arrived complete -- sixty cases, eleven kilobytes -- and read as zero, because a POSIX `grep`
sees a NUL after every character. The capture step now uses `Out-File -Encoding utf8`, and the
comparator normalises what it is given before reading it: NULs and carriage returns stripped,
a leading UTF-8 BOM removed. Both halves, because fixing only the producer would leave the
next producer free to make the same mistake.

It had already drifted: from v1.0.0 to v1.8.2 the POSIX file claimed parity while carrying 33
cases, missing the remote-pipe block. Likely cause: typing that command into a shell to check it
trips `guard-bash` itself, so the case is awkward to verify by hand. Closed in v1.8.3 by comparing
the printed labels of both runs, line for line, and automated in v1.10.4 so it cannot drift again.

## Why `check-policy` exists

Immutable-archive and secret-file protection moved out of a hook into `deny` rules because
permissions are enforced by the harness at zero cost and cannot fail open. But a control that
leaves a tested hook must not become an untested control. `check-policy` re-tests it where it
now lives.

It also enforces the one constraint the whole design rests on: **`.claude/` is an adapter, not a
home for rules.** Every adapter file must reference `.ai/`. Without this check that constraint was
documentation only — and documentation does not stop a contributor from writing a rule in the
wrong place.

**Referencing `.ai/` alone proved insufficient.** Before v1.2.0 every agent and skill adapter cited
its source *and* restated it in different words — 1.6x to 2.1x the size of the file it pointed at,
with zero literal duplicate lines, so no diff could reveal it. `check-policy` passed all 38 of its
controls while blind to the fact. So `agents/` and `skills/` adapters now also face:

Limits are **per surface**, because the surfaces differ: a role adapter needs only a pointer, while
a slash command legitimately carries the concrete invocations for two shells.

### The entrypoints are a surface too

`CLAUDE.md` and `AGENTS.md` are the only files an agent is guaranteed to read. That makes them the
most tempting place to restate a rule *for salience*, and the least visible place for that copy to
drift.

It had already happened, and nothing caught it. `AGENTS.md` carried a section headed
*Non-Negotiables (restated for salience)* listing **7 of the 8** rules from `core.md` section 3 —
and rule 8, *never expand scope silently*, had gone missing from the copy. Exactly the defect fixed
in `.claude/agents/` and `.claude/commands/` two versions earlier, sitting in the two files that
matter most, because the guard covered directories and these are root files.

v1.8.2 removed the restatements and added four controls per entrypoint, declared in
`policy.entrypoints`:

| Control | Fails when |
| --- | --- |
| Length | The file exceeds 40 lines. Derived, not chosen: after the rewrite `CLAUDE.md` is 31 and `AGENTS.md` 37 |
| Points at the contract | The file does not reference `.ai/contract/core.md` |
| No rules section | A forbidden heading appears — `## Non-Negotiables`, `## Engineering Rules`, `## Rules`, `## Lifecycle`, `## Safety`, and eight more |
| No restated rules | A line matches `^[0-9]+\.[ \t]+Never[ \t]` — the exact shape of the non-negotiable list |

The pattern is spelled `[ \t]` rather than `\s` so .NET regex and POSIX ERE agree, which is the
same lesson `check-placeholders` learned from `[a-z]` versus `[A-Za-z]`.

Proven by planting each violation in a throwaway copy and asserting the exit code — seven cases,
identical results on both platforms. The isolating case matters most: a single numbered `Never`
line, with no forbidden heading and no length breach, still fails.

| Surface | Max lines | Why that number | Forbidden headings |
| --- | --- | --- | --- |
| `agents/` `skills/` | **20** | Double the 10 observed after the v1.2.0 rewrite | `## Method` `## Review Order` `## Severity` `## Boundaries` `## Output` `## Constraints` `## Preconditions` `## Never` `## Rules` `## Finish with` `## Responsibilities` `## Required Inputs` `## Context to Load` |
| `commands/` | **35** | Observed max 21 after the v1.2.1 rewrite; two shell invocations plus an argument hint need the room | `## Do this` `## Rules` `## Hard rules` `## Hard rule` `## Steps` `## Method` `## Stop conditions` `## Review Order` `## Severity` `## Boundaries` `## Constraints` `## Preconditions` `## When to Use` |

For commands the **heading rule is what bites**, not the length: all ten now carry zero `##`
headings. A command that needs sections is restating a procedure that belongs in `.ai/workflows/`.

The limits live in `scripts/lib/blueprint-manifest.json` under `policy.adapter.thin`, as a list of
per-surface groups. Raising one to make a file pass is the failure mode this check exists to
catch — move the content to `.ai/` instead.

## The discovery gate, enforced

`.ai/contract/core.md` section 0 forbids writing code into an undefined project. Until v1.8.0 that
was prose, and prose does not stop a write. Nothing in `.claude/settings.json` referenced it, and
`check-placeholders` exits `0` by default — so the rule the whole design rests on was the one rule
with no enforcement anywhere.

`scripts/hooks/guard-discovery` is a `PreToolUse` hook on `Write`, `Edit`, and `NotebookEdit`. It
exits `2` when the target path is outside the allowlist **and** any `blocking` placeholder target
still carries a marker.

| | Paths |
| --- | --- |
| **Allowed while undefined** | `.ai/` `docs/` `.claude/` `scripts/` `templates/` `examples/` `.github/`, plus `CLAUDE.md` `AGENTS.md` `README.md` `LICENSE` `.gitignore` `.gitattributes` `.editorconfig` `blueprint.version` |
| **Blocked while undefined** | Everything else — where source, manifests, migrations, and scaffolding land |

The allowlist is deliberately generous about the blueprint's own surfaces: a maintainer must never
be locked out of the blueprint by the blueprint, and adoption legitimately edits `scripts/hooks/`
and `.claude/settings.json` before discovery finishes.

**What counts as undefined has one home.** The hook reads `placeholderScan` from the manifest and
takes the targets weighted `blocking` — the same data `check-placeholders` uses. It counts only the
word markers, not the bracketed prompts: `.ai/context/` is written entirely in the `TBD:` style, so
markers alone answer the question, and duplicating the bracket regex would create a second home for
the trickiest pattern in the repository.

**It fails open when the manifest cannot be read**, and that is deliberate. `_json.sh` states the
principle: a hook is a safety net, not a security boundary. A hook that blocks every write on a
machine with no JSON parser is a hook that gets switched off, and a disabled hook enforces nothing.
The fail-**closed** half of this control is `check-placeholders --fail-on-blocking`, which since
v1.7.2 refuses to report a clean result it did not compute. Hook for the moment of the mistake,
validation for the gate that cannot be talked around.

`--fail-on-blocking` / `-FailOnBlocking` already existed; v1.8.0 added no new option.

**Wiring is now asserted by name.** `policy.requiredHooks` only checked that an event was declared —
a settings file could list `PreToolUse` and reference no guard at all. `policy.requiredHookScripts`
names `guard-bash`, `guard-discovery`, and `scan-secrets`, and `check-policy` fails when the
settings file does not reference one.

Seven self-test cases cover it, all against **throwaway fixture projects** rather than this
repository. Testing against the host repo would tie the expected exit codes to whether the
blueprint's own context happens to be filled — so filling it later would silently invert them.

## Why the BOM check exists

A UTF-8 BOM in `blueprint.version` broke `check-all.sh` while `check-all.ps1` kept passing — the
cross-platform divergence this blueprint exists to prevent. The breakage is measured, not assumed:

| Type | With a BOM |
| --- | --- |
| `.sh` | **Does not run.** `bom.sh: line 1: <BOM>#!/usr/bin/env: No such file or directory` — and `bash -n` passes it silently, so the syntax gate cannot catch this class |
| `.json` | `python3 json.load` raises `Unexpected UTF-8 BOM`. `jq` tolerates it, so a host with `jq` passes and a host without it fails |
| `.yml` / `.yaml` | PyYAML tolerated it in testing. Checked anyway — machine-parsed configuration, and other consumers may differ |
| `.md`, `.ps1` | **Deliberately not checked.** Harmless there, and a check that fails on harmless input is a check that gets disabled |

Only the first three bytes of each candidate file are read. The report names the path and never
prints content.

## Continuous integration

`.github/workflows/validate.yml` runs the **same aggregate entry points** as a developer does —
`check-all.ps1` and `check-all.sh` — not the individual checks. Running them separately would let a
gating check be added locally and silently never run in CI, which is how `check-blueprint-version`
came to be missing from CI between v1.1.2 and v1.6.0.

| Job | Runs on | Proves |
| --- | --- | --- |
| `windows` | `windows-latest` | `check-all.ps1` under Windows PowerShell 5.1, plus a parse of every `.ps1` |
| `posix-jq` | `ubuntu-latest` | `check-all.sh` with **jq present** |
| `posix-python3` | `ubuntu-latest` | `check-all.sh` with **jq hidden**, plus `bash -n` on every `.sh` |
| `shellcheck` | `ubuntu-latest` | Static analysis of every shell script |
| `line-endings` | `ubuntu-latest` | The committed tree already matches `.gitattributes` |

### Why the POSIX suite runs twice

The `.sh` scripts read JSON through **jq or python3**. The development machine has no jq, so only
the python3 branch had ever executed. One job installs jq and one hides it, so both branches are
proven rather than assumed.

### Why `git diff --check` is not in CI

After a fresh checkout there is no working-tree diff, so `git diff --check` compares nothing and
always passes. It would be a green step that proves nothing.

The `line-endings` job asks the question that actually matters: run `git add --renormalize .` and
fail if anything changes. A change means a file was committed with endings `.gitattributes`
forbids — which is precisely what breaks a `.sh` script on POSIX, and which `bash -n` does not
catch.

### One dependency, deliberately

Only `actions/checkout` is used. A third-party secret-scanning action was removed in v1.6.0: it
required passing a token to code this repository does not control, and gitleaks-action needs a paid
licence under an organization account — a CI failure unrelated to the blueprint, which is how a
team learns to ignore CI. v1.6.1 replaced it with a first-party check.

## Secret scanning

`scripts/hooks/scan-secrets` gained a third mode, `--scan-tree` / `-ScanTree`, which scans every
**git-tracked** file and exits 1 on findings.

**Why a mode and not a new script:** the hook already owns ten patterns, a placeholder allowlist,
a skip list, a size cap, and an extension filter. Copying them into `scripts/validation/` would
create a second home for the one fact that matters most, which is the failure this repository has
spent six phases eliminating. The patterns live in one place and three modes share them.

**Why the existing hook modes could not simply be reused in CI:** Stop mode scans what
`git status` reports as changed. A fresh CI checkout has changed nothing, so it would scan **zero
files and pass**. A security check that passes because it examined nothing is worse than no check.

| Pattern | | Pattern | |
| --- | --- | --- | --- |
| Private key block | `-----BEGIN … PRIVATE KEY-----` | Stripe secret key | `sk_live_…` `sk_test_…` |
| AWS access key id | `AKIA…` `ASIA…` | JSON Web Token | `ey….….…` |
| AWS secret access key | assigned, 20+ chars | Generic assigned secret | `api_key`/`secret`/`password`/`token` = quoted 12+ |
| GitHub token | `ghp_` `gho_` `ghu_` `ghs_` `ghr_` | Database URL with password | `postgres://user:pass@…` |
| Slack token | `xoxb-` `xoxa-` … | Google API key | `AIza…` |

**It never prints the value.** Output is the file path, the line number, and the pattern name.
Verified by planting five syntactically valid canaries in a throwaway repository and asserting that
none of their values appears anywhere in the output.

**Allowlist**, deliberately narrow: conventional placeholders (`your-api-key-goes-here`,
`${VAR}`, `<token>`, `changeme`, `example`, `TBD`, and similar), plus four paths that contain
secret-shaped text by design — `scripts/hooks/`, `scripts/validation/`, `.ai/rules/security.md`,
`.ai/rules/ai-safety.md`, and `examples/`.

**In CI it is not a separate job.** `check-all` runs it, and CI runs `check-all` — which is exactly
why CI was rewired that way in v1.6.0: a new gating check reaches CI without anyone remembering to
add it.

## Line endings

`.gitattributes` pins them, because `core.autocrlf` is commonly `true` on Windows and would
otherwise rewrite LF to CRLF on checkout for every text file:

| Type | Ending | Reason |
| --- | --- | --- |
| `.sh` `.md` `.json` `.yml` `.yaml` `.version` `.gitkeep` | **LF** | A CRLF in a `.sh` file breaks it on POSIX — and `bash -n` passes it silently, exactly like the BOM case |
| `.ps1` `.psm1` `.psd1` `.bat` `.cmd` | **CRLF** | Windows-executed |

The policy agrees with `.editorconfig` at every overlapping point. **If you change one, change the
other in the same commit** — two files describing the same rule is the drift setup this repository
otherwise works to avoid.

No validation script asserts line endings today; `git check-attr` and `git ls-files --eol` are the
tools for it. Adding an automated check is a candidate for a later phase.

## Source-of-truth guards

v1.3.1 made `docs/` the source of truth for project facts and reduced `.ai/context/` to linked
summaries. v1.3.2 stopped that from being documentation alone.

**Why:** every rule this repository left to documentation has broken — adapter discipline,
command adapters, the `finish-task` gate count. Three for three.

| Guard | Fails when |
| --- | --- |
| **Summaries still summarize** | A file in `.ai/context/` stops containing `docs/`, or a section title that `docs/` owns reappears in it — `Target Users`, `Data Architecture`, `Module Boundaries`, and nine more |
| **Open questions reach the register** | A file under `.ai/contract/`, `.ai/workflows/`, `.ai/agents/`, `.ai/skills/`, `.ai/rules/`, `.ai/context/`, or `.claude/` writes `undecided:`, `assumption:`, or `open question:` without pointing at `.ai/memory/open-questions.md` |
| **Roles pair with adapters** | A file in `.ai/agents/` has no `.claude/agents/` counterpart (the role cannot be dispatched), or an adapter has no source (it is a second knowledge source by definition) |
| **Profiles stay selectors** | A profile names a role absent from `.ai/agents/`, declares no roles in frontmatter, or never points at `docs/` |

Profiles declare their roles in **frontmatter**, not prose:

```yaml
requiredRoles: [product-analyst, architect, implementer, tester, reviewer]
optionalRoles: [data-reviewer]
```

That is deliberate. A regex over prose would have to guess which backticked word is a role name,
and a guessing check produces false positives — which is how a check gets disabled.

**Both are deliberately dumb.** They check that a pointer is present and that a known-duplicated
heading has not come back. Neither can detect a paraphrase, and neither is meant to — a guard that
tries to be clever produces false positives, and a check that cries wolf gets disabled.

`templates/` and `examples/` are not scanned: they exist to show the shape of a record, not to
instruct. `.ai/memory/decisions/` is not scanned either — an ADR is a historical record, and
rewriting one to satisfy a check would violate the rule that historical rationale is never
silently edited.

## Two placeholder conventions, one score

The templates use both `TBD:` and bracketed prompts — `[modular monolith / microservices]`,
`[requirements and approach]`, `[stores]`. `check-placeholders` counts both.

Before v1.3.0 it counted only `TBD`. `docs/architecture/overview.md` is written **entirely** in the
bracket style — 59 placeholders, zero `TBD` — so the readiness report said `docs/architecture` had
4 markers, all of them from `decisions.md`, while the single most important architecture document
sat completely unfilled and unmeasured. The score was not incomplete; it was **misleading**. An
adopter could fill four table rows and see that area report ready.

| | Before | After |
| --- | --- | --- |
| `docs/architecture` | 4 | **63** |
| Total | 158 | **219** |

Fenced code blocks are skipped, so `array[index]` in a sample is not mistaken for a gap. Markdown
links are excluded.

**The pattern is written `[A-Za-z]`, never `[a-z]`.** PowerShell's `-match` is case-insensitive by
default and `grep -E` is case-sensitive, so `[a-z]` matched `[Component Name]` on Windows and
skipped it on POSIX — the two platforms disagreed by 10 lines from one pattern that inherited its
behavior from the engine instead of stating it. Spell the intent.

## A marker in backticks is a mention, not a gap

`check-placeholders` ignores `TBD`, `TODO`, and `FIXME` when they appear **inside backticks**. A
documentation sentence such as *"While any `TBD` remains here, the discovery gate is closed"*
describes the rule; it is not an unfilled field. Counting it kept the discovery gate closed on a
fully defined project — and in one real adoption that accidental closure was the only thing
holding code back, because the real reason (open governance gates) had no enforcement yet. Both
halves are now fixed: the mention is no longer counted, and `guard-governance` holds the line on
its own merits. Fenced code blocks were already skipped; inline code spans now are too, on both
platforms, with identical counts.

**The enforcer no longer follows the same rules — it asks the same tool.** `guard-discovery` used to
count markers itself. Copying `check-placeholders`' three rules kept the two close for a while and
then failed anyway: the checker also treats bracketed prompts like `[the project name]` as
placeholders, and the hook only ever counted word markers. A project whose context was written
entirely in bracket style opened the discovery gate while the checker still called it blocking —
measured at exit `0` against 3 blocking.

Since v1.15.10 the hook runs the **project's own** `check-placeholders --fail-on-blocking` and takes
its verdict, so there is exactly one place where *undefined* is defined and no second grammar to
drift. It resolves the checker from the project under audit, not from this repository, because
`check-placeholders` derives its scan root from its own location. It **fails closed** when that
checker is missing or answers without a count: a gate that cannot see is not a gate. The cost is
paid only on the refused path — every permitted prefix returns before it — so writing a document
never invokes it. Self-tests on both shells assert that a bracket-style context refuses code and
still permits docs.

The POSIX scan also stopped handing its regexes to `awk`. `mawk` — the default `awk` on Debian and
Ubuntu, so on every `ubuntu-latest` runner — supports neither `\b` nor the `{4,}` interval the
bracket pattern needs, and a pattern it cannot parse **matches nothing**: measured, 59 bracket
placeholders in `docs/architecture/overview.md` under `grep -E`, 1 under `mawk`. That would have
read a fully unfilled project as ready. `awk` now only strips fences and code spans; `grep -E` does
the matching.

## `check-links` at scale

The first POSIX version spawned three to five processes per markdown *line* — a `grep`, a `sed`,
a `tr`, a `grep` per ignore pattern, and a `cd`/`dirname`/`basename` per reference. Invisible on
this repository; on a real adopting project with ninety thousand markdown lines it took twenty
minutes, which is a correct answer nobody waits for, which is a check that gets skipped.

Extraction is now one `awk` pass per **file**, and every per-reference decision is a bash builtin:
`case`/glob for the path shape and prefixes, a pure-string path normaliser instead of `cd`/`pwd`,
`[[ =~ ]]` for the handful of ignore patterns. Nothing forks inside the loop.

| Corpus | Before | After |
| --- | --- | --- |
| This repository (449 references) | ~3 s | ~1 s |
| 38,000-line fixture (18,449 references) | **469 s** | **19 s** |

Same reference count, same broken and unportable verdicts on the repository and on planted
violations — measured before and after, not assumed.
## Why `check-links` exists

A reference to a file that does not exist sends an agent somewhere empty and costs a whole turn to
discover. It is the most common form of documentation rot and entirely mechanical to catch.

Only references containing a path separator are checked. A bare `core.md` in prose is shorthand
inside an established context, not a claim about location; checking it would produce noise instead
of findings.

## Usage

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1 -Strict
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-placeholders.ps1 -Detailed
```

```bash
bash scripts/validation/check-all.sh
bash scripts/validation/check-all.sh --strict
bash scripts/validation/check-placeholders.sh --detailed
```

`--strict` / `-Strict` also fails on blocking placeholders. Use it in CI **once the project is
adopted**; a fresh blueprint is expected to report them.

## The manifest

`check-structure` reads its required-path list from `scripts/lib/blueprint-manifest.json` rather
than hardcoding it. That list is data, declared once, shared by both platforms.

**When you add a required file, add its path to the manifest.** `check-structure` also reports
files that exist but are undeclared, so drift is visible in both directions — **on both platforms
since v1.15.10**. The PowerShell half had done this since it was written and the POSIX half never
had, so a POSIX-only run could not see an orphan at all. Both now scan the same roots with the same
extensions and exclusions, print the same block, and carry the count in the summary line. It stays
**reported, not gating**, on both: Windows never failed on an undeclared file either, and gating on
one platform only would trade a parity gap for a worse one.

`check-placeholders` reads its scan targets and their weights from the same manifest.

### Every manifest reader fails closed

A validation that passes because it examined nothing is worse than no validation: it is a false
all-clear. Three checks used to produce exactly that.

Each `.sh` reader runs inside a command or process substitution, so its `exit 1` ends that subshell
and nothing else. An unread manifest therefore left empty arrays, and the scripts reported success
over zero inputs. Measured on a shell with no `jq` and a `python3` that is a stub rather than an
interpreter — Git Bash on Windows, and minimal containers:

| Check | Before v1.7.x | Now |
| --- | --- | --- |
| `check-structure` | `passed (0 paths verified)`, exit `0` | exit `1` |
| `check-placeholders` | **`This project is fully adopted.`**, exit `0` | exit `1` |
| `check-links` | `passed (0 references checked)`, exit `0` | exit `1` |
| `check-policy` · `check-blueprint-version` · `sync-blueprint` | exit `1`, blaming the wrong file | exit `1`, naming the manifest |

All of them now emit the same sentence: `Cannot read blueprint manifest. Install jq or python3.`

The `check-placeholders` case was the dangerous one. Its answer is what the discovery gate in
`.ai/contract/core.md` section 0 consults, so a false clean opened the gate on an undefined
project — the single failure the gate exists to prevent.

The PowerShell variants were checked for the same pattern rather than assumed safe. `$ErrorActionPreference = 'Stop'`
already made a missing or unparseable manifest fatal, but a manifest that is **valid JSON with the
keys missing** slipped through: `check-structure.ps1` and `check-placeholders.ps1` reported a clean
result over zero inputs. Both now verify the data before trusting a clean answer. Six scripts times
three failure modes, eighteen cases, all failing closed.

## Why `check-placeholders` exists

`check-structure` proves a file exists. It cannot prove the file says anything. A blueprint whose
context files are entirely `TBD:` passes every structural check while telling an agent nothing —
and every task then starts blind. This check turns that gap into a visible readiness score.

Weights reflect real cost: `blocking` markers sit in always-loaded context, so one unfilled marker
there degrades **every** future task.

## Rules

- Report failures that are actionable: the exact path, and what is wrong with it.
- Return a non-zero exit code when a gating check fails. Never soften a check to make the tree look
  clean.
- Distinguish "not ready" (`2`) from "error" (`1`).
- Keep `check-placeholders` informational by default. A blueprint that fails out of the box teaches
  people to ignore the validator.

## Requirements

The `.sh` variants need `jq` **or** `python3` to read the manifest. Both are present on every CI
image and most developer machines. The `.ps1` variants have no external requirement.
