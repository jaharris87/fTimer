> **When to read this:** When you need repository workflow guidance: issue setup, PR opening, review monitoring, findings disposition. Do not load this during routine coding tasks unless the task is in an issue/PR/review/disposition stage.

# Maintainer Guide

This document routes maintainers to workflow-specific docs for issue setup, PR
opening, review monitoring, findings disposition, and release closeout. It is
not the first-stop user documentation for building or using fTimer; normal
users should start with [`README.md`](../README.md), examples, and
[`docs/troubleshooting.md`](troubleshooting.md).

Shared coding-agent context lives in `CLAUDE.md` / `AGENTS.md`. Those files
remain available for automation and source-of-truth discipline, but this guide
keeps the human maintainer workflow separate from agent implementation context.

## Repository Bootstrap

- Create the review labels in GitHub from the catalog in `.github/codex-review-roles.json`.
  Automatic labels currently include:
  - `codex-software-review`
  - `codex-methodology-review`
  - `codex-red-team-review`
  - `codex-docs-contract-review`
  - `codex-test-quality-review`
  - `codex-build-portability-review`
  - `codex-api-compat-review`
  - `codex-mpi-safety-review`
  Optional deeper-review labels currently include:
  - `codex-performance-overhead-review`
  - `codex-pragmatic-design-review`
  - `codex-adoptability-review`
  - `codex-completion-audit-review`
- Create or verify the ordinary issue-triage labels used by the issue templates,
  release checklist, and contributor intake docs:
  - `bug`
  - `enhancement`
  - `documentation`
  - `question`
  - `strategic-question`
  - `improvement-issue`
  - `release-audit`
  - `release-blocker`
  - `post-release`
- Add a repository secret named `CODEX_TRIGGER_PAT` for the review-trigger workflow.
- Configure a `main` ruleset that:
  - requires pull requests before merge
  - requires CI, lint, and `Codex Review Coverage`
  - blocks direct pushes and force pushes
  - requires conversation resolution

## CI Dependency Pins

CI treats third-party tooling as part of the release trust boundary. Keep the
download identity and cache identity together when updating pinned tools.

- pFUnit:
  - Update `PFUNIT_VERSION`, `PFUNIT_ARCHIVE_URL`, and `PFUNIT_SHA256` together
    in `.github/workflows/ci.yml`.
  - Compute `PFUNIT_SHA256` from the release archive before merging the update,
    for example by downloading the intended `pFUnit-vX.Y.Z.tar` release asset
    from `Goddard-Fortran-Ecosystem/pFUnit` and running `sha256sum`.
  - The pFUnit cache key includes the runner/compiler/MPI/CMake identity, the
    pFUnit version, and the archive SHA. Changing the toolchain image, version,
    or SHA intentionally creates a new cache lineage.
- fprettify:
  - Update `.github/constraints/lint.txt` when changing the lint tool version.
  - Keep the CI install command constraint-based so `pip` cannot float to a
    newer formatter during release validation.
- Validation:
  - Run `git diff --check` after dependency pin updates.
  - Let GitHub CI exercise the verified pFUnit download path and the pinned
    lint install path before treating a release-boundary PR as ready.

## Workflow Docs

Use the workflow docs below for workflow-specific operating procedures. Load only the workflow you need.

- [`docs/workflows/pr-open.md`](workflows/pr-open.md) — opening a PR,
  applying review labels, review prompt library
- [`docs/workflows/review-monitoring.md`](workflows/review-monitoring.md) —
  monitoring for review output, fallback review, inspection commands, known
  limitations
- [`docs/workflows/findings-disposition.md`](workflows/findings-disposition.md)
  — responding to findings, deferral rules, merge-blocking criteria, PR closeout
- [`docs/release.md`](release.md) — release checklist, validation matrix,
  artifact policy, tag steps, and post-release triage

## Standard Maintainer Flow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Implement the change on a feature branch.
3. Open a pull request to `main` — see [`pr-open.md`](workflows/pr-open.md).
4. Monitor for review output — see [`review-monitoring.md`](workflows/review-monitoring.md).
5. Address every finding — see [`findings-disposition.md`](workflows/findings-disposition.md).
6. Do not merge while merge-blocking findings remain unresolved.

For release preparation, use [`docs/release.md`](release.md) after the relevant
issue/PR workflow is complete. A coding agent may prepare evidence and release
notes, but a human maintainer owns the final tag and GitHub release.
