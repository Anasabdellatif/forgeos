# Project Constraints

Constraints of the blueprint repository itself. An adopting project's copy is seeded from
`templates/constraints-template.md`; nothing here travels into it. `core.md` §3 is not repeated.

## Hard Constraints

- Cross-platform parity: every script ships as `.ps1` and `.sh`, identical behaviour and
  label-identical self-tests, proven in CI.
- Windows PowerShell 5.1 is the floor — no PS7-only syntax. POSIX assumes bash, `jq` or
  `python3`, and mawk-compatible `awk`.
- The core names no language, framework, product type, or AI provider.
- CI uses no third-party actions beyond `actions/*`.
- Line endings follow `.gitattributes`, kept in step with `.editorconfig`.
- Sync guarantees are only strengthened, never relaxed; identity files seed from `templates/`,
  never from this repository's filled copies.

## Scope Boundaries

- No framework app templates and no domain overlays yet; rationale lives in
  `.ai/memory/decisions/`.

## Prompt Prohibitions

The `Do not:` list `forgeos next` writes into a generated prompt. **These are this repository's
constraints, not universal ones**, and they live here because this file is project-specific: sync
never copies it, so nothing below reaches an adopting project. An adopter's copy is seeded from
`templates/constraints-template.md` and carries generic entries instead — which is the whole point.
Before this section existed, entries were hardcoded in `project-status`, so every adopting
project was told not to touch repositories it had never heard of.

Two forms, and the parser reads nothing else:

- `- when-not `regex`: text` — emitted unless the slice being named is itself about that subject.
  A phase about the CLI may not be told to avoid the CLI.
- `- text` — always emitted.

Edit this list freely. It is read, never written.

### Conditional

- when-not `release|launch`: create a tag or a GitHub Release
- when-not `install`: start installer or package manager work
- when-not `dashboard|website`: start dashboard or website work

### Always

- weaken, skip, or delete a test to obtain a passing result
- add co-author attribution or tool-credit language
- push
