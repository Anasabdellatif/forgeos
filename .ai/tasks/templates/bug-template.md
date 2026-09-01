# Bug: [Title]

## Metadata

- Status: `inbox`
- Severity: `[critical / high / medium / low]`
- Priority: `[critical / high / medium / low]`
- Owner: `[person or agent]`
- Reported: `[YYYY-MM-DD]`
- Environment: `[development / staging / production / other]`
- Related task or incident: `[path or none]`

## Summary

Describe the defect in one precise paragraph.

## Expected Behavior

Describe the authoritative expected behavior.

## Observed Behavior

Describe exactly what happens instead.

## Reproduction

### Preconditions

- [Required state or setup]

### Steps

1. [Step]
2. [Step]
3. [Step]

### Reproduction Result

- Frequency: `[always / intermittent / unknown]`
- First known occurrence: `[date or unknown]`
- Error or symptom: `[exact sanitized output]`

## Evidence

- Logs: `[sanitized path or excerpt]`
- Screenshots: `[path or none]`
- Failing test: `[path or none]`
- Related code: `[paths or unknown]`

## Profile Compliance

Declare what fixing this bug touches. The project's profile decides which of those areas demand a
role's evidence before closure; `finish-task` checks the declaration, not the prose.

- Profile: `[from .ai/context/project.md, or none]`
- Scope tags: `none`

Choose from `security` `data` `release` `product` `architecture` `domain`, or `none`. A bug in a
login path or an upload handler is `security` even when the fix is one line.

- Role evidence:
  - `[role]`: `[what was examined, what was found, where the detail lives]`

Replace that line before closing. **Role evidence must describe what was reviewed and the result;
template placeholders do not satisfy the gate** — see `.ai/tasks/templates/task-template.md`.

## Impact

- Users affected: `[scope]`
- Data impact: `[none / risk / confirmed]`
- Security impact: `[none / suspected / confirmed]`
- Operational impact: `[description]`
- Workaround: `[safe workaround or none]`

## Initial Hypotheses

- [Unconfirmed hypothesis]

## Confirmed Root Cause

[Pending until supported by evidence]

## Scope

### In Scope

- Reproduce and isolate the defect.
- Fix the confirmed root cause.
- Add or update regression coverage when practical.

### Out of Scope

- [Explicit exclusions]

## Acceptance Criteria

- [ ] The defect is reproducible before the fix or otherwise supported by evidence.
- [ ] The confirmed root cause is documented.
- [ ] The expected behavior is restored.
- [ ] Important neighboring behavior is not regressed.
- [ ] Relevant validation passes.
- [ ] Remaining risk and skipped checks are documented.

## Validation Plan

- [Exact reproduction, regression test, and broader checks]

## Resolution

- Fix summary: `[pending]`
- Files changed: `[pending]`
- Commands executed: `[pending]`
- Results: `[pending]`
- Remaining risks: `[pending]`
