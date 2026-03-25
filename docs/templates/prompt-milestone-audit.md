Run a completion audit for <issue / phase / release milestone>.

Start with:
1. the parent issue / milestone / phase definition
2. the relevant PRs or diffs
3. changed tests
4. changed docs
5. the matching detailed audit prompt

Task:
- Verify that claimed work is actually complete
- Check that tests/docs/acceptance criteria line up with reality
- Identify honest closeout status and missing items

Working rules:
- Start from the claim set and changed artifacts.
- Expand only when needed to verify a specific completion claim.
- Prefer concrete gaps over generic suggestions.

Deliverables:
- audit report
- explicit complete / incomplete items
- recommended follow-up issues if needed