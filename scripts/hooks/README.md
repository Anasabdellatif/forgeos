# Blueprint Hooks

Mechanical enforcement of the parts of the operating contract worth enforcing mechanically.
Wired up in `.claude/settings.json`.

Hooks are a **safety net against accidents**, not a security boundary. The contract in
`.ai/contract/` remains the real control.

## Installed Hooks

| Hook | Event | Matcher | Effect |
| --- | --- | --- | --- |
| `guard-bash` | `PreToolUse` | `Bash` | Blocks destructive commands: force push, hard reset, recursive force delete, DB drops, piped remote scripts, infra destroy, package publish, and more |
| `guard-discovery` | `PreToolUse` | `Write` `Edit` `NotebookEdit` | Blocks writes outside `.ai/` and `docs/` while the project is still **undefined** — blocking `TBD` markers remain in always-loaded context, counted with exactly the rules `check-placeholders` uses |
| `guard-governance` | `PreToolUse` | `Write` `Edit` `NotebookEdit` | Blocks writes to **protected application paths** until the project's own `.ai/context/governance.json` says `codeAuthorized: true` — a different question from discovery, answered by humans, never by default |
| `scan-secrets` | `Stop` | — | Once per turn, scans every file Git reports as changed or untracked; reports secret-like content by file and line, never the value |

## Two gates, two questions

`guard-discovery` and `guard-governance` sit on the same event and look alike. They are not the
same gate, and the day they were confused a real project stayed safe only by accident.

| | `guard-discovery` | `guard-governance` |
| --- | --- | --- |
| Asks | *Is the project defined?* | *Has anyone authorized writing application code?* |
| Reads | `TBD` markers in always-loaded context | `.ai/context/governance.json`, project-owned |
| Opens when | The documents are filled | A human sets `codeAuthorized: true` and records why — or opens one narrow window |
| Default | Closed until filled | **Closed until authorized. No default opens it.** |
| Governs | Everything outside `.ai/` and `docs/` | Only the globs in `protectedPaths` |

**A narrow implementation window is the middle setting**, since v1.14.0. `codeAuthorized: true`
opens every protected path at once, which is too much for the first slice of work — a migration,
a scaffold — so `implementationWindow` leaves the project closed and makes only the paths it
lists writable:

```json
"implementationWindow": { "active": true, "allowedPaths": ["backend/database/migrations/**"], "decidedIn": ".ai/memory/decisions/2026-08-21-window.md" }
```

**It narrows permission; it is not a bypass.** The project stays unauthorized, everything outside
`allowedPaths` is still refused, and the refusal names the open window rather than pretending
none exists. Every failure mode is closed: inactive opens nothing, an empty or non-array
`allowedPaths` opens nothing, globs that match nothing open nothing, and a corrupted file opens
nothing — it cannot even read a window. Close it when the slice lands: `docs/adoption.md` §6.

A project can be fully defined and still be in alignment, review, or approval with three decision
gates open. Discovery cannot see that — it opened the moment the last `TBD` was filled. That is
what happened: an adopting project had `G1b`, `G3`, and `G4` open and no code authorized, and the
only thing between it and its first source file was a stray `TBD` inside a *documentation sentence*
that happened to keep discovery shut. Protection by accident is not protection. Governance is the
gate that actually asks the question.

The refusal names the open gates, the file that was attempted, and where the decision is recorded,
because a block that does not explain itself teaches the agent to work around it. A missing
governance file means *not governed* (older projects predate it); a file that is present but
unreadable fails **closed** for protected paths — a corrupted gate must not read as an open one.

All four ship as `.ps1` (Windows PowerShell 5.1 and 7+, the committed default) and `.sh` (bash 4+
with GNU tools, sharing `_json.sh` for payload parsing — Linux and WSL are proven in CI, stock
macOS is not; see the root `README.md`).

**A seeded `protectedPaths` list governs nothing it does not match.** The defaults describe a root
layout, so a project whose code sits under `backend/` and `frontend/` gets a closed gate over empty
space — `codeAuthorized: false` and no protection, which reads as safety and is not. Map the globs
to the real layout at adoption and prove it by feeding the hook a representative path:
`docs/adoption.md` §6 carries the command and the exit codes to expect.

## What Is Deliberately *Not* a Hook

Immutable-archive protection, `.env` and key-material protection, and confirmation on mutating
commands live in `.claude/settings.json` as `deny` and `ask` rules instead.

The reason is measured. A `PreToolUse` hook on `Write|Edit` costs ~280 ms of process startup on
every file write; a second `PostToolUse` hook doubled that to ~560 ms per write. Permission rules
are enforced inside the harness at **zero** cost and cannot be bypassed by a hook timing out or
failing open.

A control that moves out of a tested hook must not become an untested control, so
`scripts/validation/check-policy.ps1` verifies every required `deny` and `ask` rule is still
present. It runs as a gating check in `check-all` and in CI.

`scan-secrets` moved from per-write to per-turn for the same reason. Coverage is identical —
every written file appears in `git status` — while the startup cost is paid once instead of once
per file.

## Contract Mapping

| Control | Mechanism | Contract clause |
| --- | --- | --- |
| Destructive commands need authorization | `guard-bash` hook | `core.md` §3.5, `safety.md` §1 |
| Secrets never enter the tree | `scan-secrets` hook + `deny` rules | `core.md` §3.3, `.ai/rules/security.md` §1 |
| `completed/` is an immutable archive | `deny` rules | `lifecycle.md` §1 |
| Mutating commands are confirmed | `ask` rules | `safety.md` §1 |

## Exit Code Semantics

| Code | Meaning |
| --- | --- |
| `0` | Allow. Nothing is shown. |
| `2` | Block (`PreToolUse`) or report to the agent (`Stop`). `stderr` is fed back to Claude. |
| other | Non-blocking error. Logged; execution continues. |

All hooks **fail open** on a malformed or unreadable payload. A parsing bug must never wedge a
session.

`scan-secrets` checks `stop_hook_active` before doing anything: a `Stop` hook that exits 2 makes
Claude continue, so without that guard it would loop forever. The self-test covers it.

## Verifying

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1
```

```bash
bash scripts/hooks/selftest.sh
```

The suite long outgrew the hooks alone: destructive commands blocked, safe commands allowed,
secrets detected, both gates exercised on throwaway fixtures, and the adoption and context tooling
covered case by case — the full list and its current count live in `scripts/validation/README.md`.
Run it after any edit to a hook or a rule table. `check-all` includes it as a gating check on both
platforms.

## Switching Platform

```bash
cp .claude/settings.posix.json.example .claude/settings.json    # Linux / macOS
chmod +x scripts/hooks/*.sh scripts/validation/*.sh scripts/ai/*.sh
```

Policy is identical between the two; only the interpreter differs.

## Adding a Rule

1. Ask first whether it belongs in `.claude/settings.json` as a `deny` rule. If a path glob can
   express it, the permission is strictly better — zero latency, and it cannot fail open.
2. If it needs to inspect command *content*, it belongs in `guard-bash`. Add the pattern and the
   reason to **both** the `.ps1` and the `.sh` rule table.
3. Add a positive case and a negative case to **both** self-tests. Run them.
4. If you added a permission rule instead, add it to `policy.requiredDeny` in
   `scripts/lib/blueprint-manifest.json` so `check-policy` guards it.

Prefer precision over coverage. A false positive that blocks routine work gets the whole hook
disabled, which is strictly worse than a missing rule.

## Searching for a Guarded Pattern

`guard-bash` matched the text of a command, so `grep -R "rm -rf" .` was blocked by the rule meant
to stop the deletion — the safest way to inspect a dangerous pattern was the one way the hook
refused. Found by an audit; fixed in v1.13.5.

A read-only search is now allowed, and the exception is deliberately narrow, because a wrapper
that merely quotes the text still runs it. All three must hold:

| Condition | Why |
| --- | --- |
| The program is a known search tool — `grep` `egrep` `fgrep` `rg` `ag` `ack` `findstr` `Select-String` `sls`, or `git grep` | These read; they do not delete |
| No `;` `\|` `&` backtick `$(` `(` `)` `{` `}` `<` `>` or newline | Any of them can start a second command that does execute |
| No `--pre` `--pager` `--hostname-bin` | Options that make a search tool run another program |

So `grep -R 'rm -rf' .` passes, while `bash -c 'rm -rf /tmp/x'`, `grep -R 'rm -rf' . ; rm -rf /tmp/x`,
and `grep -R 'rm -rf' . | sh` all stay blocked. **Anything ambiguous keeps its block.**

## Known Limits

- Pattern matching is textual. Obfuscated or indirect commands (variable expansion, `eval`,
  base64) are not caught, by design.
- `scan-secrets` runs after the write. It reports rather than prevents; the value is already on
  disk and must be removed and rotated.
- `.claude/settings.local.json` can override policy locally and is gitignored. Team-wide policy
  belongs in `.claude/settings.json`, where it is reviewed like any other code.
