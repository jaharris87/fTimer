> **When to read this**
>
> Read this file when opening a pull request, preparing the PR body, and applying the correct review labels.
>
> Use it at the transition from implementation to review.
>
> Do **not** load this by default during routine coding before the change is ready to be packaged into a PR.

# Pull Request Opening Workflow

This document covers how to open a PR and prepare the correct review path.

## Before Opening the PR

Before opening the PR, confirm:

- the work is linked to an issue
- the change is on a feature branch
- the diff is scoped appropriately
- relevant tests have been run
- docs are updated when behavior changed

## Standard PR Workflow

For each scoped change:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement the change on that feature branch.
4. Open a pull request to `main`.
5. Apply the review labels required by the diff.
6. Monitor for actual review output.
7. Address every finding before merge.

## Required Review Labels

Always apply:

- `codex-software-review`

Also apply `codex-methodology-review` when changes touch:

- `src/ftimer_core.F90`
- `src/ftimer_summary.F90`
- `src/ftimer_mpi.F90`
- `docs/semantics.md`

Also apply `codex-red-team-review` when changes touch:

- `src/ftimer_core.F90`, especially `start`, `stop`, or `repair_mismatch`
- `src/ftimer_mpi.F90`

## PR Body Expectations

A good PR body should include:

- what changed
- why it changed
- what did not change
- tests run
- whether user-facing behavior changed
- any explicit follow-up or risk notes

## Review Prompt Routing

Native short trigger prompts live in `.github/prompts/`.

Detailed fallback or targeted review prompts live in `.github/prompts/detailed/`.

Use the short prompts for label-triggered native review.
Use the detailed prompts for:

- fallback manual review
- targeted risk reviews
- repository-health audits
- pre-release or phase-boundary audits

## Session Discipline

Opening the PR should usually be the end of the implementation phase.

Prefer not to continue into heavy review-monitoring or fallback-review work in the same already-large implementation session unless the change is urgent and the context is still small.