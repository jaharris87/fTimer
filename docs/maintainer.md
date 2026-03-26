> **When to read this:** When you need repository workflow guidance: issue setup, PR opening, review monitoring, findings disposition. Do not load this during routine coding tasks unless the task is in an issue/PR/review/disposition phase.

# Maintainer Guide

This document routes to phase-specific workflow docs. Shared coding-agent context lives in `CLAUDE.md` / `AGENTS.md`; this file is for maintainer workflow, not implementation guidance.

## Repository Bootstrap

- Create the review labels in GitHub:
  - `codex-software-review`
  - `codex-methodology-review`
  - `codex-red-team-review`
- Add a repository secret named `CODEX_TRIGGER_PAT` for the review-trigger workflow.
- Configure a `main` ruleset that:
  - requires pull requests before merge
  - requires CI and lint checks
  - blocks direct pushes and force pushes
  - requires conversation resolution

## Workflow Phases

Use the workflow docs below for phase-specific operating procedures. Load only the phase you need.

- [`docs/workflows/pr-open.md`](workflows/pr-open.md) — opening a PR, applying review labels, review prompt library
- [`docs/workflows/review-monitoring.md`](workflows/review-monitoring.md) — monitoring for review output, fallback review, inspection commands, known limitations
- [`docs/workflows/findings-disposition.md`](workflows/findings-disposition.md) — responding to findings, deferral rules, merge-blocking criteria, PR closeout

## Standard Maintainer Flow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Implement the change on a feature branch.
3. Open a pull request to `main` — see [`pr-open.md`](workflows/pr-open.md).
4. Monitor for review output — see [`review-monitoring.md`](workflows/review-monitoring.md).
5. Address every finding — see [`findings-disposition.md`](workflows/findings-disposition.md).
6. Do not merge while merge-blocking findings remain unresolved.
