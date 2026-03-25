> **When to read this**
>
> Read this file only for one-time or infrequent repository setup: labels, secrets, rulesets, and review-trigger prerequisites.
>
> This file is not part of normal day-to-day implementation or PR handling.
>
> Do **not** load this by default during routine coding, review, or disposition work.

# Repository Bootstrap

This document covers one-time or infrequent repository setup for the fTimer workflow.

## Review Labels

Create these GitHub labels:

- `codex-software-review`
- `codex-methodology-review`
- `codex-red-team-review`

These labels define which native review flows should run for a PR.

## Native Review Trigger Prerequisites

Add a repository secret named:

- `CODEX_TRIGGER_PAT`

This is required by the native review-trigger workflow.

## Branch Protection / Ruleset

Configure a `main` ruleset that:

- requires pull requests before merge
- requires CI and lint checks
- blocks direct pushes
- blocks force pushes
- requires conversation resolution

## Prompt Library Expectations

The native short trigger prompts live in:

- `.github/prompts/`

Long-form fallback and targeted review prompts live in:

- `.github/prompts/detailed/`

Repository facts and coding context should not be duplicated in those prompt files unless the review format specifically requires it. Shared coding-agent context belongs in `docs/agent-context.md`.

## Periodic Maintenance Check

Occasionally verify that:

- the review labels still exist
- the trigger workflow still posts the expected `@codex review ...` comments
- the detailed prompt library still matches current review categories
- branch protection still matches intended merge policy

## Related Templates

This workflow usually does not require a dedicated prompt template.

If bootstrap work is being planned as part of a broader maintenance effort, use:

- `docs/templates/prompt-task-planning.md` — to scope the maintenance work
- `docs/templates/session-handoff.md` — to hand off any remaining setup work