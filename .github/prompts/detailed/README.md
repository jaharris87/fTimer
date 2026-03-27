# Detailed Review Prompts

This directory is the authoritative inventory for the long-form review prompt library.

- `.github/prompts/*.md` remains the condensed prompt set used by the native label-triggered Codex PR workflow.
- Keep the top-level prompts reserved for label-triggered native reviews.
- Use the detailed prompts in this directory for manual fallback reviews or deeper repository-health reviews that are not wired to PR labels by default.
- Do not paste a detailed prompt into a PR unless you are intentionally using the documented fallback flow.

## Prompt Catalog

### Fallback versions of the PR-triggered reviews

- `software-review.md` — detailed fallback version of the `codex-software-review` PR review.
- `methodology-review.md` — detailed fallback version of the `codex-methodology-review` PR review.
- `red-team-review.md` — detailed fallback version of the `codex-red-team-review` PR review.

### Additional detailed reviews

- `adoptability-review.md` — targeted review for onboarding friction, downstream integration effort, and time-to-first-success for new users and contributors.
- `api-compat-review.md` — targeted review for API stability, user-facing compatibility, and upgrade risk.
- `build-portability-review.md` — targeted review for build behavior, toolchain assumptions, and portability regressions.
- `completion-audit-review.md` — use at issue, phase, or release boundaries to verify that claimed work is actually complete and that docs, tests, and acceptance criteria are honestly closed. Not intended as a routine per-PR review.
- `docs-contract-review.md` — targeted review for documentation accuracy and implementation-contract drift.
- `mpi-safety-review.md` — targeted review for MPI collectives, rank consistency, and distributed-summary safety.
- `performance-overhead-review.md` — targeted review for overhead, hot-path cost, and unintended performance regressions.
- `pragmatic-design-review.md` — use selectively on PRs that introduce new abstractions, wrappers, or architecture; skip it for narrow bug fixes or documentation-only changes.
- `test-quality-review.md` — targeted review for whether tests really exercise the claimed behavior and guard against regressions.
