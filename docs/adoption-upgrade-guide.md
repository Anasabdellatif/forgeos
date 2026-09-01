# Upgrade Guide for Adopting Projects

For a project that already carries ForgeOS and wants a newer version. First-time adoption is
[`docs/adoption.md`](adoption.md); this page is what happens afterwards, every time.

## What an adopted project is

A project that ran the sync once and now carries two halves that behave differently:

| Half | Examples | Who owns it |
| --- | --- | --- |
| **Portable** | `.ai/contract/`, `.ai/rules/`, `.ai/workflows/`, `.ai/skills/`, `.ai/agents/`, `.ai/profiles/`, `.claude/`, `scripts/`, `templates/`, `examples/`, `.github/workflows/`, `CLAUDE.md`, `AGENTS.md`, `.editorconfig`, `.gitattributes` | ForgeOS. These update. |
| **Project-owned** | `.ai/context/`, `.ai/tasks/`, `.ai/plans/`, `.ai/memory/`, `docs/`, `README.md`, `LICENSE`, `.gitignore`, `blueprint.version` | You. Sync never reads, writes, or compares them. |

There is a third state, **source-only**: paths that exist in the ForgeOS repository and are never
copied anywhere — its release tooling and its own public trust files. You will not see them, and
that is correct. If one ever appears in your project, `check-policy` reports it as a leak.

`blueprint.version` sits in the project-owned half for a reason: it is your record of what you
adopted, including a SHA-256 for every file the sync wrote. That record is how the next upgrade
tells an upstream change from something you edited.

## What version am I on?

```bash
grep -m1 '"version"' blueprint.version
grep -m1 '"role"'    blueprint.version     # "adopted" in your project, "source" in ForgeOS itself
```

Offline, with more detail — what you carry and what has drifted since the last sync:

```bash
bash scripts/validation/check-blueprint-version.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-blueprint-version.ps1
```

That check needs no source and no network. It is a gating check in `check-all`, so a project cannot
quietly lose track of what it is running.

## The upgrade, step by step

**1. Get the newer ForgeOS.** Download the checksummed artifact from the release you want and verify
it, or clone the repository and check out that tag. There is no installer and no package registry:
the artifact is a verified copy of the source, not a package manager.

**2. Start from a clean tree.** Commit or stash your own work first. The upgrade should be one
commit you can revert in one step.

**3. Dry run. It writes nothing.**

```bash
bash scripts/blueprint/sync-blueprint.sh --source <path-to-forgeos> --target .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/blueprint/sync-blueprint.ps1 -Source <path-to-forgeos> -Target .
```

**4. Read the counters before applying anything.** They are the whole decision:

| Counter | Means | What to do |
| --- | --- | --- |
| `new` | The newer version adds this file; you do not have it | Nothing. It will be written. |
| `updated` | You have it, it matches what was recorded, upstream changed it | Nothing. It will be replaced. |
| `unchanged` | Identical on both sides | Nothing. |
| `pre-existing` | The file was in your project **before** ForgeOS arrived | Read it. Sync did not put it there and will not overwrite it. |
| `locally modified` | A portable file whose hash no longer matches what was recorded — you edited it | Decide. See below. |
| `removed in source` | Present here, gone upstream | Delete by hand if you agree. Sync never deletes. |
| `project-owned` | Matched a project-owned path | Nothing, ever. Listed only so you can see the split working. |
| `seeded` | Scaffolding written **only because it was absent** | Nothing. An existing file is never re-seeded. |

**5. Apply, when the numbers say what you expect:**

```bash
bash scripts/blueprint/sync-blueprint.sh --source <path-to-forgeos> --target . --apply
```

**6. Validate, and commit the upgrade on its own.**

## Local customizations

A portable file you edited — a project-specific rule in `guard-bash`, an extra deny in
`.claude/settings.json` — is detected by hash, reported as `locally modified`, and **skipped**. It is
not overwritten and not silently merged.

```
  locally modified   1   <- skipped unless --force
  LOCALLY MODIFIED (your edits -- review before deciding):
    ! scripts/hooks/guard-bash.ps1
```

Three ways forward, in order of preference:

1. **Contribute it upstream.** If the customization is generally useful, it stops being a
   customization and everyone gets it.
2. **Diff and decide.** Compare your version against the newer source, port what you still need,
   then take the upstream file.
3. **Keep it.** It stays skipped and stays reported on every future sync, which is the point: an
   unresolved divergence should keep asking.

**`--force` overwrites your edit with the upstream file.** It is never the default and should never
be a habit. Use it only after you have diffed the file and decided the upstream version wins — and
never as a way to make a report quiet. Through v1.11.2 a bug meant a skipped file's hash was
re-recorded as if the tool had written it, so the customization survived exactly one sync and was
silently overwritten by the next; the record now holds what the tool wrote, never what it found,
and six self-test cases replay that sequence on both shells.

## Validate after upgrading

```bash
bash scripts/validation/check-all.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

Eight gating checks decide the exit code; three informational reports never do. What to do when one
speaks up:

| Report | Means | Response |
| --- | --- | --- |
| `Structure validation FAILED` | A declared path is missing or empty | Re-run the sync with `--apply`; if it persists, a file was deleted locally |
| `Policy check FAILED` | A required permission, hook wiring, or classification is missing | Usually a hand-edited `.claude/settings.json`. The message names the control |
| `Link check FAILED` | A Markdown reference does not resolve | Almost always your own `docs/` — fix the path or the file |
| `Blueprint version` drift | A synced file no longer matches its record | Expected if you customized. Pass `--fail-on-drift` only if you want it enforced |
| `Secret scan` finding | A credential-shaped string is in a tracked file | Stop. Rotate first, then remove. The report names file, line, and pattern — never the value |
| `PROJECT OVER` / `PROJECT WARN` | Your always-loaded files exceed the budget | Trim `.ai/context/` — the ledger and the context summaries are yours to shorten |
| `PLATFORM OVER` | The blueprint's own floor exceeds the budget | Not yours to fix. Report it upstream |
| `State freshness NOTE` | The ledger has not been touched in N commits | Either refresh it, or say in your report why the state is unchanged. Under a shallow clone it declines to measure at all |
| `UNFILLED [blocking]` placeholders | `.ai/context/` or `docs/product/` still carry `TBD` | Adoption is unfinished. Fill from evidence — this is informational by default and only fails with `--strict` |
| `Public surface NOT APPLICABLE` | You are an adopted project | Correct and expected. That audit belongs to ForgeOS, not to you |

## Record the state

An upgrade is work, and work leaves a record here:

- Update `.ai/context/current-state.md` — which version you now carry, and anything the upgrade
  changed about how you work.
- If the upgrade forced a decision — you kept a customization, you changed a protected path — write
  it in `.ai/memory/decisions/`.
- Commit the upgrade separately from feature work, with the version in the message.

`check-state-freshness` measures the lag between that ledger and `HEAD`. It advises; it never blocks.

## Upgrading from 1.14.x to 1.15.x

Two changes in this range need a decision from you rather than just an apply:

**The closure gate got stricter (1.14.1, 1.14.2).** `finish-task` refuses to close a task whose
role evidence is placeholder text — `TBD`, "to be filled", a bracketed prompt, and the equivalents
in Arabic — and, since 1.14.2, an empty evidence value no longer silently absorbs the next line on
Windows. **Any active task carrying placeholder evidence will stop closing after this upgrade.**
That is the intended behaviour, and it is worth knowing before you meet it mid-task: do the review,
write what it found, then close.

**Validation gained rows (1.15.0 to 1.15.5).** `check-all` now runs eleven checks. One of them,
`check-public-surface`, audits the ForgeOS repository's own public page and reports **NOT
APPLICABLE** in your project — it is not measuring you.

**If you adopted 1.15.0 through 1.15.4, upgrade to 1.15.5.** Those versions shipped a suite that was
green in the ForgeOS repository and red in every project that adopted it: five source-only files
were declared required but correctly never copied, so `check-structure` reported them missing, and
the source-only control asserted the presence of paths that must be absent in your project. Nothing
you did caused it, and no fix on your side was needed. 1.15.5 makes both checks read
`blueprint.version`'s `role` and require source-only paths only where they belong.

## What is not automated yet

- **No one-click installer.** Adoption and upgrade are `git` plus a script you can read first.
- **No CLI.** A `forgeos` command wrapping this engine is on the roadmap.
- **No package registry.** Nothing to `npm install`, `pip install`, or `brew install`.
- **No installer around the artifact.** Checksummed release artifacts exist and are the recommended
  first-time source, but downloading one is not installing: you verify it, extract it, and run the
  same sync you would run from a clone.
- **No automatic upgrade check.** Nothing phones home, so nothing will tell you a new version
  exists. Watch the repository.

Roadmap: [`docs/roadmap.md`](roadmap.md). What changed and why:
[`docs/changelog.md`](changelog.md).
