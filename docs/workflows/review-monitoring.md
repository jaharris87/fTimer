> **When to read this:** When monitoring for review output after opening or materially updating a PR. Do not load this during implementation or before the PR exists.

# Review Monitoring

## Monitoring Reviews

After opening or materially updating the PR:

1. Inform the user that you are monitoring for reviews.
2. Poll every 60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. After the trigger workflow completes, watch for a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicating the review will not proceed (e.g., quota exhausted). Note: the connector may also post unrelated comments when PR text contains the word "Codex" — those are not fallback signals; only a response to the trigger itself counts.
5. Once all expected reviews have arrived, respond to every finding.
6. If reviews have not arrived after 10 minutes and no unavailability signal has appeared on the trigger comment, tell the user and ask how to proceed.

## Fallback When Native Codex Review Is Unavailable

Use this fallback only when the label-triggered review path is unavailable or insufficient, for example:

- a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicates the review will not proceed (e.g., quota exhausted) — note that connector comments triggered by PR text containing "Codex" are not this signal
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
- Native Codex review did not reliably follow the previous long-form trigger prompts, so the workflow now uses single-line trigger comments and keeps the detailed versions in a separate long-form prompt library for fallback and non-triggered deep reviews.
- Codex review bodies may ignore prompt instructions about top-level headings.
- A "no findings" outcome may appear as a generic comment or reaction rather than a distinct type-specific review body.
- GitHub does not expose clean provenance from a particular trigger comment to a particular returned review object.

In practice, infer review type from the review contents and the trigger context when the returned wrapper is generic.
