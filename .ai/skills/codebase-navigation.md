# Codebase Navigation Skill

## Objective

Locate the smallest set of files and symbols needed to understand and complete a task.

## Method

1. Read `.ai/context/structure.md` first — the navigation map exists so you do not have to search
   blind. Then the active task, project context, and constraints.
2. Search by domain term, symbol, route, command, configuration key, error message, or test name —
   not by directory browsing.
3. Inspect indexes, manifests, entry points, and the nearby tests before opening large
   implementation files. Tests state intended behavior more compactly than the code does.
4. Trace callers, dependencies, data flow, and public contracts only as far as needed.
5. Confirm the source of truth for the behavior being changed.
6. Record relevant paths in the task or plan when work spans multiple sessions.

## Constraints

- Do not treat examples, generated files, or stale documentation as authoritative without corroboration.
- Do not open unrelated large files merely because they are nearby.
- Do not re-read a file whose content you already have.

## Efficiency Guidance

- Do not scan the entire repository by default.
- Prefer targeted search over broad recursive reading.
- Reuse verified context instead of rereading unchanged files.
- Stop expanding context once enough evidence exists to act safely — not once you have read
  everything. `.ai/contract/core.md` §10: the smallest **sufficient** context, not the smallest
  possible one.

## Output

A concise map of relevant files, responsibilities, dependencies, tests, and unresolved gaps.
