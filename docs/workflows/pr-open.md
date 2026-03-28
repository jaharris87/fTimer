> **When to read this:** When opening a pull request, preparing the PR body, and applying review labels. Do not load this during routine coding before the change is ready for PR.

# Pull Request Opening

## Standard PR Workflow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement the change on that feature branch.
4. Open a ready-for-review pull request to `main`. Do not open a draft PR unless the user explicitly asks for one.
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

The native trigger workflow posts single-line `@codex review ...` comments built from `.github/prompts/`. When multiple review labels are applied close together, the workflow now serializes those trigger jobs per PR and waits to keep subsequent `@codex review` comments at least 30 seconds apart. The authoritative inventory for the long-form prompt library lives in `.github/prompts/detailed/README.md`.

Keep the top-level prompts reserved for label-triggered native reviews. Use the detailed prompts for manual fallback reviews or deeper repo-health reviews that are not wired to PR labels by default. Do not paste a detailed prompt into a PR unless you are intentionally using the documented fallback flow.

When you need the available detailed prompt names or their intended usage context, consult `.github/prompts/detailed/README.md` instead of duplicating that inventory here.
