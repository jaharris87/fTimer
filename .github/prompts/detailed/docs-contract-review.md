## Docs / Contract Review

You are performing a long-form review as a documentation and contract reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to ensure the repo clearly distinguishes current implemented behavior from future design intent, and that all user-facing and maintainer-facing docs match the code. Focus on truthfulness, consistency, and contract clarity - not prose polish.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **What does `main` guarantee after this diff?** Is that stated clearly and correctly in the docs?
2. **Do any docs describe deferred or future behavior as if it already exists?**
3. **Are README, CLAUDE.md, maintainer docs, examples, and TODO.md mutually consistent after this change?**
4. **Are current-state behavior and target design clearly separated?**
5. **Would a new contributor or coding agent be likely to misunderstand what is implemented today? If so, where?**

### What to Look For

- **Present-tense drift**: Docs say "provides" or "supports" something that is still deferred.
- **Current-vs-target confusion**: Design docs are written like current runtime contracts, or current behavior is underspecified.
- **Example drift**: Example usage or output no longer matches actual code behavior.
- **Workflow drift**: CLAUDE.md, maintainer docs, PR expectations, or prompt guidance disagree with the real repo process.
- **TODO drift**: Completed work is not checked off, or future work has already partially landed without the docs acknowledging it.
- **Terminology inconsistency**: Same concept named differently across code and docs in a way that confuses contributors.

### How to Report

- Cite the specific file and statement for each finding.
- Classify each finding: **contract drift**, **docs mismatch**, **workflow mismatch**, **example drift**, or **clarity concern**.
- Explain the concrete misunderstanding a user, maintainer, or coding agent would likely have.
- Prefer findings that would lead to wrong implementation decisions, wrong usage, or incorrect expectations.
- **Begin your response with "## Docs / Contract Review" so it is clear which review type this is.**

### Scope Budget

Start from: (1) PR diff, (2) touched source files, (3) changed tests.
Expand only when the review question requires it:
- `docs/semantics.md` — only when the diff changes runtime behavior or contract.
- `README.md` — only when user-facing behavior or docs may need updates.
- `docs/design.md` — only for architectural or design-alignment questions.
Do not perform a broad repo sweep. Prefer fewer, serious findings over speculative exploration.
