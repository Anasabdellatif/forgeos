# Debugging Skill

## Objective

Identify the root cause of a defect using evidence, reproducible observations, and controlled experiments.

## Method

1. Define the expected behavior and the observed failure.
2. Reproduce the issue with the smallest reliable case.
3. Capture exact inputs, environment, errors, logs, and conditions.
4. Form ranked hypotheses based on evidence.
5. Test one hypothesis at a time with the least invasive experiment.
6. Trace the failure across boundaries only when evidence requires it.
7. Fix the root cause rather than masking the symptom.
8. Add or update a regression test when practical.
9. Validate the fix and important neighboring behavior.

## The three rules that carry the method

1. **Reproduce before theorizing.** A hypothesis about a failure you cannot reproduce is a guess.
2. **One hypothesis, one experiment.** Changing three things and seeing green teaches you nothing
   about which one mattered.
3. **Fix the cause, not the symptom.** A `try/catch` around the error, a null guard at the call
   site, or a retry that hides a race are all symptom fixes. **Say so if you ship one.**

## Constraints

- Do not change unrelated code while investigating.
- Do not suppress errors, disable checks, weaken an assertion, or loosen validation to hide the
  failure. See `.ai/rules/testing.md` §6.
- Separate confirmed causes from hypotheses. Label evidence and inference distinctly.
- Do not report "fixed" without observing the failing case now pass **and** the neighbouring
  behavior still pass.
- Record reusable lessons when the cause or diagnostic method will help future work.

## Efficiency Guidance

- Reproduce the smallest failing case before expanding scope.
- Prefer one controlled experiment per hypothesis.
- Stop collecting logs once the root cause is supported by sufficient evidence.

## Output

A confirmed root cause, focused fix, validation evidence, and remaining uncertainty.
