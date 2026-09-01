# Claude Code Adapter Layer

This directory makes the blueprint **executable** in Claude Code. It contains no rules of its own —
every file points into `.ai/`, which stays the single source of truth shared with Codex.

The design rule: **`.ai/` is portable and authoritative; `.claude/` is an adapter.** Nothing is
duplicated. If you find yourself copying a rule in here, the design has been broken.

**This is enforced, not requested.** `check-policy` fails the build when an `agents/` or `skills/`
adapter exceeds 20 lines, or a `commands/` adapter exceeds 35, or any of them carries an
operational section — `## Method`, `## Boundaries`, `## Do this`, `## Rules`, and others. Every
adapter must also reference `.ai/`.

Referencing `.ai/` alone was tried first and was not enough: adapters cited their source *and*
restated it in different words, at up to 2.1x the size of the file they pointed at, with zero
literal duplicate lines — invisible to any diff. Hence the line and heading limits enforced by
`scripts/validation/check-policy.ps1`, over the rule in section 1 of `.ai/rules/documentation.md`.

## Contents

| Path | Surface | What it does |
| --- | --- | --- |
| `settings.json` | Permissions and hooks | Allowlists blueprint scripts, asks before mutating commands, denies secret reads, wires the four safety hooks |
| `settings.posix.json.example` | Same, for Linux, WSL, or macOS with modern bash | Identical policy; only the hook interpreter differs |
| `agents/` | Subagents | `architect`, `implementer`, `reviewer`, `tester`, `security-reviewer` — frontmatter plus a pointer to `.ai/agents/` |
| `commands/` | Slash commands | The task lifecycle, made invocable — a pointer to the `.ai/` source plus the concrete invocations. Limit 35 lines, because two shell invocations need more room than a role pointer |
| `skills/` | Auto-triggered skills | Descriptions that drive triggering, plus a pointer to `.ai/skills/` |

## Slash Commands

| Command | Use it to |
| --- | --- |
| `/discovery` | Define an undefined project through a six-phase interview. **Fires automatically** when `.ai/context/` still has blocking `TBD` — no code is written until it completes |
| `/start-task` | Turn a request into a bounded task with observable acceptance criteria |
| `/implement` | Apply the active task as the smallest complete change, validating each step |
| `/review` | Independently review the change for correctness, safety, scope, and evidence |
| `/finish-task` | Close the task only after verifying the full Definition of Done |
| `/handoff` | Write a continuation record for another agent or session |
| `/adr` | Record a durable architectural or product decision |
| `/blueprint-validate` | Run structure, empty-file, placeholder, and hook checks |
| `/build-context` | Build a deterministic context package for transfer |
| `/adopt` | Fill the blueprint's context files from a real codebase |

## Subagents

Delegate when the work benefits from separation of responsibilities — in particular, when the
reviewer should not be the author.

| Subagent | Delegate when |
| --- | --- |
| `product-analyst` | The request is a sentence, criteria are vague, or scope is contested |
| `architect` | Structure, contracts, data models, migrations, or more than one valid path |
| `implementer` | The change is approved and scoped; you want it applied minimally |
| `reviewer` | A change is ready and needs an independent correctness and scope check |
| `tester` | Validation design is non-trivial, or a bug needs a regression test |
| `security-reviewer` | Anything touching auth, data, input, secrets, execution, or infrastructure |
| `data-reviewer` | A schema, migration, backfill, retention, or hot-path query needs judging |
| `release-manager` | A deploy, migration run, release tag, or flag flip needs a go / no-go |

A subagent inherits the entire operating contract. **Role specialization never grants an
exception** to `.ai/contract/core.md`.

## Skills

Skills load themselves when the work matches their description — you do not invoke them.

`debugging` · `codebase-navigation` · `test-generation` · `refactoring` · `documentation-update`

Each is a thin wrapper that points at the full method in `.ai/skills/`, plus the few rules worth
restating at the point of use.

## Enforcement

Two mechanisms, chosen by measured cost.

**Permissions** (`settings.json`) — enforced inside the harness at **zero** latency, cannot fail
open:

| Rule set | Covers |
| --- | --- |
| `deny` | The immutable archive (`*/completed/`, `plans/abandoned/`), Git internals, `.env` files, key material, `secrets/` |
| `ask` | `git commit` · `git push` · merge · rebase · dependency installs · docker · kubectl · terraform · cloud CLIs |

**Hooks** — for what a path glob cannot express:

| Hook | Event | Effect |
| --- | --- | --- |
| `guard-bash` | `PreToolUse` on `Bash` | Blocks force push, hard reset, recursive force delete, DB drops, piped remote scripts, infra destroy, package publish |
| `guard-discovery` | `PreToolUse` on `Write` `Edit` | Blocks writes outside `.ai/` and `docs/` while the project is still undefined |
| `guard-governance` | `PreToolUse` on `Write` `Edit` | Blocks protected application paths until the project's `governance.json` authorizes code |
| `scan-secrets` | `Stop` | Once per turn, scans every changed file; reports secret-like content by line — never the value |

A `PreToolUse` hook costs ~280 ms of process startup per call. Anything a `deny` rule can express
belongs there instead. `scripts/validation/check-policy.ps1` re-tests the rules that moved, so a
control leaving a tested hook does not become an untested one.

Verify:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1
```

Details, exit-code semantics, and how to add a rule: `scripts/hooks/README.md`.

**Hooks are a safety net against accidents, not a security boundary.** The contract remains the
real control.

## Local Overrides

`.claude/settings.local.json` overrides this file and is gitignored. Use it for personal
preferences. **Team policy belongs in `settings.json`**, where it is reviewed like any other code.

## Adding to This Layer

1. Write the rule or method in `.ai/`, where it belongs.
2. Add the thin adapter here that points to it. **It must reference `.ai/`** — `check-policy`
   fails the build otherwise, because an adapter file with no `.ai/` reference means a rule was
   written in the wrong place.
3. Add the path to `scripts/lib/blueprint-manifest.json`.
4. Run `/blueprint-validate`.

If step 1 has no obvious home in `.ai/`, that is the signal to stop and reconsider — not the signal
to write it here.
