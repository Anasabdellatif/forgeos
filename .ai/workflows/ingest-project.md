# Project Ingestion Workflow

## Objective

Turn a project's own documents into compact project intelligence an agent can read cheaply — or,
when no governing documents exist, prepare the discovery records a project needs before
implementation. No value a governing document already states is ever asked of the owner, and no
whole specification is ever re-read to find one.

## When It Runs

- Once, before the first implementation slice of an adopted project, and again when a governing
  document is added, replaced, or re-signed.
- When `scripts/validation/check-project-ingestion` reports `NOTE`.
- Never in the source blueprint: it has no product of its own, and the check reports `N/A`.

This is not the discovery interview. `.ai/workflows/discovery.md` defines an undefined project by
asking; this workflow recovers what the repository already answers, and asks only what it does not.

## 1. Classify the project

Look, do not read. List the candidate directories and the files in them — names, types, sizes,
page counts where the file system shows them. Open nothing yet.

| Mode | When | Outputs, in `.ai/product/` |
| --- | --- | --- |
| `PROJECT_WITH_GOVERNING_DOCS` | Authoritative sources exist: a client specification (`docs/Client/`), developer documents (`docs/Developer/`), a data model (`docs/data/`), signed requirements, architecture documents | `authority-map.md` · `source-index.md` · `project-concept.md` · `module-map.md` · `requirement-matrix.md` · `implementation-roadmap.md` · `open-decisions.md` |
| `PROJECT_DISCOVERY_REQUIRED` | No governing document exists, or only notes nobody has agreed to | `project-brief.md` · `stakeholders.md` · `module-map-draft.md` · `questions.md` · `assumptions.md` · `phase-roadmap.md` |

The check guesses from directory names; the authority map decides. A project whose governing
documents live elsewhere writes an authority map naming them, and is in the first mode from then on.

Templates for both sets are in `templates/project-intelligence/`. Copy, then fill — never edit a
template in place.

## 2. Rank the sources

Write the authority map first. It decides every later conflict.

Default authority order, highest first. The project may reorder it; the map records why.

1. Signed or client-approved specifications and contracts
2. Data models and schemas the client or the architecture approved
3. Developer and architecture documents
4. Product requirement documents not yet signed
5. The code as it exists — authoritative for what *is*, never for what *should be*
6. Meeting notes, chat exports, drafts

When two sources disagree, the higher one wins and the conflict is recorded in the open-decisions
map with both citations. Never resolve a conflict silently, and never let the code overrule a
signed specification without a decision record.

## 3. Index before you extract

Write the source index: one row per governing document, each with a stable ID (`S-01`, `S-02`, …),
its path, type, version or date, size or page count, authority rank, and the subjects it covers.
This is the only place a full path is repeated; every later map cites the ID.

**Citation format, used everywhere below:** `S-03 §4.2` or `S-03 p.17` — the source ID plus the
narrowest locator the document allows. A fact with no citation is an assumption, and is labelled as
one.

## 4. Extract — what to take, what to leave

Take, in your own compact words, each with a citation:

- the project's purpose, users, scope, and explicit non-goals → the project concept
- modules, their responsibilities, entities, and dependencies → the module map
- each requirement as one line, with priority and an acceptance hint → the requirement matrix
- phases and their exit criteria → the implementation roadmap
- every gap, contradiction, or unanswered question → open decisions

Leave in the source, and cite instead:

- paragraphs, tables, and screens copied whole
- anything a map can point to rather than restate
- values that change often — the map names where they live

Size limits keep the maps cheap: the project concept stays under 60 lines, a requirement is one
line, and a module entry stays under five lines. A map that grows past 300 lines is split by module,
never truncated (`.ai/rules/documentation.md` §6).

## 5. Record modules

One row per module: its name, a one-sentence responsibility, key entities, what it depends on, the
sources that define it, and its status. Name modules the way the business does, in the documents'
own language — not after a folder layout the code has not built yet.

## 6. Build the requirement matrix

Every requirement gets an ID (`R-001`), one line of text, its module, a priority, the citation that
defines it, an acceptance hint a test could check, and a status: `not started` · `in progress` ·
`done` · `disputed`. A requirement stated in two documents is one row with two citations. A
requirement the sources contradict is `disputed` and has a matching open decision.

The roadmap `forgeos next` reads stays `docs/roadmap.md`. The implementation roadmap feeds its
criteria table; it does not replace it.

## 7. Record open decisions — only after the sources

An open decision means the sources were checked and do not answer. Each one names the sources
consulted, why the question blocks work, the options, the owner who decides, and when the answer is
needed.

**Before any question reaches the owner, search the source index for it.** A value a governing
document already states is extracted, never asked — and a missing value that blocks nothing is
recorded as an assumption, not raised as a blocker.

## 8. Discovery mode

With no governing documents, fill the six discovery records instead:

- **project brief** — problem, users, outcome, scope, non-goals, success measure
- **stakeholders** — roles and decision rights, with no personal data beyond names and roles
- **module map draft** — candidate modules, each with a confidence rating
- **questions** — what only the owner can answer
- **assumptions** — what is being treated as true, and how it will be verified
- **phase roadmap** — phases with exit criteria, discovery and agreement before implementation

Every entry is marked `confirmed` or `assumed`. When the answers harden into agreed documents, place
them under `docs/`, write an authority map, and the project moves to the first mode.

## Token economy

The maps exist so that nobody — human or agent — pays for a whole specification twice.

- **Never copy** a specification, cahier des charges, data model, or screen list into always-loaded
  context. `.ai/context/` points to `.ai/product/`; it never contains it.
- **Maps first.** A later session reads the relevant map, then opens the original only to verify
  the one passage a citation names.
- **No repeated whole-document reads.** A question answered once is answered in a map, with its
  citation.
- **Sources before questions.** No question reaches the owner before the source index was searched.
- **Missing is not blocking.** A value the sources answer is not a blocker, and a value nothing needs
  yet is an assumption.

## Validation

`scripts/validation/check-project-ingestion` reports the mode, the governing directories it found,
and how many of the seven maps or six discovery records exist. It checks presence only, never opens a
document, and never fails — an adopted project without maps is a finding, not a broken build. It
runs as an informational row in `check-all`.

## Not in this slice

- `forgeos ingest` and a slash command — slice 2.
- Gating, so validation fails for a documented project without maps — slice 3, once proven on
  adopters.

Tracked in `docs/roadmap.md` under M-25.
