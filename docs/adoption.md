# Adopting the Blueprint

How to take this blueprint into a real project. Budget 60–90 minutes for a project of any size —
most of it is answering questions only you can answer.

## 0. What you are adopting

A generic blueprint is a shell. Its value comes entirely from the project facts you put into it.
An unadopted blueprint gives an agent structure with no knowledge, which is barely better than
nothing. **The adoption step is the product.**

## 1. Copy it in

**From the release artifact** — the recommended first-time source, because you can verify it before
you trust it. Download both files from the
[latest release](https://github.com/Anasabdellatif/forgeos/releases/latest):

```bash
sha256sum -c forgeos-<version>.tar.gz.sha256      # refuse the archive if this does not say OK
tar -xzf forgeos-<version>.tar.gz
bash forgeos-<version>/scripts/blueprint/sync-blueprint.sh --source forgeos-<version> --target .
bash forgeos-<version>/scripts/blueprint/sync-blueprint.sh --source forgeos-<version> --target . --apply
```

The artifact is a sync source, not an installer and not a package: nothing is placed outside the
target you name, and the dry run above still comes first.

**New project from a clone** — clone, **discard the blueprint's history**, then start your own. The
`git init` alone is not enough; without removing `.git` first, your project inherits every commit
this repository ever made:

```bash
git clone https://github.com/Anasabdellatif/forgeos.git my-project
cd my-project
rm -rf .git && git init -b main
```

**Existing project** — use the sync tool, not `cp`. It copies only the portable half and never
touches `.ai/context`, `.ai/tasks`, `.ai/plans`, `.ai/memory`, `docs`, `README.md`, or
`.gitignore`:

```bash
bash <blueprint>/scripts/blueprint/sync-blueprint.sh --source <blueprint> --target .
bash <blueprint>/scripts/blueprint/sync-blueprint.sh --source <blueprint> --target . --apply
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File <blueprint>\scripts\blueprint\sync-blueprint.ps1 -Source <blueprint> -Target . -Apply
```

The first run is a dry run. Review it, then re-run with `--apply` / `-Apply`.

**Empty folder** — sync in, then make it a repository:

```bash
bash <blueprint>/scripts/blueprint/sync-blueprint.sh --source <blueprint> --target <folder> --apply
cd <folder> && git init -b main && git add -A
```

`git init` is a required step, not housekeeping. Validation scans the **git-tracked** tree, so
`check-all` fails until the repository exists. Sync says so when the target is not one.

This also writes `blueprint.version`, which records the version adopted and a hash per file. Every
later upgrade is the same command, and it will skip anything you have customized rather than
overwriting it. See `scripts/blueprint/README.md`.

If the project already has a `CLAUDE.md`, sync will report it as a conflict on the next run rather
than overwriting: merge by hand, keeping your project-specific content and adding the
`@.ai/contract/core.md` import line at the top.

## 2. Pick your platform

The Windows variant is committed by default. On Linux, WSL, or any POSIX shell:

```bash
cp .claude/settings.posix.json.example .claude/settings.json
chmod +x scripts/**/*.sh
```

**The POSIX scripts need bash 4+ and GNU tools** — `mapfile`, `declare -A`, `sha256sum`,
`find -printf`. Linux and WSL have them. **Stock macOS does not**: it ships bash 3.2 and BSD
utilities, so the scripts fail there as delivered until modern bash and GNU coreutils/findutils
lead your `PATH` (`brew install bash coreutils findutils`). CI proves Windows PowerShell 5.1 and
Ubuntu only — no job runs macOS, so treat it as unverified and run the self-test before trusting
it. On macOS the PowerShell half works unchanged under PowerShell 7+.

Verify the hooks actually run on your machine before trusting them:

```bash
bash scripts/hooks/selftest.sh
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1
```

## 3. See what is unfilled

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-placeholders.ps1
```

Every `TBD:` is a fact the blueprint cannot know. The report weights them: `blocking` markers sit
in always-loaded context, so an unfilled one degrades **every** future task.

## 4. Fill from evidence, not from assumption

**Two paths, depending on whether code already exists.**

### Empty project — the discovery gate does it for you

Just open Claude Code in the project. `.ai/context/project.md` still says `TBD`, so the discovery
gate fires on the first turn and the interview starts by itself. No command to remember.

Six phases: idea → requirements → technology → brand and interface → architecture and diagrams →
constraints. Nothing gets written in code until all six are confirmed and `check-placeholders`
reports 0 blocking.

Depth expected: `examples/discovery-example.md`. Contract: `.ai/contract/discovery.md`.

### Existing project — `/adopt` reads what is already there

Run `/adopt` in Claude Code, or do it manually in this order.

### 4a. `.ai/context/stack.md` — derive from files

Read the manifests that actually exist. Record **exact** versions from lockfiles.

```bash
git ls-files | rg -i "package\.json|requirements|pyproject|go\.mod|Cargo\.toml|pom\.xml|build\.gradle|\.csproj|Gemfile|composer\.json|Dockerfile|docker-compose|\.github/workflows"
```

If a version cannot be verified from a file, write `unverified:` in front of it. Never guess.

### 4b. `.ai/context/structure.md` — derive from the tree

Source paths, test paths, entry points, module boundaries, generated directories, and anything an
agent must never hand-edit. This file exists so agents stop scanning; a wrong entry here is worse
than an empty one.

### 4c. `.ai/context/project.md` and `constraints.md` — ask the humans

These cannot be derived from code:

- Purpose, stage, primary users, business priorities, non-goals, success criteria
- Hard constraints: legal, compliance, contractual, platform, compatibility
- Availability target, performance budget, backup and retention, release rules and approval gates

**Ask. Do not infer.** A confident wrong answer here propagates into every future task.

### 4d. `docs/` — fill what exists, leave the rest honest

Fill `docs/product/`, `docs/architecture/overview.md`, `docs/domains/domain-map.md`, and
`docs/operations/`. Leave `TBD:` where nothing exists yet. **An honest gap beats an invented fact.**

## 5. Make the rules yours

`.ai/rules/coding.md` and `.ai/rules/testing.md` ship with generic guidance. Replace it with:

- The real test, lint, build, and type-check **commands**
- The project's actual naming, error-handling, and module conventions
- The test levels this project actually runs, and where each lives

An agent will follow a specific command; it can only approximate a generic principle.

## 6. Make the hooks yours

Add your project's dangerous commands to `scripts/hooks/guard-bash.ps1` **and** `.sh` — the deploy
command, the migration runner, the production CLI, the data-export job.

For each rule you add:

1. Add the pattern and the reason to both implementations.
2. Add a positive and a negative case to both self-tests.
3. Run both self-tests.

Prefer precision over coverage. A false positive that blocks routine work gets the hook disabled,
which is strictly worse than a missing rule.

### Point the governance gate at your real code

`.ai/context/governance.json` arrives seeded with `codeAuthorized: false` and a list of
`protectedPaths`. **Those paths are examples written for a root layout, and a glob that matches
nothing governs nothing.** `codeAuthorized: false` protects only what `protectedPaths` names — a
project whose code lives in `backend/` and `frontend/` is, with the shipped defaults, a project
where the gate is closed over empty space. A real adoption found exactly that.

So the first governance decision is not whether to authorize code; it is where your code is:

| Layout | `protectedPaths` |
| --- | --- |
| Root application | `src/**` · `app/**` · `routes/**` · `package.json` |
| Split front and back | `backend/**` · `frontend/**` · plus each manifest |
| Monorepo | `apps/**` · `packages/**` · `services/**` |
| Any of them | the migration, infrastructure, and dependency files that matter: `migrations/**` · `infra/**` · `Dockerfile` |

Never list `.ai/`, `docs/`, `scripts/`, or `templates/`: alignment work has to stay possible while
code is closed.

Then prove it, rather than assuming — feed the hook a path you actually expect to be governed:

```bash
printf '{"tool_name":"Write","tool_input":{"file_path":"backend/src/server.ts"}}' | CLAUDE_PROJECT_DIR="$PWD" bash scripts/hooks/guard-governance.sh; echo "exit=$?"
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "'{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"backend/src/server.ts\"}}' | & { $env:CLAUDE_PROJECT_DIR = $PWD; scripts\hooks\guard-governance.ps1 }; Write-Output \"exit=$LASTEXITCODE\""
```

Exit `2` means the gate covers that path. Exit `0` while your code is still unauthorized means the
globs miss it — fix them before you rely on the gate. Repeat for one representative path per area
you meant to protect. `G0` in the seeded `blockedUntil` exists for this review; close it by doing
the review, not by deleting the line.

### Opening it: all of it, or one slice

There are two ways to let code be written, and the wrong one is the easy one.

| Use | When |
| --- | --- |
| `codeAuthorized: true` | Implementation is approved **as a whole**: the design is settled, review and tests are in place, and normal work across the protected paths is expected |
| `implementationWindow` | **One approved slice**, while everything else stays closed — the first migration, a scaffold, a spike. The project is still not authorized |

The first implementation of anything is a slice, and authorizing the project to write it opens
every other protected path at the same moment. A window avoids that trade:

```json
"codeAuthorized": false,
"implementationWindow": {
  "active": true,
  "allowedPaths": ["backend/database/migrations/**"],
  "decidedIn": ".ai/memory/decisions/2026-03-12-authorize-migration-window.md"
}
```

With that, `backend/database/migrations/001_create_users.sql` is writable while
`backend/app/Service.php` and `frontend/**` are still refused — and the refusal names the open
window, so the agent knows a slice exists and that this file is not in it.

It fails closed in every direction: an inactive window opens nothing, an active window whose
`allowedPaths` is empty or is not a list opens nothing, a window listing globs that match nothing
opens nothing, and a corrupted governance file opens nothing.

**Close the window when the slice lands.** Review what was written, then set `active` back to
`false` — or record the decision that opens the project properly. A window nobody closes is
`codeAuthorized: true` with extra steps, and it will be read as safety that is no longer there.

## 7. Verify

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

```bash
bash scripts/validation/check-all.sh
```

Once the project is genuinely adopted, switch CI to `--strict` / `-Strict` so blocking placeholders
fail the build.

Sync also seeded `.ai/context/current-state.md` — the state ledger every session reads first.
Keep it current from day one: refresh it at every task close and every handoff, and start each
session from it instead of re-deriving where the project stands. For handoffs between sessions
of this project, `scripts/ai/build-context --minimal` is the default; full mode only when the
receiver will not load the contract itself. Rules and budget: `.ai/contract/economy.md`,
measured by `check-context-budget` inside `check-all`.

## 8. First real task

**Observed:** the discovery gate fires on its own in an undefined project, phase 1 produces
`docs/product/vision.md` and the profile in `.ai/context/project.md`, and `check-all` passes on
both platforms afterwards. That much has been run on a real empty project.

**Expected, not yet observed:** phases 2 to 6 are designed to end with a backlog in
`.ai/tasks/inbox/` and a directory structure created from `.ai/context/scaffold.json` via
`scripts/ai/scaffold`. No project has been taken that far yet, so treat those two outputs as the
contract's intent rather than as demonstrated behaviour, and check what actually landed before
relying on it.

Then pick the first task and go.

```
/start-task <the smallest genuinely useful thing>
/implement
/review
/finish-task
```

Read `examples/` first. The examples set the depth bar; the templates only set the shape.

## Checklist

- [ ] Platform settings selected, hook self-test passes on this machine
- [ ] `.ai/context/stack.md` filled from manifests and lockfiles, versions exact
- [ ] `.ai/context/structure.md` filled from the real tree
- [ ] `.ai/context/project.md` and `constraints.md` answered by a human
- [ ] `docs/product/` and `docs/architecture/overview.md` reflect reality
- [ ] `.ai/rules/` carries the project's real commands and conventions
- [ ] Project-specific guard rules added, with tests, both platforms
- [ ] `protectedPaths` in `.ai/context/governance.json` match this project's real code layout,
      proven by running `guard-governance` against one path per protected area
- [ ] `check-all` passes; CI runs it on every push
- [ ] `.ai/context/current-state.md` reflects reality and is refreshed at every close
- [ ] One task has been taken end to end through the lifecycle

## Upgrading later

```bash
bash scripts/blueprint/sync-blueprint.sh --source <blueprint>            # what would change
bash scripts/blueprint/sync-blueprint.sh --source <blueprint> --apply    # take it
bash scripts/validation/check-all.sh                                     # confirm nothing broke
```

Anything you customized is reported and skipped, never overwritten. Anything the project owns —
context, tasks, plans, memory, docs — is never even looked at.

**If a customization is generally useful, push it back into the source blueprint.** A rule
maintained privately in three projects is three rules that will diverge.

## Keeping it alive

A blueprint decays the moment it stops matching reality. Three habits prevent that:

1. **Update context in the same change.** A structural change that does not update
   `.ai/context/structure.md` is incomplete.
2. **Record decisions when they happen.** A decision reconstructed six months later is fiction.
3. **Prune quarterly.** Delete rules nobody follows and documents nobody reads. A rule that is
   routinely ignored teaches agents that rules are optional — the single most expensive failure
   mode this blueprint has.
