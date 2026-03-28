> **When to read this:** When opening a pull request, preparing the PR body, and applying review labels. Do not load this during routine coding before the change is ready for PR.

# Pull Request Opening

## Standard PR Workflow

For every scoped piece of work:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement the change on that feature branch.
4. Open a ready-for-review pull request to `main`. Do not open a draft PR unless the user explicitly asks for one.
5. Let the review router apply automatic labels, then verify the result and add any extra labels the diff still needs.
6. Monitor for reviews and handle every finding.
7. Do not merge while merge-blocking findings remain unresolved.

## Which Labels To Expect Or Add

The review router now auto-applies the automatic Codex labels on PR `opened`, `reopened`, `ready_for_review`, and `synchronize` events using `.github/codex-review-roles.json`.

- Verify that the automatic routing result matches the actual diff.
- If the router missed a needed review, add the label manually and treat that as a signal to tighten the manifest heuristics afterward.
- If the diff warrants a deeper non-routine review, add one of the optional labels from the same catalog.

In practice:

- `codex-software-review` should always be present on a ready-for-review PR.
- Methodology, red-team, docs-contract, test-quality, build-portability, API-compat, and MPI-safety are auto-routed when the diff matches the manifest rules.
- Performance-overhead, pragmatic-design, adoptability, and completion-audit remain opt-in deeper reviews unless you explicitly add their labels.

## Detailed Prompt Library

The native trigger workflow posts single-line `@codex review ...` comments built from `.github/prompts/`. It now routes labels from the manifest, serializes trigger jobs per PR, reruns active reviews for the latest `head.sha`, and keeps subsequent `@codex review` comments at least 30 seconds apart. The authoritative inventory for long-form prompts lives in `.github/prompts/detailed/README.md`, and the authoritative label-routing catalog lives in `.github/codex-review-roles.json`.

Keep the top-level prompts reserved for label-triggered native reviews. Use the detailed prompts for manual fallback reviews or deeper repo-health reviews that are not wired to PR labels by default. Do not paste a detailed prompt into a PR unless you are intentionally using the documented fallback flow.

When you need the available detailed prompt names or their intended usage context, consult `.github/prompts/detailed/README.md` instead of duplicating that inventory here.
