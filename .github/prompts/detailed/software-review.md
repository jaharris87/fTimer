## Software Review

You are reviewing a pull request as a senior software engineer. Focus on correctness, not style.
Before expanding context, briefly state your initial review scope in one sentence.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **Does this diff change public behavior?** (CLI output, API signatures, default values, file formats)
2. **Are docs, CLI help, and tests updated together with the behavior change?** Flag any that are missing.
3. **Are new defaults safe?** Could they silently produce wrong results for existing users?
4. **Is any behavior silently lossy or imputed?** (e.g., missing data mapped to defaults without warning, fallback paths that hide errors)
5. **Is there an end-to-end test path for the new feature?** Not just unit tests - does something verify the feature works from input to output?

### What to Look For

- **Likely bugs**: Off-by-one errors, wrong variable names, swapped arguments, logic inversions.
- **Missing tests**: New branches or error paths that are not exercised by any test.
- **Edge cases**: What happens with empty input, missing data, duplicate entries, or boundary values?
- **Code smells**: Functions doing too many things, unclear naming, copy-paste duplication.
- **Coupling**: Is the diff too large or does it change too many unrelated things at once?
- **Hidden technical debt**: Workarounds, TODOs, or temporary hacks introduced without tracking.
- **Security**: Command injection, path traversal, or unsafe deserialization.

### How to Report

- Cite the specific file and function for each finding.
- Classify each finding: **bug**, **test gap**, **design concern**, or **nit**.
- Limit nits to at most 3. Do not pad the review with cosmetic observations.
- **Begin your response with "## Software Review" so it is clear which review type this is.**

## Scope Budget

Start with the smallest review context that can answer the review question.

Default review starting point:

1. the PR diff
2. the touched files
3. the relevant tests changed by the PR

Expand beyond that only when necessary.

### Expand context only if the review question requires it

- Read `docs/semantics.md` only when the diff changes runtime behavior, public contract, or edge-case semantics.
- Read `README.md` only when the PR changes user-facing behavior, examples, installation guidance, or public documentation.
- Read `docs/design.md` only when the PR introduces new abstractions, architecture changes, or future-design alignment questions.
- Read workflow docs only when the review specifically concerns issue / PR / disposition process rather than code correctness.

### Anti-churn rules

- Do not perform a broad repo sweep by default.
- Do not reread unchanged files without a specific reason.
- Prefer fewer, more serious findings over speculative exploration.
- If additional context is needed, expand incrementally and state why.

For this review, start from the diff and touched files first; expand only if required to verify correctness, docs parity, or test coverage.