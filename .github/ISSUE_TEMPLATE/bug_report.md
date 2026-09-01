---
name: Bug report
about: Something behaves differently from what the documentation or the tool itself says
title: ''
labels: bug
assignees: ''
---

<!--
Not for security vulnerabilities. Those go through .github/SECURITY.md, privately.

Most bugs here are answerable from output the tools already print, so the fastest path to a fix is
to paste that output rather than describe it.
-->

## What happened

<!-- One or two sentences. -->

## What you expected instead

<!-- And where that expectation came from: a document, a command's own output, a changelog entry. -->

## Reproduction

1.
2.
3.

**The exact command:**

```
<paste it, unedited>
```

## Output

```
<paste it in full, not summarized -- including the summary rows and the verdict line if this
came from check-all>
```

## Environment

- Shell: <!-- Windows PowerShell 5.1 / pwsh 7 / bash / WSL / Git Bash / other -->
- OS:
- `blueprint.version` → version: <!-- the "version" field -->
- `blueprint.version` → role: <!-- "source" or "adopted" -- the answer often differs -->
- `git --version`:
- `jq` present? `python3` present? <!-- the POSIX scripts read JSON through one or the other -->

## What the checks say

<!-- Optional but usually decisive. If the tool disagrees with itself across platforms, both halves
     matter. -->

```
bash scripts/validation/check-all.sh
<or>
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-all.ps1
```

## Confirmations

- [ ] The output above contains **no secret, credential, token, or key** — not even a redacted one
      whose shape reveals it
- [ ] It contains no private project, client, or customer detail
- [ ] I have read the changelog entry for my version in `blueprint.version`, in case this is known
      and already explained
