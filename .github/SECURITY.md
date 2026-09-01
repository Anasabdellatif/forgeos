# Security Policy

ForgeOS is in **public preview**. It is an engineering operating system for governed software
delivery, not a finished commercial product, and this policy describes what it does and does not
protect.

## Reporting a vulnerability

Report privately, not in a public issue. Use GitHub's **Report a vulnerability** button under this
repository's Security tab, which opens a private advisory visible only to the maintainers.

Please include: what you found, the file or script involved, the steps that reproduce it, and what
an attacker could achieve. A proof of concept helps and is welcome.

**Never include a real secret in a report.** If a credential is involved, say which kind and where
it appeared — never its value. If you believe a secret has been exposed by this repository, say so
in the first line, so it can be rotated before anything else is discussed.

Expect an acknowledgement within a week. This is a small project maintained alongside other work: a
fix lands when it is understood and proven, not on a promised date. Public credit is offered unless
you ask otherwise.

## What this project protects, honestly

The hooks and validation checks are a **safety net against accidents, not a security boundary.**

They exist because an agent working at speed makes mistakes a reviewer would catch too late, and
mechanical refusal is cheaper than a late review. `guard-bash` refuses destructive command shapes;
`guard-discovery` and `guard-governance` refuse writes outside authorized paths; `scan-secrets`
refuses to let a credential-shaped string reach a commit; the validation suite refuses to call a
change complete without evidence.

None of that stops a determined attacker, and none of it is designed to:

- A hook is a `PreToolUse` check inside one tool. Anything running outside that tool ignores it.
- The rules live in files in the repository. Whoever can edit the repository can edit the rules.
- Pattern matching catches known shapes. A novel shape passes until someone adds it.
- The permissions in `.claude/settings.json` are enforced by the harness, not by an operating
  system.

Treat them the way you treat a linter or a pre-commit hook: valuable, mechanical, and not a
substitute for review, least privilege, or a real threat model.

## What the tooling does

- **No network.** No script under `scripts/` fetches, posts, or resolves anything. Adoption,
  updates, validation, and release artifacts are local file operations plus `git`.
- **No telemetry.** Nothing is collected, counted, or transmitted. There is no analytics endpoint
  and no usage ping — and so no opt-out to configure, because there is nothing to opt out of.
- **No installer that executes remote code.** There is no `curl` piped into a shell, and none will
  be added: `guard-bash` refuses that command shape, and a governance tool that asks you to do what
  its own hook forbids has already lost the argument.
- **Writes are narrow and announced.** `sync-blueprint` is a dry run by default, never overwrites a
  project's own files, and reports every file it would touch before touching any.

## Supported versions

The latest released version receives fixes. Older versions do not: this is a source-distributed
system, and updating means re-running the sync from a newer source — see `docs/adoption.md`.

## Scope

In scope: anything in this repository — hooks, validation scripts, the sync engine, the manifest,
templates, and the workflow.

Out of scope: vulnerabilities in Claude Code, Codex, GitHub Actions, `git`, PowerShell, or bash
themselves; report those to their maintainers. Also out of scope: a project that adopted ForgeOS
and then changed the rules. Those files belong to that project from the moment they land in it.
