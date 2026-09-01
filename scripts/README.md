# Scripts

Dependency-free automation for operating, enforcing, and validating this blueprint.

Every script ships in **two equivalent implementations** — PowerShell (`.ps1`, Windows PowerShell
5.1 and PowerShell 7+) and Bash (`.sh`, bash 4+ with GNU coreutils: Linux and WSL are proven in
CI, stock macOS is not — see the root `README.md`). They must stay behaviorally identical.

## Areas

| Directory | Purpose |
| --- | --- |
| `ai/` | Task lifecycle helpers: create, package context, close |
| `validation/` | Structural, content, policy, link, and readiness checks |
| `hooks/` | Claude Code hooks that enforce the contract mechanically |
| `blueprint/` | Distribution: sync the portable half into a project without touching what it owns |
| `lib/` | Shared data — the manifest read by both platforms |

## Quick reference

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

```bash
bash scripts/validation/check-all.sh
```

## Rules for scripts in this repository

1. **No external modules.** Standard shell and standard library only. A blueprint that needs
   `npm install` to validate itself is not portable.
2. **Resolve paths from the script location**, never from the caller's working directory.
3. **Safe by default.** Refuse to overwrite; require an explicit `-Force` / `--force`. Support
   `-WhatIf` / `--check` for anything that moves or deletes.
4. **Meaningful exit codes.** `0` success · `1` error or failure · `2` "not ready", a distinct
   state from an error.
5. **Never print a secret.** Report a path and a line number instead.
6. **Parity.** A change to a `.ps1` requires the same change to its `.sh`, and both self-tests must
   pass. Divergence between the two is a defect.
7. **Data over code.** A list that both platforms need lives in `lib/`, as JSON, once.

## Testing the scripts

The hooks and the adoption tooling have a real self-test — the case-by-case list and its current
count live in `scripts/validation/README.md`, so this page cannot drift from it:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/hooks/selftest.ps1
```

```bash
bash scripts/hooks/selftest.sh
```

Run it after touching any hook or any rule table. `check-all` includes it as a gating check.
