# Blueprint Distribution

Keeps N projects on one blueprint without drift.

## The problem this solves

A blueprint copied into a second project is a fork. Improve `guard-bash` in project A and project B
never hears about it. After three projects you have three divergent blueprints — which is exactly
the single-source-of-truth failure the blueprint exists to prevent, reproduced one level up.

## The split

Declared once, as data, in `scripts/lib/blueprint-manifest.json` under `distribution`:

| Half | Paths | Synced |
| --- | --- | --- |
| **Portable** | `.ai/contract` `.ai/rules` `.ai/skills` `.ai/workflows` `.ai/agents` `.claude` `scripts` `templates` `examples` `.github/workflows` `CLAUDE.md` `AGENTS.md` `.editorconfig` | yes |
| **Project-specific** | `.ai/context` `.ai/tasks` `.ai/plans` `.ai/memory` `docs` `README.md` `.gitignore` `blueprint.version` | **never** |
| **Source-only** | `scripts/release` — release tooling declared in `distribution.sourceOnly` | **never** |

The third row is why a portable directory is not the same thing as a distributed one. Release
tooling lives under `scripts/` because the discovery gate permits writes nowhere else, and it is
dropped from the portable set before anything is classified. Nothing in it reaches this project,
which is why this page cannot point at it: the file exists only in the source repository.

The project-specific half is never read, never written, never compared. A project's facts, work
state, decisions, and history must survive every upgrade untouched — that is the whole design.

## Usage

```bash
# See what would change. Writes nothing.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/blueprint/sync-blueprint.ps1 -Source ../forgeos

# Apply it.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/blueprint/sync-blueprint.ps1 -Source ../forgeos -Apply
```

```bash
bash scripts/blueprint/sync-blueprint.sh --source ../forgeos
bash scripts/blueprint/sync-blueprint.sh --source ../forgeos --apply
```

**Dry run is the default.** A tool that overwrites files must not do so without being asked twice.

## Local customization is detected, not destroyed

`blueprint.version` records a SHA-256 per synced file. On the next sync a target file whose hash no
longer matches was edited by the project — a project-specific `guard-bash` rule, for example. It is
**skipped and reported**, not overwritten.

```
  locally modified   1   <- skipped unless -Force
  LOCALLY MODIFIED (your edits -- review before deciding):
    ! scripts/hooks/guard-bash.ps1
```

Diff it against the source, decide whether the customization still applies, then re-run with
`-Force` / `--force` if you want the upstream version after all.

**The record holds what the tool wrote, never what it found.** After apply, a file written this run
is recorded with the hash it was written with; a file skipped as locally modified keeps the hash
recorded before it, so it is reported as locally modified on every following sync until someone
diffs it and decides — resolve it by `-Force` (upstream wins, and the source hash is recorded) or by
contributing the change upstream. Through v1.11.2 the tool re-read every present target file after
apply, skipped files included, which quietly replaced the blueprint hash on record with the hash of
the customization. The next sync saw record and target agree, called the file a plain upgrade, and
overwrote it — a local edit survived exactly one sync. Six self-test cases replay that sequence now,
on both shells, and fail if the record is laundered again.

**If a customization is generally useful, contribute it back to the source blueprint** instead of
maintaining a private fork of one file in every project.

## Checking without the source

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-blueprint-version.ps1
bash scripts/validation/check-blueprint-version.sh
```

Works offline. Reports the adopted version and every file that has drifted since the last sync.
It is a gating check in `check-all`, so a project cannot lose track of what it carries.

Pass `-FailOnDrift` / `--fail-on-drift` to make drift an error. Off by default: customization is
legitimate, and a check that fails on legitimate work gets disabled.

## Verified behavior

A seeded file is normally copied from the source path of the same name. `distribution.seedTemplates`
overrides that per target: `.ai/context/project.md` is seeded from `templates/project-context-template.md`,
because this repository fills that path with the blueprint's own identity. Without the override a new
project inherited the name `AI Project Blueprint` and `Profile: none`, which silently disabled the
profile role evidence `finish-task` enforces. `.ai/memory/open-questions.md` joined them in
v1.15.0: the register is seeded from the source copy, so once this repository recorded its own
packaging questions there, every new project inherited them.

Tested end to end on both platforms against a seeded target project:

| Behavior | Result |
| --- | --- |
| Dry run writes nothing | 5 files before, 5 after |
| Apply delivers the portable set | 103 files written |
| `.ai/context/`, `.ai/tasks/`, `.ai/memory/`, `docs/`, `README.md` | all INTACT |
| Drift detected offline after a local edit | 1 reported, 102 intact |
| Re-sync preserves the customization | preserved |
| Synced project passes its own checks | 27/27 hooks, 37 policy controls |

## Versioning

`blueprint.version` in the source carries `role: "source"` and the released version. Bump it, and
tag the repository, whenever the portable half changes in a way projects should adopt.

In a project it carries `role: "adopted"`, the version, the source it came from, and the file
hashes. Do not edit it by hand — the hashes are how the next sync tells an upgrade from a
customization.
