# Support

ForgeOS is in **public preview**, maintained alongside other work. Support is best-effort, and this
page says plainly what that means so nobody waits on a promise nobody made.

## Where to go

| You want to | Use |
| --- | --- |
| Report something broken | A **bug report** issue |
| Propose a change | A **feature request** issue |
| Ask how something works | A **question** issue, after checking `README.md`, `docs/adoption.md`, `scripts/validation/README.md`, and `scripts/blueprint/README.md` |
| Report a vulnerability | **Never an issue** — see `.github/SECURITY.md` |
| Contribute a change | `.github/CONTRIBUTING.md` |

There is no chat channel, no forum, no email address, and no paid support tier. When one exists,
this page will say so.

## What makes a request answerable

Most questions about this project are answerable from output the tools already print. A request
that carries that output gets a useful answer; one that does not usually gets a request for it.

Include:

1. **The command you ran**, exactly, and which shell — Windows PowerShell 5.1, bash, WSL, Git Bash.
2. **The output**, in full, not summarized. `check-all` prints a summary row per check and a verdict
   line; both matter.
3. **The version**: `blueprint.version` carries it, and the changelog entry for that version often
   explains behaviour that looks surprising.
4. **What you expected**, and what happened instead.
5. **Whether the project is the blueprint source or an adopted project.** `blueprint.version`
   records `role` — the answer is frequently different for each.
6. **Confirmation that the output carries no secret and no private project detail.** Redact before
   pasting; do not redact so hard that the failure becomes unreadable.

## What is not supported

- **macOS is not proven.** The POSIX half is expected to run there and has never been tested on it:
  CI runs Windows and Ubuntu only. Reports are welcome and will be treated as findings, not as
  regressions against a promise.
- **Older versions.** Fixes land on the current version; updating means re-running the sync from a
  newer source.
- **A project's own rules after adoption.** Once files land in a project, that project owns them.
  Questions about a customization belong to whoever made it.
- **Response times.** There is no SLA. Issues are read; the ones with reproducible evidence are the
  ones that move.
