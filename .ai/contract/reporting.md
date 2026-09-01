# Operating Contract — Reporting and Handoff

Load when closing, pausing, or transferring work. Referenced by `.ai/contract/core.md` §9.

## 0. The Persistence Gate

**No final report without persisted state.** A report is a summary of what was written to the
repository, never a substitute for writing it. Anything durable a session produced lands in its
file **before** the final report; work that lives only in the conversation is work the next
session pays for twice — and usually loses.

What the session produced decides where it persists:

| Produced | Persists to |
| --- | --- |
| A change of position, validation result, or next action | `.ai/context/current-state.md` |
| A durable decision | `.ai/memory/decisions/` + one pointer line in the ledger |
| A gap, assumption, or unanswered question | `.ai/memory/open-questions.md` |
| A failed guard, guarantee, or process | `.ai/memory/incidents/` |
| A reusable rule worth keeping | `.ai/memory/lessons/` |
| Work continuing in another session or context | `.ai/memory/handoffs/` + a ledger refresh |
| Validation evidence for the active task | the task's Validation section |

**"Unchanged" is a valid answer, stated — never silent.** A session that produced no durable
fact (a question answered, a read-only analysis with nothing worth keeping) reports
`State: unchanged` with a one-line reason instead of writing files for ceremony's sake.

**If the user forbids writes**, say so in the report: name what would have been persisted and
where, and mark the report itself as the only carrier. A flagged exception is honest; a silent
one converts the conversation into an unindexed source of truth.

`check-state-freshness` reports how far the ledger lags the repository — informational, never
gating, so a pre-v1.12 adoption without a ledger is told, not failed.

## 1. Final Report Format

Use this structure at the end of every completed or interrupted task.

### Summary
The outcome in a few precise sentences. What changed, and what is now true that was not before.

### Files Changed
Each changed file and the purpose of its change. Group trivial changes; never omit a file.

### Validation
The exact commands executed and their observed results. Every skipped check with its reason and
residual risk. See `.ai/contract/validation.md` §7.

### Acceptance Criteria
Each criterion individually, marked `passed`, `failed`, `blocked`, or `n/a`, with its evidence.

### Risks and Limitations
Remaining risks, skipped checks, assumptions made, compatibility concerns, known gaps.

### Decisions
Decisions made during the work, and decisions still requiring user input.

### Next Action
The single most useful next action, or `None` when the work is fully complete.

### State
What was persisted where, per §0 — or `unchanged`, with the reason. This section proves the gate;
a report without it is not final.

## 2. Reporting Rules

- Do not hide uncertainty. Ambiguity reported is cheap; ambiguity concealed is expensive.
- Do not use vague claims — "everything works", "should be fine", "fully tested" — without evidence.
- Do not pad the report with restated requirements or narration of your process.
- State partial completion as partial. Scaling work down is the user's decision, not yours.
- If something was left out, say exactly what and why.

## 3. When to Write a Handoff

Write a handoff to `.ai/memory/handoffs/` when work is unfinished, blocked, interrupted,
transferred to another agent, or expected to continue in a later session.

## 4. Handoff Contents

A handoff must let another agent continue **without rereading the repository or the conversation**:

1. Current objective, and the exact task and plan paths.
2. Work completed, factually.
3. Files changed, with the purpose of each.
4. Validation already performed and its exact observed results.
5. Remaining work in priority order.
6. Blockers and unresolved decisions, with owners.
7. Risks, assumptions, and warnings.
8. The exact next recommended action — a command, a file, or a question.
9. Links to the relevant code, documentation, decisions, lessons, or incidents.

## 5. Handoff Rules

- Keep it concise and factual. It is a continuation record, not a diary.
- Never paste raw conversation history or large logs.
- Never include secrets or speculative claims.
- Never repeat information already available in a linked source — link instead.
- Date it, scope it, and name the task it belongs to.

Template: `templates/handoff-template.md`. Filled example: `examples/handoff-example.md`.

## 6. Communication Standard

- Answer the question that was asked.
- Lead with the conclusion, then the evidence.
- Separate what you verified from what you inferred.
- When you disagree with the requested approach, say so in one or two sentences, then deliver the
  requested work under stated assumptions. The user's reaffirmed decision is final.
