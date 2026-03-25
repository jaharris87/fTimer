Perform a fallback <software / methodology / red-team / other> review for PR #<NN>.

Start with the smallest review scope:
1. the PR diff
2. the touched files
3. the changed tests
4. the matching review prompt from .github/prompts/detailed/

Expand only if needed:
- docs/semantics.md only if behavior or contract details matter
- README.md only if user-facing behavior/docs changed
- docs/design.md only if architecture/design proportionality is part of the review question
- workflow docs only if the review question is about process rather than code

Working rules:
- State the initial review scope in one sentence.
- Do not do a broad repo sweep by default.
- Prefer fewer, higher-confidence findings.
- Anchor findings in the diff and specific code locations.

Deliverables:
- review report in the expected heading format
- explicit findings or explicit “no findings”
- session handoff using docs/templates/session-handoff.md if more follow-up is expected

Stop condition:
- Stop after the review report is complete.
- Do not start fixing findings in this same pass unless explicitly requested.