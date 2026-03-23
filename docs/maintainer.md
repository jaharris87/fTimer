# Maintainer Guide

This document covers repository operations, pull request workflow, and Codex review handling. It is intentionally separate from `CLAUDE.md`, which should stay focused on coding, build/test, architecture, and implementation guidance.

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

## Standard PR Workflow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement the change on that feature branch.
4. Open a pull request to `main`.
5. Apply the Codex review labels required by the diff.
6. Monitor for Codex reviews and handle every finding.
7. Do not merge while merge-blocking findings remain unresolved.

## Codex Review Workflow

This workflow is mandatory for every PR.

### Which Labels To Apply

- Always apply `codex-software-review`.
- Also apply `codex-methodology-review` when changes touch:
  - `src/ftimer_core.F90`
  - `src/ftimer_summary.F90`
  - `src/ftimer_mpi.F90`
  - `docs/semantics.md`
- Also apply `codex-red-team-review` when changes touch:
  - `src/ftimer_core.F90`, especially `start`, `stop`, or `repair_mismatch`
  - `src/ftimer_mpi.F90`

The native trigger workflow now posts intentionally condensed single-line `@codex review ...` comments built from `.github/prompts/`. The preserved detailed prompts live in `.github/prompts/manual/` for auxiliary/manual review use. Do not paste the manual backup prompts into a PR unless you are using the documented fallback flow.

### Monitoring Reviews

After opening or materially updating the PR:

1. Inform the user that you are monitoring for Codex reviews.
2. Poll every 60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. Once all expected reviews have arrived, respond to every finding.
5. If reviews have not arrived after 10 minutes, tell the user and ask how to proceed.

### Fallback When Native Codex Review Is Unavailable

Use this fallback only when the normal label-triggered Codex review path is unavailable or insufficient, for example:

- Codex usage quota is exhausted
- the trigger workflow posts successfully but no actual review artifacts arrive after the normal wait window
- the GitHub/Codex integration is unavailable

Fallback procedure:

1. Still apply the normal Codex review labels and monitor for the native review flow first.
2. Request the missing review manually, for example via ChatGPT with GitHub integration.
   You can reuse the detailed backup prompts from `.github/prompts/manual/` when doing this.
3. Ask the manual review to use the repository review heading convention:
   - `## Software Review`
   - `## Methodology Review`
   - `## Red Team Review`
4. Post the manual review output to the PR as a comment, or post a durable link plus a short summary of the findings.
5. Add a short PR comment explaining why fallback review was used and which review type it covered.
6. Handle every finding exactly as in the normal workflow: agree and fix, disagree with evidence, or defer with reason.
7. Resolve all related review threads or PR discussion threads before merge.

This fallback does not replace required CI, required PR checks, or the normal Codex-label workflow when native Codex review is available.

### How To Inspect What Actually Happened

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
- Native Codex review did not reliably follow the previous long-form trigger prompts, so the workflow now uses single-line trigger comments and keeps the detailed versions only for manual fallback.
- Codex review bodies may ignore prompt instructions about top-level headings.
- A "no findings" outcome may appear as a generic comment or reaction rather than a distinct type-specific review body.
- GitHub does not expose clean provenance from a particular trigger comment to a particular returned review object.

In practice, infer review type from the review contents and the trigger context when the returned wrapper is generic.

## Responding To Findings

For every finding in every Codex review, post a reply on the PR in one of these categories:

- Agree and fix
- Disagree with evidence
- Defer with reason

Every finding must be addressed explicitly.

When responding:

- cite the fix commit when you agree and fix
- cite code/tests/docs when you disagree
- explain scope clearly when you defer
- if the returned review omits a classification, assign one explicitly in your disposition comment using the repo categories below

After replying:

- resolve the review thread
- verify whether any unresolved review threads remain

## Merge-Blocking Criteria

Do not merge the PR if any finding classified as:

- bug
- leakage
- silent wrong answer

remains unresolved without either a fix or a disagreement backed by evidence.

Findings classified as nit, design concern, or methodology concern do not block merge unless the user decides otherwise.

## Closeout To The User

After handling the reviews, report:

- how many findings appeared per review type
- what was fixed
- what was disagreed with and why
- what was deferred
- whether any merge-blocking findings remain
