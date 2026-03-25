> **When to read this**
>
> Read this file when monitoring native review, deciding whether fallback review is needed, or inspecting what actually happened on a PR.
>
> Use it after a PR has been opened or materially updated.
>
> Do **not** load this by default during implementation unless the task is explicitly in the review-monitoring phase.

# Review Monitoring Workflow

This document covers how to monitor native review, detect failure modes, and decide when fallback review is needed.

## Goal

Do not assume review happened just because a trigger workflow passed.

A passing workflow only proves that the trigger comment was posted.
It does not prove that the expected review artifacts arrived.

## Monitoring Procedure

After opening or materially updating the PR:

1. Inform the user that you are monitoring for reviews.
2. Poll every 60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. Watch for a `chatgpt-codex-connector` response to the trigger comment indicating the review will not proceed.
5. Once all expected reviews arrive, move to findings disposition.
6. If the wait window expires without review artifacts and without an explicit unavailability signal, tell the user and decide whether to use fallback review.

## When Native Review Is Unavailable

Treat native review as unavailable or insufficient when, for example:

- a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicates the review will not proceed
- the trigger workflow succeeds but expected review artifacts do not arrive in the normal wait window
- the GitHub/Codex integration is unavailable
- the native review returned is clearly insufficient for the risk level of the diff

## Fallback Review Policy

Fallback manual review is part of the intended workflow when native review is unavailable or insufficient.

When using fallback review:

- still record that the native path was attempted first
- use the matching detailed prompt from `.github/prompts/detailed/`
- prefer a fresh or narrowly scoped review pass
- start from the PR diff and touched files first
- expand to broader repo context only if the review question requires it

Fallback review may be performed in:

- a fresh session, or
- a review-focused subagent with narrowly scoped context

The key requirement is that fallback review should behave like a fresh reviewer, not merely continue the full implementation context blindly.

## How To Inspect What Actually Happened

Useful commands:

- Trigger comments and general PR comments:
  - `gh pr view <PR_NUMBER> --comments`
  - `gh api repos/jaharris87/fTimer/issues/<PR_NUMBER>/comments`
- Review objects:
  - `gh api repos/jaharris87/fTimer/pulls/<PR_NUMBER>/reviews`
- Inline review findings:
  - `gh api repos/jaharris87/fTimer/pulls/<PR_NUMBER>/comments`
- Review thread state:
  - `gh api graphql -f query='query { repository(owner:"jaharris87", name:"fTimer") { pullRequest(number: <PR_NUMBER>) { reviewThreads(first: 50) { nodes { id isResolved path } } } } }'`
- Checks and trigger workflow status:
  - `gh pr checks <PR_NUMBER>`
  - `gh run list --workflow "Codex Review Triggers"`

## Known Limitations Of Native Codex GitHub Reviews

- A passing trigger workflow only proves that the `@codex review` comment was posted.
- Returned review bodies may ignore some requested formatting.
- A “no findings” outcome may appear as a generic comment or reaction rather than a type-specific review body.
- GitHub does not expose perfect provenance from one trigger comment to one returned review object.

Infer review type from returned content and trigger context when wrapper metadata is ambiguous.