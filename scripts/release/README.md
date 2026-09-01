# Release Tooling — Source-Only

**Nothing in this directory is distributed.** It is declared in
`scripts/lib/blueprint-manifest.json` under `distribution.sourceOnly`, which means `sync-blueprint`
drops it before classifying anything: an adopting project never receives these files.

## Why it lives inside a portable directory

The obvious home was a new top-level `tools/`. The blueprint's own discovery gate refuses it —
`guard-discovery` permits writes only to `.ai/ docs/ .claude/ scripts/ templates/ examples/
.github/`, and every one of those except `docs/` is distributed. So the split needed a third state:
**carried by the repository, never copied into a project.** Widening the gate instead would have
relaxed a protection for every adopter to make one directory writable here — the wrong direction.

The same classification is how the release *workflow* is handled. `.github/workflows` is portable,
so `release.yml` would otherwise be copied into every adopting project and try to release theirs.
It is declared source-only as well — the second entry, and it needed no new mechanism, which was
the point of building one.

## The artifact

```bash
bash scripts/release/build-artifact.sh --list          # the file list, writes nothing
bash scripts/release/build-artifact.sh                 # dist/forgeos-<version>.tar.gz + .sha256
bash scripts/release/build-artifact.sh --ref v1.14.2
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/build-artifact.ps1 -List
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/release/build-artifact.ps1
```

**The artifact is a sync source, not a product bundle.** Point `sync-blueprint --source` at an
extracted copy and it behaves exactly as a clone would.

| Carried | Why |
| --- | --- |
| The portable half, minus source-only paths | It is what sync copies |
| Seed files whose source copy is what sync reads | A new project needs its scaffolding |
| `blueprint.version` | Without it a source cannot identify itself and sync refuses it |
| `README.md`, `LICENSE` | Sync never places them; a person holding a tarball needs both |

| Refused | Why |
| --- | --- |
| Every seed target backed by a template | Those carry *this* repository's answers — identity, constraints, governance, the ledger, the open-questions register |
| `.ai/memory/`, `.ai/tasks/`, `.ai/plans/` history | The blueprint's own record, not a starting point |
| `scripts/release/` | This directory |
| Anything untracked | `git archive` reads a commit, not a directory |

The builder derives all of that from the manifest and then **re-checks the resolved list** before
writing. A boundary nobody re-checks is a boundary by hope.

## Checksums

Every build writes `<artifact>.sha256` in the format `sha256sum -c` expects — lower-case digest,
two spaces, bare filename, LF ending, so a file produced on Windows verifies on Linux.

```bash
cd dist && sha256sum -c forgeos-<version>.tar.gz.sha256
tar -tzf forgeos-<version>.tar.gz | head        # inspect without extracting
```

## The workflow

`.github/workflows/release.yml` — source-only, like everything else here.

| Property | What it is, and why |
| --- | --- |
| Trigger | `push` on tags matching `v*`, plus `workflow_dispatch` taking an existing tag. **No branch or pull-request trigger**, so no merge can publish |
| First step | Refuses anything that is not `vMAJOR.MINOR.PATCH`, reading the ref from the environment rather than interpolating it into a command |
| Second step | Refuses to build when `blueprint.version` **at that commit** disagrees with the tag. A tag naming a version its own commit does not carry is the one release mistake deleting the release cannot undo |
| Then | Runs the self-test below, builds from the tag with `build-artifact.sh --ref`, verifies with `sha256sum -c`, and re-checks the resolved archive for source-only paths |
| Uploads | Exactly `forgeos-<version>.tar.gz` and its `.sha256`. Nothing else |
| Permissions | `contents: read` for the workflow; `contents: write` on the publishing job alone — the least GitHub offers for creating a release |
| Actions | `actions/checkout` only. Publishing uses the `gh` CLI already on the runner, so no third-party action holds the token |
| Network | No remote script piping, at any step |

`workflow_dispatch` exists for one reason: a run that fails *after* the tag is pushed can be retried
without deleting and re-pushing the tag. Moving a published tag is what this project refuses to do,
and giving the retry its own door is what keeps that refusal cheap. A retry re-uploads the same two
assets, which is safe for a reason only true since v1.15.7 — the same tag builds byte-identical
archives on any platform, so the second upload carries the same bytes as the first.

Four self-test cases per shell assert these properties from the workflow's own text: that it exists
and is declared source-only, that it publishes only from a version tag, that it asks for no scope
beyond `contents`, and that it builds from the ref, verifies, and uploads only the artifact.
Removing the declaration makes the first fail 2/3 — and makes `sync` copy the workflow into the next
project that adopts, which a portable self-test case then catches at 3/4.

## What this tooling does not do

The builder does not publish, tag, sign, or upload anything, and it never touches the network.
Building an artifact is a local, repeatable act. Publishing is the workflow's job, and it happens
only when someone pushes a version tag — a separate, deliberate act.
Strategy and roadmap: recorded in the project decision log and summarized in `docs/roadmap.md`.
