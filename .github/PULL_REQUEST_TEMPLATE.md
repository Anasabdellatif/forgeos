<!--
Read .github/CONTRIBUTING.md first. The sections below are what review asks about anyway;
answering them here saves a round trip. Delete a section only if it is genuinely not applicable,
and say why rather than deleting it silently.
-->

## What this changes, and why

<!-- One paragraph. What was wrong or missing, and what this does about it. -->

## Scope

- Files changed:
- Anything touched that is not strictly required by the above, and why:

## Evidence

<!-- Paste the output. "It passes" is not evidence; the verdict line is. -->

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
<paste the summary rows and the verdict line>

bash scripts/validation/check-all.sh
<paste the summary rows and the verdict line>
```

- Platforms actually run: <!-- Windows PowerShell 5.1 / bash / WSL / Git Bash / only one, say which -->
- If this fixes a defect: how it was reproduced **before** the fix, and what the same input does now.
- If this adds behaviour: the self-test case that pins it, in **both** shells, same label and order.

## Public claims

- [ ] This change does not alter any number or claim printed on a public page
- [ ] It does, and `check-public-surface` was re-run and reports no new drift

<!-- The README states a version and check counts. If this change moves one of them, the page has
     to move with it, or the checker will say so. -->

## Distribution

- [ ] Nothing new travels to adopting projects
- [ ] Something does — list it, and say why an adopter should receive it
- [ ] Something new must NOT travel, and is declared in `distribution.sourceOnly`

<!-- The split lives in scripts/lib/blueprint-manifest.json: portable is copied into every adopting
     project, projectSpecific is never touched, sourceOnly is carried here and never copied.
     A file that stays home only because no list names it is safe by accident, not by design. -->

## State and persistence

- [ ] No durable decision, lesson, or open question came out of this
- [ ] One did, and it is recorded under `.ai/memory/` — path:
- [ ] `.ai/context/current-state.md` still describes where the project is

## Anything a reviewer should look at hardest

<!-- The part you are least sure about. Naming it is not a weakness; it is the fastest route to a
     useful review. -->
