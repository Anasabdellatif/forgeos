# Project Command Center — Contract

**What it answers:** *where is this project, and what is the next safe thing to do?*

The rest of ForgeOS answers *may this happen* and *did it actually work*. Those are enforcement
questions, and the gates answer them well. This directory answers the question a person asks at the
**start** of a session, from the repository's own files rather than from anyone's recollection.

**Status: read-only, and now answering both halves of the question.** `project-status` reports where
the project is — the map — and what the next safe thing to do is: the recommendation, the governance
window that slice would need as a draft, the validation plan it would have to pass, and a
copy-paste implementation prompt assembled from those three.

It is still read-only. Everything it produces is a suggestion a person acts on. It opens no window,
authorizes nothing, and writes nothing, including the drafts it prints.

This file is portable: it travels into every adopting project, so it names no path that does not
travel with it. A project's own roadmap and decision records are its own, and this page does not
link to them.

## The safety boundary, first

These are properties of the design, not options, and the self-test asserts each one:

| Boundary | Meaning |
| --- | --- |
| **No writes** | The command creates, modifies and deletes nothing. Its own output goes to stdout |
| **No authorization** | It never opens a governance window. It may *draft* the window a slice needs; a person opens it |
| **No destructive actions** | It runs no `git` command that changes state, and no package, network or filesystem mutation |
| **No hidden network calls** | It reads local files and local `git` metadata only. Anything requiring the network is reported `unknown`, never fetched |

The JSON carries these as explicit fields — `canModifyFiles`, `canAuthorizeCode`,
`canOpenGovernanceWindow` — all `false`. They are asserted, not decorative: a future version that
gained a write path would have to change them, and a self-test case fails if any is not `false`.

## Commands

| Command | Purpose | Status |
| --- | --- | --- |
| `forgeos` | The local command surface: `status`, `next`, `prompt`, `doctor`, `version`, `adopt`, `update` | **implemented** — complete |
| `project-status` | Report where the project is, from files | **implemented** |
| `project-map` | The system as it is: ten documentation and state surfaces | **implemented**, inside `project-status` as the `map` object |
| `next-slice` | The next incomplete capability, and whether anything blocks it | **implemented**, as `nextRecommendation` |
| `governance-window` | Draft the window that slice would need | **implemented**, as `governanceDraft` — a draft only |
| `validation-plan` | What must pass before that slice is done | **implemented**, as `validationPlan` |
| `implementation-prompt` | A copy-paste prompt generated from repository state | **implemented**, as `generatedPrompt` |
| `session-package` | Everything a coordinator would be asked for the next session: session, model, effort, scope, policy, reading order, report shape, and a paste-ready prompt | **implemented**, as `forgeos prompt` / `--section prompt` |

All seven are one command today. They are named separately because they answer separate questions and
may become separate entry points; splitting them later changes no field.

## The `forgeos` command

`forgeos` is the surface a person types, and it splits along one line: **a command about the
project routes; a command about the installation does not.**

`status`, `next` and `prompt` describe the **project**, so they route to `project-status` and add nothing —
the reading, the schema and the safety flags stay in one place. A wrapper that reformatted would be
a second answer waiting to disagree with the first, and a self-test case asserts each routed command
is byte-identical to the engine it routes to.

`doctor` and `version` describe the **installation**, so they are implemented in the wrapper. Neither
duplicates the engine, and neither could sensibly route to a command that may itself be the missing
piece: a version command that could not answer because `project-status` was absent would be a poor
version command, and the doctor fixture proves that case is real.

`adopt` and `update` act on **another** project, so they delegate to `sync-blueprint` — the one place
the copy rules live — and share a single delegation block between them. They are the only commands
here that can write, and only when `--apply` is typed.

```bash
bash scripts/command/forgeos.sh status            # where this project is
bash scripts/command/forgeos.sh next --json       # what to do next, machine-readable
bash scripts/command/forgeos.sh prompt            # the complete next-session package
bash scripts/command/forgeos.sh doctor            # whether this installation can run
bash scripts/command/forgeos.sh version           # which ForgeOS this is
bash scripts/command/forgeos.sh adopt  --target <path>   # first-time adoption   (dry run)
bash scripts/command/forgeos.sh update --target <path>   # refresh an adopter    (dry run)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/forgeos.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/forgeos.ps1 next -Json
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/forgeos.ps1 doctor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/forgeos.ps1 version -Json
```

**It lives beside what it wraps, and it is not on your PATH.** Putting it in `scripts/command/`
keeps one contract page for the whole surface, and this directory is portable so adopting projects
receive it. Installing a `forgeos` executable *onto* a PATH is a separate concern — which channel,
which checksum, which uninstall — and belongs to the installability work, not here.

## Modes

```bash
bash scripts/command/project-status.sh                    # human-readable, to stdout
bash scripts/command/project-status.sh --json             # JSON only, to stdout
bash scripts/command/project-status.sh --section next     # the recommendation half alone
bash scripts/command/project-status.sh --section prompt   # the complete next-session package
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1 -Json
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1 -Section next
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/command/project-status.ps1 -Section prompt
```

`--section next` exists so the wrapper can ask for a subset instead of re-parsing this command's
output. One emitter, one place. The subset carries its **own** schema id,
`forgeos.project-next/1`, because it is a different document: a consumer that trusted
`forgeos.project-status/1` and then found half the keys missing would be right to complain.

`--section prompt` builds the **session package** on top of the same facts: the recommendation, a
same-or-new-session decision read from the work in flight, a session name, the model and effort the
policy table recommends (`scripts/lib/session-policy.json` — a data file, first matching category
wins, the last entry is the default; edit it to name your own tools), the governance verdict, an
allowed/forbidden scope read from the governance file, a commit/push/tag/deploy policy in which
push, tag and deploy can only ever say *refused* or *ask the owner* and commit says *allowed,
local only* solely while the governance gate is open, a reading order of files that exist, the
final-report
checklist, and a paste-ready prompt carrying all of it. Its subset schema is
`forgeos.project-prompt/1`. It is the one section that can refuse: when the roadmap names no
incomplete row, or the ledger, governance file, or policy table is missing, it exits 1 and names
each missing source and the way to supply it — a package with invented facts would be worse than
no package.

**`--json` puts JSON on stdout and nothing else.** Any human commentary goes to stderr. A caller
that pipes stdout into a parser must never have to strip a banner first — the rule the packaging
decision set for every future machine-readable surface.

## Exit codes

The house convention, unchanged: **`0`** reported · **`1`** could not run · **`2`** refused by a gate.

`forgeos` follows it exactly, and that decides one question worth stating plainly: **a blocked or
undefined project is still a `0`.** The report succeeded; the news it carries is bad. `1` covers a
usage error — an unknown command, an unknown option, no command at all — and a prerequisite so
missing that nothing could run. **`2` is never emitted by any command here**, because none of them
is a gate; it stays reserved so that a caller checking for it is checking for something real.

`doctor` is the sharpest case: it exits `0` even when it finds a required prerequisite missing.
Reporting a problem is not the same as failing to report, and the verdict lives in `ready` and in
the row that names what it expected.

`project-status` returns `0` even when the project is undefined, blocked, or missing sources. A
status report that fails because the news is bad is a status report nobody runs. It returns `1` only
when it cannot read the repository at all.

## What it reads

Every field is derived from one of these, and from nothing else:

| Source | Contributes |
| --- | --- |
| `git` (read-only: `rev-parse`, `tag`, `remote`) | branch, commit, repository name, tag summary |
| `blueprint.version` | blueprint version and role |
| `.ai/context/current-state.md` | the Now / Next / Blocked-by lines |
| `.ai/tasks/` and `.ai/plans/` | counts by lifecycle folder |
| `.ai/memory/open-questions.md` | open and answered counts |
| the project's roadmap page, when it has one | the next recommended phase, and the three maturity tracks |

## What it must never invent

**A missing source is reported as missing.** No default, no estimate, no last-known value.

- A string field with no source is `"unknown"`.
- A numeric field with no source is `null` — never `0`, because zero tasks and no task directory
  are different facts.
- Every missing source is named in `missingSources`, so the gap is visible rather than implied.

This is the same standard the public page is held to: a number on a report must come from something
a reader can open.

## How percentages are computed

Percentages are **read, not calculated, and never estimated**. The live figures come from a track
table on the project's own roadmap page; the decision that set the bar defines the *method* —
**criteria met ÷ criteria declared**, against a list fixed before the work starts — and is dated
history, not a tracker. Reading the live table rather than the decision is deliberate: raising a
track must never require editing a dated record of what was decided.

If that page is absent — as it is in every adopting project, since a project's `docs/` is its own
and is never synced — all three tracks are `null` and the source is listed as missing. A percentage
this command cannot trace to a file is a percentage it does not print.

## The project map

`map` carries ten sections. Each answers the same three questions: does this surface exist, what was
read, and how much is there.

| Section | Reads | Reports beyond `state` and `sources` |
| --- | --- | --- |
| `product` | the product documentation folder | `documentCount`, `unfilledDocuments` |
| `architecture` | the architecture folder and the decision records | `documentCount`, `unfilledDocuments`, `decisionCount`, `mostRecentDecision` |
| `dataModel` | the domain folder and a conventional migrations directory | `documentCount`, `unfilledDocuments`, `migrationCount` |
| `requirements` | the product folder and `.ai/context/project.md` | `documentCount`, `blockingMarkers`, `discoveryClosed` |
| `tasks` | `.ai/tasks/`, `.ai/plans/`, and git for the ages | `inbox`, `active`, `completed`, `activeNames`, `mostRecentCompleted`, `activeAge`, `mostRecentCompletedAge`, `ageSource`, `nextSliceActive` |
| `decisions` | `.ai/memory/decisions/` | `count`, `mostRecent` |
| `openQuestions` | the open-questions register | `open`, `answered` |
| `validation` | `check-all`'s own row table | `gatingChecks`, `informationalChecks`, `blockingMarkers` |
| `release` | local git tags | `tagCount`, `latestTag` |
| `governance` | `.ai/context/governance.json` | `codeAuthorized`, `allowedPathCount`, `windowOpen` |

Every section's `state` is one of **present · partial · missing · unknown**. A vocabulary that
hedges in ten different ways is a map nobody can branch on.

Three rules keep the map honest:

- **`partial` means documents exist and still carry `TBD` markers**, counted as
  `unfilledDocuments`. That is a plainer measure than the one the placeholder checker applies, and
  it is named plainly for that reason. The gate's number appears once, as
  `requirements.blockingMarkers`, and comes from the checker itself rather than from another
  grammar invented here.
- **`migrationCount` is `null` when no conventional migrations directory exists** — a project with
  no database is not a project with an empty migrations directory.
- **`mostRecent` fields sort by filename.** Records are date-prefixed, so that is chronological
  except within a single day, where it falls back to alphabetical order.

### Slice age

Naming which slices are open and closed answers half the question; the other half is *since when*,
because a name alone cannot tell a week-old slice from a stalled one.

| Field | Means |
| --- | --- |
| `activeAge` | Whole days since the **oldest** active task was added — how long work has been open |
| `mostRecentCompletedAge` | Whole days since the newest completed task was **last touched** — moving a task into `completed/` is itself a commit against that path |
| `ageSource` | `git` or `unknown`. Never absent, so a reader always knows what produced the number |

**Read from git and from nothing else.** Filesystem timestamps were considered and rejected: in a
fresh clone an mtime is the checkout time, so every task would report as brand new — an answer to a
different question than the one asked. A **shallow clone counts as no source at all**: `git log`
there walks only the fetched commits and returns the boundary commit for any path, which is how the
freshness check once reported a stale ledger as fresh. A `rev-parse --is-shallow-repository` settles
that before anything is measured, and an unreadable history gives `null` ages with
`ageSource: "unknown"` rather than a guess.

`nextCapability` is read from the project's roadmap criteria table — the first row still marked not
built. The command reports what the roadmap already says; it never decides what comes next.

**Governance is read and never touched.** `codeAuthorized`, the allowed-path count and whether a
window is open are reported. There is no code path here that could change any of them.

## Project state vocabulary

One word answers "what kind of situation is this?", chosen in this order:

| State | When |
| --- | --- |
| `unknown` | The repository cannot be read, or `blueprint.version` is missing |
| `undefined` | Blocking placeholder markers remain in always-loaded context — the discovery gate is closed and code writes are refused |
| `blocked` | The state ledger names something in `Blocked by:` other than `none` |
| `active` | Work is open: at least one task or plan in `active/` |
| `ready` | Defined, unblocked, and nothing active — the next slice can be chosen |

`undefined` outranks `blocked` and `active` deliberately: a project that has not been defined cannot
have meaningful work in flight, and saying so is more useful than reporting the work.

## The recommendation, and the three drafts it produces

Each is derived from what the status already read. None opens a new source, and none decides
anything a file does not already say.

### `nextRecommendation` — what to do next

The **smallest eligible incomplete criterion** in the project's roadmap criteria table. A table
qualifies only when it carries a status column — a two-column criteria list has no status to read,
and inferring one from the criterion's wording would be invention.

**Two orderings decide "smallest", and both come from the table:**

1. A **partial** row before an unstarted one — part of it already exists, so less remains.
2. Within a status, the **lower number** — the order the project itself declared.

**Eligibility comes only from what a row declares.** A row saying `requires #N` is skipped while
`#N` is not complete; a row that declares nothing has no prerequisite. A prerequisite this command
inferred would be one nobody agreed to. Every skip is reported in `skipped` with its reason —
silently dropping a row is how a recommendation starts lying about what it considered — and when
*nothing* is eligible, those reasons become `blockers` and `blocked` is `true`.

**A status cell is read by its verdict, not by scanning it.** The verdict leads the cell and the
detail follows: `**done** — partial rows before unstarted ones` is *done*. Matching anywhere in the
cell once let a row be reclassified by a word in its own explanation.

This is deliberately a **different question from `nextCapability`**, which keeps its narrower
meaning: the first row still marked *not built*. When every row has been started, `nextCapability`
is `null` and the recommendation still names the partial one. The two disagreeing is itself
informative — nothing is unstarted, and something is unfinished.

When every row is complete, `capability` is `"unknown"` and says so; that is not a failure to look.

`blocked` is never a judgement. A blocker is a fact read from a file, and each one names its source:
the state ledger's `Blocked by` line, `codeAuthorized` being false, or a task already sitting in
`active/` — because the next safe thing to do is finish that, not open another.

`confidence` is `high` when the criteria table, the state ledger and the governance file were all
read; `medium` when the capability was found but one of those was missing, so the blockers could not
be fully checked; `unknown` when no capability could be named at all.

### `governanceDraft` — the window that slice would need

A draft. `canApplyAutomatically` is `false`, permanently, and a self-test case fails if it is not.

`allowedPaths` comes from **one declared rule** matched against the roadmap section that owns the
recommended row, and every drafted path must exist in the repository before it is listed. A section
no rule covers gets an empty list and says so. Guessing a path list for a surface that does not exist
yet is the same invention the rest of this command refuses.

`required` answers whether a window is actually needed: `true` when the gate is closed, when a
drafted path falls inside a `protectedPaths` entry, **or when the governance file could not be read
at all**. An unreadable gate is assumed closed, never open.

### `validationPlan` — what would have to pass

`narrow` first, then `full`. Every entry names a script that exists, so an adopting project is never
told to run something it does not have.

`ciRequired` is `true` when the slice would change shell files and ShellCheck is not installed
locally — the one check that cannot produce local evidence, so CI is the only place its result can
come from. **Nothing in the plan has been run**, and the first note says so on every run.

### `generatedPrompt` — the part a person copies

Assembled from the fields above and from nothing else, so re-running the command against an
unchanged repository produces the same text. It names the working directory, the branch, the commit,
the version, the capability and where its wording lives; it requires pre-checks; and it carries the
prohibitions.

A prohibition is dropped **only** when the roadmap section is itself about that subject — a phase
about the CLI may not be told to avoid the CLI. Entries under `### Always` are never dropped
whatever the phase.

The prompt is printed flush-left between two rules so it can be copied straight out of a terminal
without the report's indentation coming with it. It is the **one field whose value differs between
the two shells**: the working-directory line is that shell's own path, `/c/...` under POSIX and
`C:\...` under PowerShell. Every other line is identical, and the self-test asserts the prompt
contains the directory it was generated in.

**Its subject is whatever was actually selected.** When a row is named, that is the subject and its
owning section decides which prohibitions drop. When no row can be named — every criterion complete —
the subject is the next phase instead, because a prompt titled `unknown` is a defect in the artifact
rather than a fact about the project; `capability` still reads `unknown`, so nothing is dressed up.
The prohibitions are then matched against that phase, which is what keeps a prompt about the CLI
phase from telling its reader to avoid the CLI.

## `doctor` — whether this installation can run

Nine rows, each `ok` / `missing` / `unknown`, each marked required or optional, and each carrying a
detail that says what was expected. A missing tool is **reported, never hidden and never silently
worked around**: a doctor that conceals a missing dependency is how a first run fails with a stack
trace instead of a sentence.

| Row | Required | What it answers |
| --- | --- | --- |
| `shell` | yes | Which shell is running this, and its version |
| `project-status` | yes | The engine the wrapper routes to is present |
| `validation` | yes | `check-all` is present |
| `blueprint.version` | yes | Readable, and which version and role it declares |
| `manifest` | yes | The manifest every check reads is present |
| `json reader` | no | POSIX: `jq`, else a **working** python — probed by a real parse, because Git Bash ships a `python3` stub that satisfies `command -v` and cannot run. PowerShell: built in |
| `git` | no | Present, and this is a repository. Without it the status command reports its git fields as unknown rather than failing |
| `hook wiring` | no | `.claude/settings.json` references the hook scripts — the safety net is attached |
| `line endings` | no | `.gitattributes` exists and pins rules |

`ready` is `true` only when every **required** row is `ok`. Optional rows never flip it; they are
reported so the gap is visible rather than implied.

`schema` is `forgeos.doctor/1`. It carries the same three safety flags as the status document.

## `adopt` — the one command that can write

```
forgeos adopt --target <path>            a DRY RUN. Nothing is written
forgeos adopt --target <path> --apply    the single writing mode
```

**It delegates; it does not re-implement.** Both routes are `sync-blueprint`'s own, and that engine
keeps every copy rule, every hash comparison and the cases that pin them. A second copy of those
rules here would be a second answer waiting to disagree with the first.

**The dry run is not a new decision.** `sync-blueprint` has reported rather than written by default
since it shipped — *"WITHOUT `--apply` THIS ONLY REPORTS"* is its own header. `adopt` adds no writing
path at all; it chooses between two that already exist.

**`--force` is never passed and never exposed.** It is the flag that overwrites a file the adopting
project customized. A wrapper quietly offering it would undo the guarantee the sync engine exists
for, so a case asserts the flag appears in no argument list here, and another proves the guarantee
survives the wrapper: edit a synced file in the target, apply again, and the file is reported as
locally modified, skipped, and still carries the edit afterwards.

**A reading command refuses a writing flag.** `forgeos status --apply` exits `1` rather than
accepting it silently.

```
schema             string   "forgeos.adopt/1"
mode               string   dry-run | apply
wouldWrite         bool     false for a dry run, true under --apply
delegatesTo        string   the engine this routed to
forcePassed        bool     always false
source / target    string
plannedFileCount   number or null   new + updated + first-time seeds
filesWritten       number or null   apply only, read from the engine's own line
counters.*         number or null   the engine's nine counters, verbatim
exitCode           number   the engine's, propagated unchanged
warnings           array    each derived from a counter, never invented
missingSources     array
safety.canModifyFiles   bool  follows the mode -- see below
safety.canAuthorizeCode / canOpenGovernanceWindow   always false
```

**`canModifyFiles` is `true` under `--apply`.** Reporting `false` while writing files would be the
exact lie these flags exist to prevent, so the flag follows the mode instead of decorating it. The
other two never change: adopting a blueprint authorizes no code and opens no window.

**The JSON is produced without modifying `sync-blueprint`.** The engine already prints its counters
with fixed labels from array lengths, so they are read back rather than re-derived — and a label
that is absent yields `null`, never `0`, because *the engine did not print this* and *the engine
printed zero* are different facts. That coupling is pinned rather than hoped for: a case asserts the
labels this wrapper reads are the ones the engine still prints, so renaming one there fails loudly
here instead of quietly nulling every counter.

**Exit codes are the engine's, propagated unchanged** — `0` for both modes, `1` for every error it
already detects: a target that does not exist, a target equal to the source, a source that is not a
blueprint. That is the house convention exactly, so nothing needed inventing.

The source is always this checkout. Adopting from an extracted release artifact means calling
`sync-blueprint` directly, which the adoption guide already covers.

## `update` — the same delegation, with a precondition

```
forgeos update --target <path>            a DRY RUN. Nothing is written
forgeos update --target <path> --apply    the writing mode
```

`adopt` brings ForgeOS into a project that does not have it. **`update` refreshes one that does**, and
that precondition is what makes it a command rather than an alias:

- **The target must already carry `blueprint.version` with `role: adopted`.** Anything else is
  refused with exit `1`, naming `adopt` as the command to use instead. It **fails closed** — syncing
  into a project that never adopted *is* an adoption, and calling it an update would hide a
  first-time seeding behind a word that promises only a refresh.
- It reports the transition it would make: `fromVersion` read from the target's own file,
  `toVersion` from this checkout's. Neither is assumed.

Everything else is `adopt`'s, deliberately: the same engine, the same dry-run default, the same
absent `--force`, the same customization guarantee, the same counters and exit codes. **The two share
one delegation block** rather than carrying a copy each — two copies would eventually disagree about
`--force` or about a counter, and a self-test case asserts there is exactly one call to the engine.

`schema` is `forgeos.update/1`, identical to `forgeos.adopt/1` plus `fromVersion` and `toVersion`.

**What `update` deliberately does not do.** There is no network fetch, no remote update channel, no
version discovery, no package manager, and no branch or tag guessing. The source is this checkout,
full stop. It also deletes nothing: a file removed from the source is reported and left in place,
because the engine does not delete and neither does this.

## `version` — which ForgeOS this is

```
schema                 string   "forgeos.version/1"
version                string   from blueprint.version, or "unknown"
role                   string   source | adopted | "unknown"
commit                 string   full sha, or "unknown"
latestTag              string or null
distanceFromLatestTag  number or null   commits from that tag to HEAD
releaseKnown           bool     always false -- see below
releaseVersion         string or null
source                 string   "blueprint.version", or "missing"
missingSources         array    every source that could not be read, named
safety.canModifyFiles / canAuthorizeCode / canOpenGovernanceWindow   always false
```

**The version is read, never compiled in.** A self-test case runs the command against a fixture
declaring a version this repository has never carried and asserts the command reports *that* one —
a constant in the script would fail to move — and separately asserts the script contains no
version-shaped literal at all.

**`releaseKnown` is `false`, and that is a statement rather than a gap.** A GitHub Release is a
remote fact and no local file records one, so this command says it does not know instead of
inferring the release from the latest tag. The two are related but not the same: a tag can exist
with nothing published behind it, and reporting one as the other is how a version command starts
claiming a publication nobody made. The same reasoning already makes `repository.visibility`
permanently `"unknown"` in the status document.

**`distanceFromLatestTag` is `null` in a shallow clone.** `git rev-list` there counts only the
fetched commits, so the number would be a floor rather than a fact — the same guard the slice ages
use, for the same reason.

## JSON schema

`schema` is versioned. A breaking change to any field's meaning increments it; adding a field does
not. Consumers should read `schema` before trusting a key.

```
schema                    string   "forgeos.project-status/1"
generatedFrom             string   always "repository files only"
projectState              string   unknown | undefined | blocked | active | ready
repository.name           string   from the git remote, or the directory name, or "unknown"
repository.branch         string   or "unknown"
repository.commit         string   full sha, or "unknown"
repository.visibility     string   always "unknown" -- it needs the network, so it is not fetched
blueprint.version         string   from blueprint.version, or "unknown"
blueprint.role            string   source | adopted | "unknown"
state.ledgerPresent       bool
state.now / next / blockedBy   string or null, parsed from the ledger
work.tasksInbox / tasksActive / tasksCompleted    number or null
work.plansActive          number or null
work.openQuestions / answeredQuestions            number or null
validation.checkAllPresent    bool
validation.gatingChecks / informationalChecks     number or null
release.tagCount          number or null
release.latestTag         string or null
maturity.installability / projectCommandCenter / endToEndProjectDriving
                          number or null, plus maturity.source
map.<section>.state       string   present | partial | missing | unknown, for all ten sections
map.<section>.sources     array    the files or folders that section read
map.tasks.activeAge / mostRecentCompletedAge      number or null, whole days
map.tasks.ageSource       string   git | unknown -- what produced those two numbers
nextPhase                 string or null   the first phase whose criteria are not all complete
nextCapability            string or null, the first roadmap criterion still marked not built
nextRecommendation.capability   string   the smallest ELIGIBLE incomplete criterion, or "unknown"
nextRecommendation.reason       string   why that row, in words traceable to the file
nextRecommendation.source       string   the page it was read from, or "missing"
nextRecommendation.confidence   string   high | medium | low | unknown
nextRecommendation.selectedStatus  string  partial | not built | unknown -- the chosen row's own status
nextRecommendation.blocked      bool     true when blockers is non-empty
nextRecommendation.blockers     array    each naming the file the blocker came from
nextRecommendation.skipped      array    every row passed over, and why
governanceDraft.required               bool    true also when the gate could not be read
governanceDraft.allowedPaths           array   drafted paths, each proven to exist
governanceDraft.rationale              array   "<path> -- why it is needed"
governanceDraft.canApplyAutomatically  bool    always false
validationPlan.narrow / full    array    commands, each naming a script that exists
validationPlan.ciRequired       bool     true when only CI can produce ShellCheck evidence
validationPlan.notes            array    always opens with "No check in this plan has been run."
generatedPrompt           string   the copy-paste prompt, newlines and all
safety.canModifyFiles / canAuthorizeCode / canOpenGovernanceWindow   always false
missingSources            array of strings -- every source that could not be read
```

Adding these fields did not change the meaning of any existing one, so **`schema` stays
`forgeos.project-status/1`**. A consumer written against the previous version reads this one
unchanged.

## Tests

The self-test in `scripts/hooks/selftest.{sh,ps1}` covers this directory, with identical case labels
and order on both shells:

- the JSON parses, and every required key is present
- the three safety flags are `false`
- a project missing every optional source still reports, naming them in `missingSources` rather
  than crashing or inventing values
- maturity percentages are `null` when the decision record is absent
- the human output names the current phase
- running the command leaves the working tree unchanged
- the four recommendation sections exist, the existing keys survive, and `canApplyAutomatically`
  is `false`
- the generated prompt names the directory it was generated in and keeps the prohibitions that are
  never dropped
- **every displayed boolean is lower case on both shells** — PowerShell stringifies `True` and
  POSIX prints `true`, and the two drifted apart on a line no JSON test could see. Asserted in both
  directions, with a case-sensitive comparison: the default one on Windows is what let it through
- a project with no roadmap reports `unknown` and drafts no path, rather than inventing a slice
- the task map carries both ages and names the source that produced them, and an unreadable history
  reports `unknown` rather than a guessed age
- a row whose declared prerequisite is unmet is **skipped, reported, and passed over** for the next
  eligible one — proven against a fixture where the eligible row is not the first incomplete row
- when no row is eligible, the reasons are reported as blockers rather than as silence
- **a status cell is read by its verdict, not by a word in its detail** — the case that pins the
  defect where `**done** — partial rows...` classified a finished row as partial
- `forgeos status` and `forgeos next` are **byte-identical** to the engine calls they route to, in
  both modes — the case that keeps the wrapper a wrapper
- the `next` subset carries `forgeos.project-next/1` and all four of its sections
- `doctor` names every one of its nine rows, and its JSON carries `ready` and the safety flags
- a fixture with the engine removed reports `not ready`, names the missing file and what to do, and
  **still exits `0`** — reporting a problem is not failing to report
- an invalid command exits `1` with usage text, and the wrapper contains no copy of the engine's
  reading logic
- every `forgeos` command leaves the working tree unchanged
- `version` reports and carries all ten declared keys, with the safety flags `false`
- **the version comes from `blueprint.version`, never from a constant** — asserted against a fixture
  carrying a version this repository has never had, and by the absence of any version literal in the
  script
- a missing `blueprint.version` reports `unknown` and names the missing source, and a release is
  never inferred from a tag
- an unsupported argument to `version` exits `1` with the usage text, on **both** shells — the
  PowerShell half collects unmatched arguments itself rather than letting the binder answer, so the
  two shells report the same mistake the same way
