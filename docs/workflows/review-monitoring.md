> **When to read this:** When monitoring for review output after opening or materially updating a PR. Do not load this during implementation or before the PR exists.

# Review Monitoring

## Monitoring Reviews

After opening the PR, or after manually requesting another review on a later push:

1. Inform the user that you are monitoring for reviews.
2. Poll every 30-60 seconds for up to 10 minutes.
3. Inspect actual review artifacts, not just workflow success.
4. Remember that the review router now maintains one global Codex review queue per PR only for the initial automated review wave. Within that initial wave it advances sequentially inside one workflow run, waits for the PR body to lose Codex's `eyes` reaction before moving to the next automated role, and stands down if a newer plain manual `@codex review` comment appears after the latest automated trigger. Once the PR head moves past that first automated-review SHA, the router stops posting further automated review requests and rerouting, so any later-push review is manual by design.
5. Unless the connector explicitly reports that the review will not proceed, give the native `@codex` review flow at least 5 minutes before considering any manual fallback.
6. After the trigger workflow completes, watch for a `chatgpt-codex-connector` response to the `@codex review` trigger comment indicating the review will not proceed (e.g., quota exhausted). Note: the connector may also post unrelated comments when PR text contains the word "Codex" — those are not fallback signals; only a response to the trigger itself counts.
7. Once all expected reviews have arrived, respond to every finding.
8. Post a coverage marker comment for each active review role on the current head SHA so the `Codex Review Coverage` check can pass.
9. If reviews have not arrived after 10 minutes and no unavailability signal has appeared on the trigger comment, tell the user and ask how to proceed.

## Codex Review Coverage Check

The separate `Codex Review Coverage` workflow is the durable merge gate for review coverage.

It checks two things:

1. the automatic review labels still match the current PR diff
2. every active review role has an explicit coverage marker for the current head SHA

Coverage markers are top-level PR comments that contain a hidden token like one of these:

```text
Codex review coverage: software covered for <HEAD_SHA> via native review.
<!-- codex-review-coverage role=software sha=<HEAD_SHA> status=covered source=native -->

Codex review coverage: docs-contract covered for <HEAD_SHA> via manual fallback.
<!-- codex-review-coverage role=docs-contract sha=<HEAD_SHA> status=covered source=manual-fallback -->

Codex review coverage: red-team waived for <HEAD_SHA> because native review was unavailable and the maintainer accepted the risk.
<!-- codex-review-coverage role=red-team sha=<HEAD_SHA> status=waived source=maintainer-override -->
```

Use `status=covered` when the role was actually satisfied, whether by native review or manual fallback. Use `status=waived` only for an explicit maintainer override with a written reason.
Only trusted repo commenters count for coverage markers: accounts with repo `write`, `maintain`, or `admin` permission, plus any explicitly allowed bot account.

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

Use a connector-first inspection path for routine review reads, and switch to local `gh` only when the connector loses required structure or when you need an explicitly allowed CLI-only workflow such as GraphQL thread state or Actions checks.

Preferred connector-backed reads:

- Trigger comments and general PR comments:
  - GitHub connector / Codex Apps MCP reads such as `github_fetch_issue_comments`, `github_fetch_pr`, and `github_get_pr_info`
- Review objects and inline review findings:
  - GitHub connector / Codex Apps MCP reads such as `github_fetch_pr_comments`, `github_fetch_pr_patch`, `github_fetch_pr_file_patch`, and `github_list_pr_changed_filenames`
- Flat PR metadata or changed-file inspection:
  - GitHub connector / Codex Apps MCP reads such as `github_fetch_pr` and `github_list_pr_changed_filenames`

Use local `gh` only for explicit connector gaps or allowed CLI workflows, and state the reason briefly in the thread when you do:

- Current-branch PR discovery:
  - `gh pr view --json number,url,headRefName,headRepositoryOwner,headRepository`
- GraphQL-only review-thread state or resolution state:
  - `gh api graphql -f query='query { repository(owner:"jaharris87", name:"fTimer") { pullRequest(number: <PR_NUMBER>) { reviewThreads(first: 50) { nodes { id isResolved path } } } } }'`
- Checks and trigger workflow status:
  - `gh pr checks <PR_NUMBER>`
  - `gh run list --workflow "Codex Review Routing and Triggers"`

## Known Limitations Of Native Codex GitHub Reviews

- A passing trigger workflow only proves that labels were reconciled and the `@codex review` comment was posted.
- Trigger comments now include hidden `role`, `sha`, and prompt-version metadata so you can tell whether the latest relevant commit has actually been queued for the expected review.
- Automatic posting is intentionally limited to the initial automated review wave for a given PR head. Once the PR head changes after that first wave begins, the router does not reroute or post more review requests unless a human does so manually.
- Automatic labels are reconciled in both directions against the current PR diff, so stale auto-routed labels are removed when their selectors no longer match.
- `Codex Review Coverage` is the durable status check for review coverage. It fails when the active review labels are out of sync with the current diff or when the current head SHA is missing coverage markers for active roles.
- The role manifest and condensed prompt files are read from the PR base revision rather than from PR-controlled content.
- The router now enforces a global Codex review lock per PR by looking at the PR body's Codex `eyes` reaction. If that reaction is still present, no new `@codex review` trigger is posted yet.
- If the PR contains a newer plain manual `@codex review` comment without the workflow metadata token, the router treats that PR as manually managed and does not post additional automated review requests.
- When multiple review labels are active together, the trigger workflow serializes those jobs per PR, spaces subsequent `@codex review` comments by at least 30 seconds, and waits between them inside the same run.
- Native Codex review did not reliably follow the previous long-form trigger prompts, so the workflow now uses single-line trigger comments and keeps the detailed versions in a separate long-form prompt library for fallback and non-triggered deep reviews.
- Codex review bodies may ignore prompt instructions about top-level headings.
- A "no findings" outcome may appear as a generic comment or reaction rather than a distinct type-specific review body.
- GitHub does not expose clean provenance from a particular trigger comment to a particular returned review object.

In practice, infer review type from the review contents and the trigger context when the returned wrapper is generic.
