# Refactoring Skill

## Objective

Improve internal structure without changing required observable behavior.

## Preconditions

- The current behavior and source of truth are understood.
- Relevant tests or validation exist, or the risk of missing coverage is documented.
- The refactoring is within task scope. Opportunistic refactoring is out of scope by default —
  see `.ai/rules/coding.md` §2.

## Method

1. Name the structural problem and the specific improvement. "It's messy" is not a problem
   statement.
2. Identify behavior that must remain unchanged.
3. Establish targeted tests or baseline validation.
4. Refactor in small reversible steps.
5. Validate after each meaningful step.
6. Remove obsolete code only after verifying it is unused.
7. Review module boundaries, naming, dependencies, and accidental complexity.
8. Update architecture or developer documentation when structural guidance changes.

## Constraints

- Do not combine broad refactoring with unrelated feature work when avoidable.
- Do not introduce abstractions for hypothetical future needs.
- Preserve public contracts unless a separately approved change requires otherwise.
- Stop if behavior changes unexpectedly or validation becomes unreliable.

## Efficiency Guidance

- Refactor along one boundary at a time.
- Prefer mechanical, reviewable edits when behavior must remain unchanged.
- Run narrow validation after each meaningful structural step.

## Output

A clearer structure with equivalent required behavior and supporting evidence.
