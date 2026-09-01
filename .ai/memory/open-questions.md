# Open Questions and Assumptions

**The single register of what this project does not yet know.**

Before this file existed, assumptions and open questions were recorded in six different section
types across five file classes — `docs/product/vision.md`, `docs/domains/domain-map.md`,
`.ai/context/constraints.md`, every task, and every plan — with no index. Nothing could answer
*"what are we still unsure about?"*, and `.ai/contract/discovery.md` §4.3 mandates recording
`undecided: <question>` with an owner while giving it nowhere to land.

That is what this file is for.

## What belongs here

| Kind | Meaning |
| --- | --- |
| `assumption` | Something being treated as true without proof. If it is wrong, work has to change. |
| `question` | Something nobody has decided yet, blocking or not. |

Anything that must be true for the current plan to hold, and that nobody has verified, is an
assumption — whether or not someone wrote it down as one.

## What does not belong here

- A decided matter. That is a decision — `.ai/memory/decisions/`.
- A task. If the answer is "someone must do work", open a task.
- A risk with a known cause and mitigation. That belongs in the plan's `Risks` section.
- A `TBD` in a template. That is an unfilled field, not an open question.

## Rules

1. **Never resolve an entry silently.** Closing one means linking the decision, the task, or the
   answer that closed it, and dating it.
2. **Every entry has an owner.** "The team" is not an owner. An entry with no owner is an entry
   nobody will answer.
3. **State what it blocks.** An open question that blocks nothing is a note; say so, and keep it
   short.
4. **A task or plan may state an assumption locally, but anything that outlives the task belongs
   here.** When a task closes, promote its surviving assumptions into this register.
5. Closed entries stay, with their outcome. The record of what we were once unsure about is the
   most useful part of this file.

## Register

Newest first. Status: `open` · `answered` · `superseded` · `dropped`.

| # | Kind | Question or assumption | Owner | Status | Raised | Source | Blocks | Closed by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 013 | question | `guard-discovery` counts only word markers, so a project whose context is written in bracket style (`[the project name]`) opens the gate while `check-placeholders` still reports it blocking — reproduced in a sandbox: hook exit 0, checker 3 blocking. The hook documents the tradeoff deliberately, to avoid a second home for the bracket regex | blueprint maintainer | answered | 2026-08-28 | M-19.14 pre-public audit | any adopter who fills context in bracket style rather than `TBD` | v1.15.10, 2026-08-28 — one detector, not two: the hook now runs the project's `check-placeholders --fail-on-blocking` and takes its verdict, failing closed when that checker is missing or answers without a count. Bracket-style context went from exit 0 to exit 2 while docs stay permitted; two cases per shell pin both |
| 012 | question | Five paths carried no `.gitattributes` rule — `LICENSE`, `.editorconfig`, `.gitattributes`, `.gitignore`, `*.example` — so their bytes followed each platform's default: adopters received CRLF on Windows and LF on Linux, and the same tag built different artifacts | blueprint maintainer | answered | 2026-08-27 | M-19.7 artifact proof | byte-reproducible releases, and adopter consistency | v1.15.7, 2026-08-27 — `.gitattributes` pins all five to `eol=lf`, which is what `.editorconfig` `[*]` already required; 0 of 215 tracked paths now inherit the platform, and a release self-test case per shell fails by name if one ever does again |
| 011 | question | Which field discoveries from adopted projects are approved for publication, and by whom — the anonymization rule is written but no report is cleared yet | blueprint maintainer | answered | 2026-08-26 | M-19.1 launch contract | the field-reports index (M-19.5) | v1.15.9, 2026-08-28 — `docs/field-reports.md` **is** the cleared set: ten entries, published since v1.15.5, each describing what broke in ForgeOS and naming no project, client, repository, route or person. The maintainer clears an entry by writing it there under that rule |
| 010 | question | Does the repository go public under its current name, accepting a later rename and redirect, or does the rename precede publication? | blueprint maintainer | answered | 2026-08-26 | M-19.1 launch contract | the publication step after M-19.6 | v1.15.8, 2026-08-28 — the rename precedes it: renamed to `Anasabdellatif/forgeos` while private, tag and release intact, visibility unchanged |
| 009 | question | `check-state-freshness` reported OK under CI's shallow checkout, so the state line proved nothing on every push — measure it, or say it cannot be measured? | blueprint maintainer | answered | 2026-08-25 | M-18.1, found while fixing the ShellCheck failure | the persistence gate's only mechanical signal | v1.15.1 — the checker refuses to guess and the check-all jobs fetch full history |
| 008 | question | `check-structure.ps1` detects undeclared files and `check-structure.sh` does not — a POSIX-only run never sees an orphan. Fix the gap or drop the feature? | blueprint maintainer | answered | 2026-08-25 | M-18, found when two new scripts were reported on Windows only | validation parity, and anyone maintaining from Linux | v1.15.10, 2026-08-28 — the POSIX half scans the same roots, extensions and exclusions, prints the same block and carries the count in the same summary line. Reported, not gating, on both: Windows never failed on one either. One case per shell creates an undeclared file and asserts it is named, counted, and still exit 0 |
| 007 | assumption | A seed file is safe only while it is empty — any seed file this repository will ever fill needs a template override BEFORE it is filled | blueprint maintainer | open | 2026-08-25 | M-18 artifact boundary | the next seed file someone fills | — |
| 006 | assumption | Managed context keeps a real task at or under 50% of an unmanaged run's tokens — claimed, never measured | blueprint maintainer | open | 2026-08-25 | M-17 packaging decision | the efficiency claim on the public README (M-20) | — |
| 005 | question | `.ai/memory/open-questions.md` seeds from this filled file (no `seedTemplates` override), so these rows travel into a fresh adoption's register — add an override? | blueprint maintainer | answered | 2026-08-25 | M-17 persistence step | register hygiene of any adoption seeded after 2026-08-25 | seedTemplates override, v1.15.0 — the source-only distribution decision |
| 004 | question | Where does the release workflow live so it does not travel to adopters — a portable-set exclusion, or outside `.github/workflows/`? | blueprint maintainer | answered | 2026-08-25 | M-17 packaging decision | M-18 release artifacts | `distribution.sourceOnly`, v1.15.0 — same decision |
| 003 | question | Is the ForgeOS name available where it matters — GitHub repository and organization, npm, domain? The GitHub half is settled (the repository is `Anasabdellatif/forgeos`); npm and the domain are unchecked | blueprint maintainer | open | 2026-08-25 | M-17 packaging decision | **M-22 installability**: the npm/npx channel cannot ship until the name resolves. Raised from a branding preference to a shipping gate by the 2026-08-28 maturity-bar decision | — |
| 002 | assumption | The POSIX half runs on macOS (bash 3.2, BSD userland) without changes — never exercised there | blueprint maintainer | open | 2026-08-25 | M-17 packaging decision | **M-22 installability**: no Homebrew formula before a macOS CI job proves the platform, and the support matrix ForgeOS may publicly claim | — |
| 001 | question | Does the CLI earn npm distribution, or do checksummed artifacts plus the scripts suffice? | blueprint maintainer | answered | 2026-08-25 | M-17 packaging decision | M-21 and M-22 | 2026-08-28, owner decision — it earns it: npm/npx is a declared installability channel in M-22, alongside the CLI in M-21. Artifacts plus scripts are no longer judged sufficient for a public launch. Shipping it still waits on question 003 |
| TBD: 001 | TBD: `assumption` or `question` | TBD: state it so it can be answered yes or no | TBD: a person | TBD: `open` | TBD: YYYY-MM-DD | TBD: task, plan, discovery phase, or review | TBD: what waits on it, or `nothing` | TBD: decision path, or `—` |

## Example of a filled row

Not project data — a shape reference. See `examples/discovery-example.md` for two in context.

| # | Kind | Question or assumption | Owner | Status | Raised | Source | Blocks | Closed by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 004 | question | Which payment provider, given the region? | product owner | open | 2026-08-03 | discovery phase 3 | subscription billing task | — |
| 003 | assumption | No downstream consumer reads the per-line refund amounts | implementer | answered | 2026-08-01 | plan step 4 | schema change | verified in review, 2026-08-02 |
