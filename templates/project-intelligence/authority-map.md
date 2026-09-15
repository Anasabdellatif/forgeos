# Authority Map

Which sources govern this project, in what order, and who settles a conflict. Written first; every
other map defers to it. Procedure: `.ai/workflows/ingest-project.md` §2.

- Project: [Project name]
- Updated: [YYYY-MM-DD]
- Mode: `PROJECT_WITH_GOVERNING_DOCS`

## Authority order

Highest first. Reorder only with a reason in the last column.

| Rank | Source class | Paths | Wins over | Why this rank |
| --- | --- | --- | --- | --- |
| 1 | Signed specification or contract | [docs/Client/ ...] | every rank below | [signed by the client on YYYY-MM-DD] |
| 2 | Approved data model | [docs/data/ ...] | 3 to 6 | [approved by whom] |
| 3 | Developer and architecture documents | [docs/Developer/ ...] | 4 to 6 | [reason] |
| 4 | Unsigned product requirements | [paths] | 5 to 6 | [reason] |
| 5 | Code as built — what is, never what should be | [source directories] | 6 | — |
| 6 | Notes, chat exports, drafts | [paths] | — | — |

## Conflict rule

The higher rank wins. Every conflict found becomes a row in the open-decisions map, with both
citations. None is resolved silently.

## Decision owners

| Area | Decides | Escalates to |
| --- | --- | --- |
| [Scope and requirements] | [Role] | [Role] |
| [Data model] | [Role] | [Role] |
