# Maintainer Guide

This document covers repository operations, pull request workflow, and PR review handling. It is intentionally separate from `CLAUDE.md`, which should stay focused on coding, build/test, architecture, and implementation guidance.

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
5. Apply the review labels required by the diff.
6. Monitor for reviews and handle every finding.
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

The native trigger workflow now posts intentionally condensed single-line `@codex review ...` comments built from `.github/prompts/`. The long-form prompt library lives in `.github/prompts/detailed/`. Keep the top-level prompts reserved for label-triggered native reviews; use the detailed prompts for manual fallback reviews or deeper repo-health reviews that are not wired to PR labels. Do not paste a detailed prompt into a PR unless you are intentionally using the documented fallback flow.

### Detailed Prompt Library

The detailed prompt set in `.github/prompts/detailed/` has two roles:

- long-form fallback versions of the three PR-triggered review types: `software-review.md`, `methodology-review.md`, and `red-team-review.md`
- additional long-horizon review prompts that are not label-triggered by default: `api-compat-review.md`, `build-portability-review.md`, `completion-audit-review.md`, `docs-contract-review.md`, `mpi-safety-review.md`, `performance-overhead-review.md`, `pragmatic-design-review.md`, and `test-quality-review.md`

Use the additional detailed prompts when you want a targeted repository review outside the normal PR trigger flow, for example periodic maintainability checks, pre-release audits, or focused follow-up investigation on a risky area.

- Use `completion-audit-review.md` at issue, phase, or release boundaries to verify that claimed work is actually complete and that docs, tests, and acceptance criteria are honestly closed. Not intended as a routine per-PR review.
- Use `pragmatic-design-review.md` selectively on PRs that introduce new abstractions, wrappers, or architecture. Skip it for narrow bug fixes or documentation-only changes.

### Monitoring Reviews

After opening or materially updating the PR:

1. Inform the user that you are monitoring for reviews.
2. Poll every 60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. Watch PR comments for a message from `chatgpt-codex-connector` indicating quota or usage limit reached — if one appears, switch to the fallback flow immediately without waiting for the full 10-minute window.
5. Once all expected reviews have arrived, respond to every finding.
6. If reviews have not arrived after 10 minutes and no quota message has appeared, tell the user and ask how to proceed.

### Fallback When Native Codex Review Is Unavailable

Use this fallback only when the label-triggered review path is unavailable or insufficient, for example:

- Codex usage quota is exhausted (signalled by a `chatgpt-codex-connector` comment on the PR)
- the trigger workflow posts successfully but no actual review artifacts arrive after the normal wait window
- the GitHub/Codex integration is unavailable

Fallback procedure:

1. Still apply the review labels and monitor for the native review flow first.
2. Request the missing review manually, for example via ChatGPT with GitHub integration.
   Use the matching detailed prompt from `.github/prompts/detailed/` when doing this.
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
- Native Codex review did not reliably follow the previous long-form trigger prompts, so the workflow now uses single-line trigger comments and keeps the detailed versions in a separate long-form prompt library for fallback and non-triggered deep reviews.
- Codex review bodies may ignore prompt instructions about top-level headings.
- A "no findings" outcome may appear as a generic comment or reaction rather than a distinct type-specific review body.
- GitHub does not expose clean provenance from a particular trigger comment to a particular returned review object.

In practice, infer review type from the review contents and the trigger context when the returned wrapper is generic.

## Responding To Findings

For every finding in every review (native, fallback, or manual), post a reply on the PR in one of these categories:

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

### Deferring Findings Properly

A deferred finding is an explicit decision to accept limited risk now and track the work for later. It is not a way to avoid addressing a finding.

**When deferral is appropriate:**

- the finding is real or plausible enough to acknowledge
- it is not merge-blocking under this guide
- fixing it in the current PR would materially expand scope, delay the intended work, or mix unrelated changes
- there is a clear follow-up path

**What deferral requires:**

1. Post a PR disposition reply that states:
   - what the finding is
   - why it is not being fixed in this PR
   - the current risk or impact
   - the intended follow-up
   - whether it is acceptable risk for merge, or release-blocking but not merge-blocking

2. Create a follow-up GitHub issue when the deferred item represents real engineering work. Link both ways:
   - in the PR reply: `Deferred to #NN`
   - in the issue body: `Deferred from PR #NN`

3. Update any parent, umbrella, or audit issue with a disposition line such as:
   - `fixed`
   - `deferred to #NN`
   - `not applicable`
   - `disagreed with evidence`

A deferred finding is not considered handled until the PR disposition comment and any required follow-up issue both exist.

**Rule of thumb for whether to open an issue:**

- If the deferred item requires code, tests, docs, validation, or design work, open an issue.
- If no code, docs, tests, or design work is expected to follow, it can remain in the PR discussion.
- If it came from a formal software, methodology, or red-team review and is a real follow-up item, default to opening an issue.

**Preferred wording.** Avoid vague language like "will do later." Use specific language:

> Deferred to #52 because this PR is scoped to packaging stability; the identified hardening work is real but non-blocking for merge and has explicit acceptance criteria in the follow-up issue.

**Recommended PR disposition template for deferred findings:**

```
Disposition: Deferred to #NN
Finding: <one-line summary of the finding>
Why not fixed in this PR: <scope, sequencing, or mix-of-concerns reason>
Current risk: <low / medium / high — brief rationale>
Merge status: non-merge-blocking / release-blocking but not merge-blocking
Follow-up: #NN — <one-line description of what the issue tracks>
```

**Recommended follow-up issue skeleton:**

```
Deferred from PR #NN
Scope: <what area of the code or design this covers>
Why deferred: <brief reason — scope, sequencing, risk level>
Risk / impact: <what could go wrong if this is not addressed>
Acceptance criteria:
- [ ] <specific, verifiable condition>
- [ ] <specific, verifiable condition>
```

## Merge-Blocking Criteria

Do not merge the PR if any finding classified as:

- bug
- leakage
- silent wrong answer

remains unresolved without either a fix or a disagreement backed by evidence.

Findings classified as `bug`, `leakage`, or `silent wrong answer` should not be deferred for merge unless the maintainer documents why the finding is not valid, not applicable to this PR (e.g., pre-existing and not introduced here), or not applicable in this context.

A deferred finding may remain open at merge time only if it is explicitly recorded as non-merge-blocking and has durable follow-up tracking when required (see [Deferring Findings Properly](#deferring-findings-properly)).

Findings classified as nit, design concern, or methodology concern do not block merge unless the user decides otherwise.

## Closeout To The User

After handling the reviews, report:

- how many findings appeared per review type
- what was fixed
- what was disagreed with and why
- what was deferred, including the linked follow-up issue number for each deferred finding
- whether any deferred item is release-blocking but not merge-blocking
- whether any merge-blocking findings remain
