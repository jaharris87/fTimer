# Codex Review Bootstrap

This repository uses label-triggered Codex reviews on pull requests. The trigger workflow posts `@codex review` comments from the repository owner account using `CODEX_TRIGGER_PAT`.

## Prerequisites

- Labels:
  - `codex-software-review`
  - `codex-methodology-review`
  - `codex-red-team-review`
- Repository secret:
  - `CODEX_TRIGGER_PAT` with `pull-requests:write`
- `main` ruleset:
  - require pull requests
  - require CI and lint
  - block direct pushes and force pushes
  - require conversation resolution

## Current Limitations

Observed behavior of native Codex GitHub reviews:

- A successful trigger workflow only proves that the `@codex review` comment was posted.
- The returned review body may ignore prompt instructions about top-level headings or other formatting.
- A "no findings" outcome may not leave a distinct visible review body.
- GitHub does not expose a clean mapping from a specific trigger comment to a specific review object.

Because of that, this repo uses **sequential review triggering** instead of posting multiple review requests in parallel.

## Sequential Review Process

1. Open the PR and apply only `codex-software-review`.
2. Wait for the trigger comment and the actual Codex review output.
3. Respond to findings, fix or disposition them, and resolve the review threads.
4. Remove `codex-software-review`.
5. If needed, apply only `codex-methodology-review` and repeat.
6. If needed, apply only `codex-red-team-review` and repeat.

Recommended order:

1. `codex-software-review`
2. `codex-methodology-review`
3. `codex-red-team-review`

Keep exactly one Codex review label active on the PR at a time.

## Investigation Commands

These commands are the current best way to inspect what actually happened:

- Trigger comments:
  - `gh api repos/jaharris87/fTimer/issues/<PR_NUMBER>/comments`
- Review objects:
  - `gh api repos/jaharris87/fTimer/pulls/<PR_NUMBER>/reviews`
- Inline review comments:
  - `gh api repos/jaharris87/fTimer/pulls/<PR_NUMBER>/comments`
- Review thread state:
  - `gh api graphql -f query='query { repository(owner:"jaharris87", name:"fTimer") { pullRequest(number: <PR_NUMBER>) { reviewThreads(first: 50) { nodes { id isResolved path } } } } }'`
- Trigger workflow runs:
  - `gh run list --workflow "Codex Review Triggers"`
- CI/check status:
  - `gh pr checks <PR_NUMBER>`

Treat the workflow run as "trigger posted", not "review completed".
