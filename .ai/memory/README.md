# AI Memory

Durable knowledge that should survive across tasks and sessions.

## Categories

- `open-questions.md`: **the single register of assumptions and unanswered questions**, with owners
  and status. One file, not a directory — the point is that there is exactly one place to look.
- `decisions/`: important product or architecture decisions and their rationale.
- `lessons/`: reusable lessons discovered during implementation or debugging.
- `incidents/`: significant operational, security, or production incidents.
- `handoffs/`: concise continuation context for unfinished or transferred work.

An open question that gets answered becomes a decision: close its row and link the record.

## Rules

- Store only durable, reusable information.
- Do not store raw conversations, secrets, temporary notes, or easily rediscovered facts.
- Keep each record concise, dated, scoped, and linked to relevant tasks, plans, code, or documentation.
- Use the templates in `/templates/` when creating records.
