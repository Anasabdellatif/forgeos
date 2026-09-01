# Workflows

Repeatable procedures for moving work safely from request to completion.

## Available Workflows

| Workflow | Stage | Slash command |
| --- | --- | --- |
| `discovery.md` | **Define an undefined project. Runs automatically.** | `/discovery` |
| `start-task.md` | Clarify, scope, and activate work | `/start-task` |
| `implement.md` | Execute the change in controlled steps | `/implement` |
| `review.md` | Inspect correctness, risk, and scope | `/review` |
| `finish-task.md` | Validate and close completed work | `/finish-task` |
| `handoff.md` | Preserve continuation context | `/handoff` |

## This directory is the single source of truth

The procedure lives here. `.claude/commands/` routes to it and adds only what a workflow file
cannot carry: the concrete PowerShell and bash invocations, the subagent names, the `$ARGUMENTS`
placeholder.

**That is enforced, not requested.** `check-policy` fails the build on a command over 35 lines or
carrying a section such as `## Do this` or `## Rules`. After v1.2.1 the ten commands carry zero
`##` headings — a command that needs sections is restating a procedure that belongs here. The
controls live in `scripts/validation/check-policy.ps1`; the rule they enforce is section 1 of
`.ai/rules/documentation.md`.

Codex users follow these files directly.

Four commands have no workflow counterpart — `/adr`, `/adopt`, `/blueprint-validate`,
`/build-context`. Each routes to its own source instead: `.ai/memory/decisions/README.md`,
`docs/adoption.md`, `scripts/validation/README.md`, and `scripts/ai/README.md`.

## Usage

Select the smallest workflow that matches the current stage. A workflow defines the **process**;
the task file defines the specific **outcome**.

A workflow never overrides `.ai/contract/core.md`, the active task's acceptance criteria, or any
safety control. When a workflow step conflicts with the contract, the contract wins and the
conflict gets reported.
