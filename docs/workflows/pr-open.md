> **When to read this:** When opening a pull request, preparing the PR body, and applying review labels. Do not load this during routine coding before the change is ready for PR.

# Pull Request Opening

## Standard PR Workflow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement the change on that feature branch.
4. Open a pull request to `main`.
5. Apply the review labels required by the diff.
6. Monitor for reviews and handle every finding.
7. Do not merge while merge-blocking findings remain unresolved.

## Which Labels To Apply

- Always apply `codex-software-review`.
- Also apply `codex-methodology-review` when changes touch:
  - `src/ftimer_core.F90`
  - `src/ftimer_summary.F90`
  - `src/ftimer_mpi.F90`
  - `docs/semantics.md`
- Also apply `codex-red-team-review` when changes touch:
  - `src/ftimer_core.F90`, especially `start`, `stop`, or `repair_mismatch`
  - `src/ftimer_mpi.F90`

## Detailed Prompt Library

The native trigger workflow posts single-line `@codex review ...` comments built from `.github/prompts/`. The long-form prompt library lives in `.github/prompts/detailed/`. Keep the top-level prompts reserved for label-triggered native reviews; use the detailed prompts for manual fallback reviews or deeper repo-health reviews that are not wired to PR labels. Do not paste a detailed prompt into a PR unless you are intentionally using the documented fallback flow.

The detailed prompt set has two roles:

- long-form fallback versions of the three PR-triggered review types: `software-review.md`, `methodology-review.md`, and `red-team-review.md`
- additional long-horizon review prompts that are not label-triggered by default: `api-compat-review.md`, `build-portability-review.md`, `completion-audit-review.md`, `docs-contract-review.md`, `mpi-safety-review.md`, `performance-overhead-review.md`, `pragmatic-design-review.md`, and `test-quality-review.md`

Use the additional detailed prompts for targeted repository reviews outside the normal PR trigger flow, such as periodic maintainability checks, pre-release audits, or focused follow-up investigation on a risky area.

- Use `completion-audit-review.md` at issue, phase, or release boundaries to verify that claimed work is actually complete and that docs, tests, and acceptance criteria are honestly closed. Not intended as a routine per-PR review.
- Use `pragmatic-design-review.md` selectively on PRs that introduce new abstractions, wrappers, or architecture. Skip it for narrow bug fixes or documentation-only changes.
