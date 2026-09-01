# Field Reports

The defects that shaped ForgeOS were not found by its own tests. They were found by using it on
real work — and each one is now a permanent check that cannot regress quietly.

## The privacy rule

**A field report describes what broke in ForgeOS. It never describes what the project does.**

Never published: the name of any adopting project, organisation, client, or customer · repository
names, URLs, hostnames, or routes · file paths, schemas, or code from the project · credentials or
any fragment of one · screenshots · anything that would identify a person.

Every entry below is distilled from this repository's own public record — the changelog in
`blueprint.version` and the project decision and lesson logs (records predating the public launch
live in the development line) — all written anonymously in the first place. The test applied
before publishing any report: **remove the ForgeOS half, and see whether the remainder still
identifies anyone.** If it does, it is rewritten.

Entries are grouped by what went wrong, not by where it was found.

---

## Encoding and platform differences

### A handoff package that read fine and lied

**Discovered.** Context packages produced on Windows arrived corrupted: an em-dash became three
characters, a section sign doubled, non-Latin text turned to ruins.

**Why it mattered.** Windows PowerShell 5.1 reads a BOM-less UTF-8 file as CP1252 unless told
otherwise, and every file here is BOM-less UTF-8. The mojibake was then stored as *perfectly valid*
UTF-8 — so the package parsed, looked plausible, and quietly misinformed whoever read it next. The
POSIX half had always passed bytes through untouched, so the two platforms disagreed with no error
anywhere.

**Response.** Every read of a text file in the PowerShell half now names its encoding explicitly.
Output is emitted as UTF-8 so a captured stream matches what is written to disk, and stays BOM-less.

**Validation.** Self-test cases build a fixture carrying an em-dash, a section sign, non-Latin
script, and accented text, package it, and assert every character survives, that no mojibake
signature appears, and that no BOM is introduced. **Landed in 1.12.2.**

### A gate that answered differently on each platform

**Discovered.** The task-closure gate accepted a file on Windows that it refused on POSIX.

**Why it mattered.** One regex wrote `\s` where it meant "spaces and tabs". In .NET `\s` also
matches a newline, so an empty evidence value ran past the end of its own line and captured the
next one as its content. **A gate whose verdict depends on the platform is not a gate.**

**Response.** Horizontal whitespace is now written explicitly, and the rule was recorded: when two
implementations must agree, never let either inherit a default from its engine.

**Validation.** Four self-test cases per shell covering an empty value followed by another field,
an empty value followed by prose, same-line evidence, and a placeholder after a blank line.
**Landed in 1.14.2.**

### A JSON reader that was present but could not run

**Discovered.** On Windows and Git Bash, scripts that read JSON through `python3` produced garbage
or a misleading failure.

**Why it mattered.** A Microsoft Store stub named `python3` sits on `PATH` there and executes
nothing. Every reader that chose its interpreter with `command -v` picked the stub. The failure did
not look like a missing dependency; it looked like broken data.

**Response.** Thirteen scripts now select a reader by **capability, not presence**: `jq` first, then
a `python3` that can actually run `import json`, then `python`, then a clear message naming the real
cause. Reader output is CR-stripped, because a native Windows Python prints CRLF into a POSIX
pipeline.

**Validation.** CI runs the POSIX suite twice — once with `jq` present and once with it hidden — so
both branches are proven rather than assumed. **Landed in 1.13.3**, extending work from 1.6.0.

### Line endings that were right in the repository and wrong on arrival

**Discovered.** An adopting project received bytes that no checkout of the same tag contains.

**Why it mattered.** The committed blobs had never drifted — a renormalise pass was a verified
no-op — but sync distributes **working-tree** bytes. Twenty-one files still carried CRLF from before
the line-ending policy, and every PowerShell script sat at LF where a fresh clone produces CRLF. A
shell script can arrive on POSIX with CRLF and fail in ways that look like a logic error.

**Response.** `.gitattributes` is treated as portable infrastructure and travels with the blueprint;
the source working tree was renormalised to the exact bytes a fresh checkout produces.

**Validation.** A CI job asserts the committed tree matches the policy, and reports endings by
attribute. **Landed in 1.11.4 and 1.13.2.**

---

## Correctness across shells

### A valid reference reported broken, on one platform only

**Discovered.** The link checker reported broken references that resolved fine — but only under
POSIX.

**Why it mattered.** The `..` handler stripped a path segment with a pattern that cannot match when
no slash remains, so a reference climbing two directories collapsed to the wrong path. PowerShell
resolved it correctly. **The two shells disagreed about a correctness verdict**, which is worse than
both being wrong: whichever ran last was believed.

**Response.** One explicit branch — strip when a slash remains, empty otherwise.

**Validation.** Three self-test cases per shell pin the normalisation. **Landed in 1.13.1.**

### A reporter and an enforcer that disagreed

**Discovered.** The placeholder report said zero blocking markers while the write-blocking hook
still refused to allow code.

**Why it mattered.** Two pieces of code counted the same thing with different rules — fenced blocks,
inline code, whole words. A project was told it was ready and then blocked anyway, with no way to
reconcile the two answers.

**Response.** Both now count with identical rules.

**Validation.** A self-test runs the reporter and the enforcer against one fixture and asserts they
agree. **Landed in 1.11.2.**

---

## Governance and evidence

### A review that had not happened, recorded as done

**Discovered.** A task closed with role evidence that read, in effect, "to be filled later" — and
the closure gate accepted it.

**Why it mattered.** The gate checked that evidence **existed**, not that it was **real**. Measured
against the released code, eight of ten placeholder shapes closed a task. Worse, it produced an
archived record asserting a security review that had not been done, at the exact moment the record
becomes immutable. **Evidence-of-form is how a control becomes ceremony.**

**Response.** The gate refuses placeholder text — `TBD`, `TODO`, "to be filled", "fill later",
"placeholder", bracketed prompts, and the equivalents in Arabic — and distinguishes "placeholder
evidence" from "missing evidence" in what it says.

**Validation.** Ten placeholder shapes and three real ones, per shell, plus the backward-compatible
path for tasks without the section. **Landed in 1.14.1.**

### All-or-nothing authorization, in a project that needed neither

**Discovered.** A project had one approved database migration to write and no way to write it: the
governance switch either blocked every protected path or opened all of them, including application
code nobody had reviewed.

**Why it mattered.** The first implementation of anything is one slice. A switch whose only settings
are "closed" and "everything" makes the easiest action the most permissive one.

**Response.** A narrow `implementationWindow` — `active`, `allowedPaths`, `decidedIn` — closed by
default. While the main switch stays closed, an active window opens exactly the listed slice and
nothing else. It fails closed in every direction: an inactive window opens nothing, an empty or
malformed path list opens nothing, an unreadable file opens nothing.

**Validation.** Self-test cases per shell for each failure direction. **Landed in 1.14.0.**

---

## The public surface itself

### The front page was the only file nothing checked

**Discovered.** While preparing the repository to go public, the README announced a version four
releases old and a control count that had been wrong for weeks.

**Why it mattered.** A suite that verified 133 controls, hundreds of references, and every self-test
case had never been pointed at the page a stranger reads first. **The claim most likely to be wrong
is the one written for humans**, because the tooling that catches everything else was never aimed at
it.

**Response.** `check-public-surface` audits the page against what the tools report: the stated
version against `blueprint.version`, the check counts against `check-all`'s own declarations, the CI
job count against the workflow, and one staleness rule that the repository can decide mechanically.
Numbers that exist only at run time are reported as unchecked, with the reason — never as a pass.

It shipped **advisory while it still reported twelve findings**, then became gating in the same
change that made it pass. A check introduced red either blocks the branch or invites someone to
soften it; a check written after the page proves nothing about the moment it mattered.

**Validation.** Ten self-test cases per shell, including the passing path on a synthetic repository
and the not-applicable path for an adopted one. **Advisory in 1.15.2, gating in 1.15.4.**

### A suite that was green here and red in every project that adopted it

**Discovered.** Running the full validation inside a freshly adopted project — something no test had
ever done — produced three failing gating checks.

**Why it mattered.** Release tooling and public trust files are declared *source-only*: they exist
in the ForgeOS repository and are deliberately never copied. But the structure check still required
them everywhere, and the classification control asserted that paths which must be **absent** in an
adopting project were present. Every adopter of four consecutive versions got a red suite through no
fault of their own — and a governance tool whose own checks fail on arrival teaches exactly one
lesson: turn the checks off.

**Response.** Both checks read `blueprint.version`'s `role`. In the source repository a source-only
path must exist; in an adopted project its **presence** is the finding, which turns a false alarm
into a leak detector.

**Validation.** Two self-test cases per shell run the checks against a fixture whose role is
`adopted` — the first cases in this repository that assert behaviour *outside* the source.
**Landed in 1.15.5.**

---

## What these have in common

Three patterns account for most of the list:

1. **Two implementations that must agree, disagreeing quietly.** Windows and POSIX, a reporter and
   an enforcer, a checker and the page it describes. The fix is never "make them similar"; it is a
   test that fails when they diverge.
2. **A check that could not see what it was judging** — a truncated history, a stub interpreter, a
   page nobody audited — and answered anyway. The rule that came out of it: a check that cannot see
   the evidence says so, and never guesses the reassuring answer.
3. **A test that assumed the world it ran in.** Cases asserting the repository was incomplete, or
   that it was the source. Each passed until the thing it assumed stopped being true.

None of these were found by writing more rules. They were found by running the system on work that
mattered, and each is now a case that fails if it ever comes back.
