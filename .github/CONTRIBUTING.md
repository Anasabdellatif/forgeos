# Contributing

ForgeOS is in **public preview**. Contributions are welcome, and the bar is specific rather than
high: this project's argument is that rules which are merely written get ignored, so a change is
judged by the evidence it carries, not by how reasonable it sounds.

Read `.ai/contract/core.md` before a first substantial change. It is the contract every agent and
every human works under here, and most review comments are just a pointer back into it.

## The house rules

**1. Both shells, or neither.** Every behaviour exists twice — `.ps1` for Windows PowerShell 5.1 and
`.sh` for POSIX bash — and the two must be behaviour-identical, not merely similar. A fix to one
half that skips the other is a defect being created, not fixed: it makes the verdict depend on the
platform. A gate that answers differently on two platforms is not a gate.

**2. Every behaviour gets a permanent case.** `scripts/hooks/selftest.ps1` and `selftest.sh` run the
same cases, in the same order, with the same labels, and CI fails if they ever diverge by one case.
New behaviour without a case is behaviour nobody will notice losing.

**3. Reproduce before you fix.** Show the defect with the current code first. If the current code
already refuses the input, there is no defect to fix — say so and stop, rather than implementing an
imaginary fix.

**4. Never weaken a gate to get a pass.** Do not raise a threshold to hide a warning, delete a
failing case, soften a check, or disable a hook. If a check is wrong, fix the check and say why in
the same change. This is the one rule with no exception.

**5. Claims need artifacts.** "It works" is not evidence; the command and its output are. The same
applies to anything written on a public page — see `scripts/validation/check-public-surface.sh`,
which exists because the README claimed a version it had drifted four releases away from.

**6. Write what you observed.** Never report a command, test, or check as passing unless it ran and
you saw the result.

## Before opening a pull request

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
bash scripts/validation/check-all.sh
```

Both must pass. `check-all` runs the gating checks and the informational reports and prints a
verdict line; paste it into the pull request. If you can only run one platform, say which — CI runs
Windows, Ubuntu with `jq`, Ubuntu with the `python3` fallback, ShellCheck, a line-ending check, and
a self-test parity job, and it will find what you could not.

Keep line endings alone: `.gitattributes` decides them, `.ps1` is CRLF and `.sh` is LF, and CI fails
if the committed tree disagrees.

## Originality

Do not copy code, text, documentation, visual identity, or package structure from another project.
Studying how others solved a problem is normal and encouraged; reproducing their material is not,
whatever its licence permits. Describe the idea in this project's own words and cite what inspired
it.

## Scope

Small, complete, reviewable changes. One concern per pull request. If a change touches architecture,
a public contract, the distribution split, or the manifest, say so in the description — those affect
every project that has adopted this blueprint, and they are reviewed against that.

Do not add: telemetry, analytics, a network call in any script, an installer that executes remote
code, or a dependency that a first-time adopter would have to install. Every one of those has been
considered and declined, and the reasons are recorded in `.ai/memory/decisions/`.

## What happens next

Changes are reviewed for correctness, scope, safety, and evidence, in that order. Expect questions
about the evidence before questions about the style. A change that is right but unproven is not
rejected — it is sent back for the proof.
