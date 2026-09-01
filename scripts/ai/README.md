# AI Helper Scripts

Task-lifecycle automation. Available as `.ps1` and `.sh` with identical behavior.

## Scripts

| Script | Does | Refuses to |
| --- | --- | --- |
| `new-task` | Creates a task or bug from a template, with a dated slug filename | Overwrite an existing record · open an **active** task while the project is still undefined |
| `build-context` | Builds a deterministic context package for transfer | Include an oversized file, or one containing secret-like content |
| `finish-task` | Gates closure on five mechanical checks, then archives the task and its plan. Records the discovery state at closure | Close a task with unchecked criteria, pending evidence, an active blocker, or unreplaced placeholders · archive a task opened outside the gate **without leaving a trace** |

## Usage

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/new-task.ps1 -Title "Add billing audit trail" -Type task -Status inbox -Priority high
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/build-context.ps1 -TaskPath .ai/tasks/active/2026-03-09-x.md -OutputPath .ai/context-package.md -Force
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/finish-task.ps1 -TaskPath .ai/tasks/active/2026-03-09-x.md -Check
```

```bash
bash scripts/ai/new-task.sh --title "Add billing audit trail" --type task --status inbox --priority high
bash scripts/ai/build-context.sh --task .ai/tasks/active/2026-03-09-x.md --output .ai/context-package.md --force --minimal
bash scripts/ai/finish-task.sh --task .ai/tasks/active/2026-03-09-x.md --check
```

## The discovery gate on `new-task`

`.ai/contract/discovery.md` section 1 forbids opening a task in `.ai/tasks/active/` while the
project is still undefined. Nothing measured that, so the rule was bypassable by accident — and it
was bypassed: an adopting project with 40 blocking markers created an active task, archived it, and
passed all eight checks. The authorization was real and stated in conversation; the mechanism
recorded none of it.

`new-task` now asks `check-placeholders --fail-on-blocking` before creating an **active** task.

| Situation | Result |
| --- | --- |
| Blocking markers remain, `--status active` | **Refused**, exit `2`, with the three ways forward |
| Blocking markers remain, `--status inbox` | **Allowed.** The contract wants requests captured, not lost — it forbids *starting* them |
| Blocking markers remain, `--status active` with the override and a reason | **Allowed**, and the whole circumstance is written into the task file |
| Blocking markers remain, override without a reason | **Refused.** An override with no stated reason is a silent override |
| No blocking markers | Allowed, unchanged |

```bash
bash scripts/ai/new-task.sh --title "..." --status active \
  --acknowledge-discovery-gate --override-reason "why this could not wait"
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ai/new-task.ps1 -Title "..." -Status active -AcknowledgeDiscoveryGate -OverrideReason "why this could not wait"
```

The override appends a `## Discovery Gate Override` section to the task: the blocking count on the
day it was created, the rule that was overridden, the reason given, and a note that if the criteria
and the finished discovery disagree, discovery wins.

**It fails closed.** If `check-placeholders` cannot be found, `new-task` refuses rather than guess.
Opening an active task is deliberate and infrequent, so the safe direction is closed — unlike a
per-write hook, where refusing on an unreadable manifest would get the hook switched off.

## Why `finish-task` records instead of blocking

`finish-task` is deliberately **not** gated on discovery state. Three reasons, in order of weight:

1. **The contract governs opening, not closing.** `.ai/contract/discovery.md` section 1 forbids
   *starting* work in an undefined project. A task already open is a fact; refusing to close it
   changes nothing about how it was created.
2. **It would strand work.** Every task the override legitimately created, and every task opened
   before the gate existed, would become uncloseable.
3. **It would push people around the tooling.** Archiving by hand is the obvious workaround, and it
   destroys the record `.ai/tasks/completed/` exists to keep.

But closure is never silent either. When the project still has blocking markers and the task
carries no `## Discovery Gate Override`, `finish-task` appends a `## Discovery Gate Note` before
archiving: the blocking count on the day of closure, and the fact that the task was opened either
before the gate existed or outside it. The archive then cannot imply the project was defined.

| Situation at closure | Result |
| --- | --- |
| No blocking markers | Archived, nothing added |
| Blocking markers, task has an override section | Archived, reported, nothing added — the trace already exists |
| Blocking markers, no override section | Archived, and a `Discovery Gate Note` is appended |

The note is written while the task is still in `active/`. `completed/` is an immutable archive,
denied to the write tools in `.claude/settings.json`, and it stays that way.

Neither script restates what "undefined" means. Both ask `check-placeholders`, which owns the rule.

`-WhatIf` (PowerShell) and `--check` (both) report without moving anything.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Invalid input, missing file, unsafe overwrite, or an error |
| `2` | The task is **not ready to close** — a distinct state, not an error |

## `finish-task` is a gate, not a verdict

It checks five things mechanically:

1. No unchecked acceptance criteria or checklist items
2. No `[pending]` completion evidence left in the record
3. The `Blocked` section does not report `Status: yes`
4. No unreplaced template placeholders
5. No scope tag whose profile-required role left no evidence -- see `.ai/profiles/README.md`

The Definition of Done in `.ai/contract/lifecycle.md` §6 has **eleven** conditions. The other six
— evidence observed, diff reviewed, docs updated, compatibility considered, and so on — cannot be
checked by a script. They are the agent's responsibility, and they belong in the final report with
their evidence.

A green exit from this script is not permission to claim the task is done.

## `build-context` safety

- Refuses any file above `-MaxFileBytes` / `--max-bytes` (default 65536).
- Refuses any file containing secret-like content, reporting the line number and never the value.
  Conventional placeholders (`your-api-key`, `${VAR}`, `<token>`) are recognized and allowed.
- Chooses a code fence longer than the longest backtick run in the content, so a fenced block
  inside an included file cannot terminate the wrapper early.
- Output packages are gitignored. Never commit one.
- `--minimal` / `-Minimal` omits the contract and context files every session already loads. Use it for
  a handoff inside this project; full mode only when the receiving environment will not load them.
  Measured at v1.10.0: full ~5,880 tokens, minimal ~1,356 -- see `.ai/workflows/handoff.md`.
