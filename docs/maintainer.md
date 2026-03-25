> **When to read this**
>
> Read this file when you need repository workflow guidance: issue setup, PR opening, review monitoring, findings disposition, and merge/closeout procedure.
>
> Shared coding-agent context lives in `docs/agent-context.md`; this file is for maintainer workflow, not general implementation guidance.
>
> Do **not** load this by default for routine coding tasks unless the task is specifically in an issue/PR/review/disposition phase.

# Maintainer Guide

This document is the entry point for repository operations and review workflow.

Shared coding-agent context now lives in `docs/agent-context.md`.
Keep this document focused on maintainer workflow rather than implementation guidance.

## What This Guide Covers

Use the workflow documents under `docs/workflows/` for phase-specific operating procedures:

- `docs/workflows/repo-bootstrap.md` — one-time repository setup, labels, branch protections, and review-trigger prerequisites
- `docs/workflows/issue-intake.md` — how to create, scope, and link issues before implementation
- `docs/workflows/pr-open.md` — how to open a PR, apply review labels, and prepare review context
- `docs/workflows/review-monitoring.md` — how to monitor native review, decide when fallback review is needed, and inspect what actually happened
- `docs/workflows/findings-disposition.md` — how to respond to findings, defer work properly, enforce merge-blocking rules, and close out the PR

## Standard Maintainer Flow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Implement the change on a feature branch.
3. Open a pull request to `main`.
4. Apply the required review labels and trigger the expected review flow.
5. Monitor for actual review artifacts, not just workflow success.
6. Address every finding explicitly.
7. Do not merge while merge-blocking findings remain unresolved.

## Routing Rules

- For coding and repository behavior context, use `docs/agent-context.md`.
- For current runtime contract details, use `docs/semantics.md`.
- For future-looking architecture or design intent, use `docs/design.md`.
- For public-facing current-state behavior, use `README.md`.

## Session Discipline For Maintainer Work

Prefer separate sessions or narrowly scoped review passes for distinct phases:

- implementation
- review monitoring
- findings disposition
- post-merge or next-step planning

When moving between phases, carry forward a compact handoff note instead of replaying the full prior conversation.

Use [`docs/templates/session-handoff.md`](templates/session-handoff.md) as the default handoff format between maintainer phases.

This is especially useful when moving between implementation, review monitoring, findings disposition, and post-merge follow-up, because it preserves the minimum durable context needed for the next phase.

## Related Templates

The reusable prompt and handoff templates live under `docs/templates/`.

Use them to keep sessions phase-bounded and to avoid replaying full prior context.

- `docs/templates/prompt-implement-issue.md` — implementation session for a scoped issue
- `docs/templates/prompt-pr-open.md` — PR-opening and packaging session
- `docs/templates/prompt-review-monitoring.md` — review-status checking session
- `docs/templates/prompt-fallback-review.md` — fallback manual review session
- `docs/templates/prompt-findings-disposition.md` — review-findings response and disposition session
- `docs/templates/prompt-task-planning.md` — next-task planning session
- `docs/templates/prompt-milestone-audit.md` — milestone / phase / release audit session
- `docs/templates/session-handoff.md` — end-of-phase handoff note for the next session

Prefer ending each major workflow phase with `docs/templates/session-handoff.md`.
