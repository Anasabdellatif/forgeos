---
name: Feature request
about: Propose a change to what ForgeOS does or enforces
title: ''
labels: enhancement
assignees: ''
---

<!--
ForgeOS is in public preview and deliberately narrow. Several obvious-looking additions have
already been considered and declined -- telemetry, a hosted dashboard, an installer that runs
remote code, agent orchestration -- and the reasons are recorded in .ai/memory/decisions/.
Worth a look before writing: the answer may already be there, with its reasoning.
-->

## The problem

<!-- What goes wrong today, for whom, and how often. A problem statement that mentions no solution
     is the most useful kind. -->

## What you tried instead

<!-- What the current tooling does, and where it stops being enough. If nothing exists yet, say so.
-->

## What you are proposing

<!-- Rough shape is fine. Command, check, rule, or document. -->

## How it would be proven

<!-- Nothing lands here without evidence, so this is a real design question, not paperwork:
     - what would the self-test case assert, in both shells?
     - what would it print when it refuses, and with which exit code?
     - what would make it fail if it ever stopped working? -->

## Impact

- **Both shells?** Everything here exists as `.ps1` and `.sh`, behaviour-identical. Would this?
- **Does it travel?** Would adopting projects receive this, or is it only for the source repository?
  (`portable` vs `projectSpecific` vs `sourceOnly` in `scripts/lib/blueprint-manifest.json`.)
- **Does it weaken anything?** A new convenience that skips a dry run, widens a permitted path, or
  makes a gate optional will be declined regardless of how useful it is.
- **New dependency?** Anything a first-time adopter would have to install is a significant cost
  here; say what and why it is worth it.

## Scope check

- [ ] This is one change, not a programme of work
- [ ] It does not require telemetry, a network call, or a hosted service
- [ ] It does not make an existing check softer, optional, or skippable
- [ ] I have read `.ai/memory/decisions/` for a decision that already covers this
