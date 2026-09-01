---
name: Question
about: Ask how something works, after the documentation did not answer it
title: ''
labels: question
assignees: ''
---

<!--
`.github/SUPPORT.md` routes "ask how something works" here, and asks you to check four pages first.
That is not a hurdle — most questions about this project are answered by output the tools already
print, and a question that names what you already read gets a better answer faster.

Read first:
  README.md · docs/adoption.md · scripts/validation/README.md · scripts/blueprint/README.md

Never open an issue for a vulnerability. See `.github/SECURITY.md`.
-->

## What are you trying to do

The goal, not the command that failed. If the command is the point, say what you expected it to do.

## What you already checked

Which of the four pages above you read, and what they said that did not settle it. "None yet" is an
honest answer; it just means the first reply may be a link.

## What the tools reported

Paste the actual output, not a summary of it. Most answers are already in here:

```
bash scripts/validation/check-all.sh
```

## Environment

- OS and shell (Windows PowerShell 5.1 · Ubuntu bash · WSL · Git Bash · macOS)
- ForgeOS version — the `version` field in `blueprint.version`
- `jq` present? `python3` able to run `python3 -c 'import json'`?

## Privacy

- [ ] This issue contains no secret, credential, internal URL, client name, or private code.
