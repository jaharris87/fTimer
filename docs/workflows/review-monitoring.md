> **When to read this:** When monitoring for review output after opening or materially updating a PR. Do not load this during implementation or before the PR exists.

# Review Monitoring

## Monitoring Reviews

After opening or materially updating the PR:

1. Inform the user that you are monitoring for reviews.
2. Poll every 30-60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. Remember that the review router now maintains one global Codex review queue per PR. It posts at most one new trigger at a time, waits for the previous trigger comment to lose Codex's `eyes` reaction, and on `synchronize` only reruns roles whose latest-push file delta still matches their routing rules, so inspect the latest trigger comment metadata before deciding a review is stale.
5. Unless the connector explicitly reports that the review will not proceed, give the native `@codex` review flow at least 5 minutes before considering any manual fallback.
6. After the trigger workflow completes, watch for a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicating the review will not proceed (e.g., quota exhausted). Note: the connector may also post unrelated comments when PR text contains the word "Codex" — those are not fallback signals; only a response to the trigger itself counts.
7. Once all expected reviews have arrived, respond to every finding.
8. If reviews have not arrived after 10 minutes and no unavailability signal has appeared on the trigger comment, tell the user and ask how to proceed.

## Fallback When Native Codex Review Is Unavailable

Use this fallback only when the label-triggered review path is unavailable or insufficient, for example:

- a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicates the review will not proceed (e.g., quota exhausted) — note that connector comments triggered by PR text containing "Codex" are not this signal
- the trigger workflow posts successfully but no actual review artifacts arrive after the normal wait window, with at least 5 minutes already given to the native flow
- the GitHub/Codex integration is unavailable

Fallback procedure:

1. Still apply the review labels and monitor for the native review flow first.
2. Request the missing review manually, for example via ChatGPT with GitHub integration.
   Use the matching detailed prompt from `.github/prompts/detailed/` when doing this.
3. Ask the manual review to use the exact heading from the matching detailed prompt for that role.
   Common examples include `## Software Review`, `## Methodology Review`, `## Red Team Review`, `## Docs / Contract Review`, and `## Test Quality Review`.
4. Post the manual review output to the PR as a comment, or post a durable link plus a short summary of the findings.
5. Add a short PR comment explaining why fallback review was used and which review type it covered.
6. Handle every finding exactly as in the normal workflow: agree and fix, disagree with evidence, or defer with reason.
7. Resolve all related review threads or PR discussion threads before merge.

This fallback does not replace required CI, required PR checks, or the normal Codex-label workflow when native Codex review is available.

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
  - `gh run list --workflow "Codex Review Routing and Triggers"`

## Known Limitations Of Native Codex GitHub Reviews

- A passing trigger workflow only proves that labels were reconciled and the `@codex review` comment was posted.
- Trigger comments now include hidden `role`, `sha`, and prompt-version metadata so you can tell whether the latest relevant commit has actually been queued for the expected review.
- The router now enforces a global Codex review lock per PR: if any prior trigger comment still has Codex's `eyes` reaction, no new `@codex review` trigger is posted yet.
- When multiple review labels are active together, the trigger workflow serializes those jobs per PR and spaces subsequent `@codex review` comments by at least 30 seconds to reduce cross-trigger mix-ups.
- Native Codex review did not reliably follow the previous long-form trigger prompts, so the workflow now uses single-line trigger comments and keeps the detailed versions in a separate long-form prompt library for fallback and non-triggered deep reviews.
- Codex review bodies may ignore prompt instructions about top-level headings.
- A "no findings" outcome may appear as a generic comment or reaction rather than a distinct type-specific review body.
- GitHub does not expose clean provenance from a particular trigger comment to a particular returned review object.

In practice, infer review type from the review contents and the trigger context when the returned wrapper is generic.
