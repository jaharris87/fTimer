# Detailed Review Prompts

This directory stores the long-form review prompt library.

- `.github/prompts/*.md` remains the condensed prompt set used by the native label-triggered Codex PR workflow.
- `software-review.md`, `methodology-review.md`, and `red-team-review.md` are the detailed fallback versions of those PR-triggered reviews.
- `api-compat-review.md`, `build-portability-review.md`, `completion-audit-review.md`, `docs-contract-review.md`, `mpi-safety-review.md`, `performance-overhead-review.md`, `pragmatic-design-review.md`, and `test-quality-review.md` are additional deep-review prompts for longer-horizon repository reviews that are not wired to PR labels by default.
  - Use `completion-audit-review.md` at issue, phase, or release boundaries to verify that claimed work is actually complete and that docs, tests, and acceptance criteria are honestly closed.
  - Use `pragmatic-design-review.md` selectively on PRs that introduce new abstractions, wrappers, or architecture to catch unnecessary complexity before it accumulates.
