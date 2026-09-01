# Documentation Update Skill

## Objective

Update the correct documentation source when behavior, architecture, configuration, domain rules, or operations change.

## Method

1. Identify the audience and canonical source of truth.
2. Inspect existing documentation before creating new content.
3. Update the smallest relevant section.
4. Separate confirmed behavior from proposals and unresolved questions.
5. Link to authoritative files instead of duplicating large content.
6. Include verified commands, paths, examples, and constraints when useful.
7. Remove or mark stale guidance that the change replaces.
8. Check terminology and links for consistency.

## Destination Guide

**The ownership table lives in `.ai/rules/documentation.md` §1.** Read it there; it is not restated
here, because a second copy of an ownership table is the drift this skill exists to prevent.

Update the **smallest section of the one document that owns the fact**. If the fact appears
elsewhere, replace the copy with a link.

## Write for the arriving reader

Someone with no context who needs to act in five minutes. A table, a short example, or a directory
tree beats a paragraph. If a sentence does not change what the reader does, delete it.

## Constraints

- Do not include secrets, personal data, or unverified claims.
- Do not create duplicate sources of truth.
- Keep documentation concise enough to remain maintainable.

## Efficiency Guidance

- Update the smallest canonical document that owns the changed fact.
- Prefer links over duplicated explanation.
- Avoid loading unrelated documentation areas unless the change crosses those boundaries.

## Output

Current, factual, discoverable documentation linked to the implemented change.
