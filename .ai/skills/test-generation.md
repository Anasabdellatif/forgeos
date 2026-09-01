# Test Generation Skill

## Objective

Create meaningful tests derived from requirements, risk, and observable behavior.

## Method

1. Read the task acceptance criteria and relevant business rules.
2. Identify the unit, integration, contract, system, or security boundary being tested.
3. List important success, failure, boundary, permission, and regression cases.
4. Prioritize cases by impact and likelihood.
5. Reuse repository test conventions, fixtures, and helpers.
6. Keep setup minimal and assertions explicit.
7. Avoid coupling tests to incidental implementation details.
8. Run the tests and inspect the observed results.
9. Document coverage gaps and checks that could not be executed.

## Quality Checks

- Does each test protect a meaningful behavior or risk?
- Will the test fail for the defect or regression it targets?
- Is it deterministic and isolated?
- Are failure messages understandable?
- Does it avoid production data, credentials, and destructive resources?

## Constraints

- Do not weaken, delete, skip, or bypass tests to obtain a passing result.
- Do not use production services, credentials, private data, or destructive resources.
- Do not test incidental implementation details when observable behavior is available.
- Do not assert on a full serialized snapshot unless the snapshot **is** the contract.
- Do not derive expectations by reading the implementation — that reproduces its bugs in the suite.
  Derive from the acceptance criteria, the business rules in `docs/domains/`, and the risk.

## Efficiency Guidance

- Start with the narrowest test that proves the acceptance criterion.
- Reuse existing fixtures and helpers before creating new setup. A test that does not look like its
  neighbours will not be maintained.
- Expand to broader tests only when risk, integration behavior, or confidence requires it.

## Output

Focused tests with clear intent, observed results, and known coverage limitations.
