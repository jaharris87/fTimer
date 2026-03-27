## Adoptability Review

You are performing a long-form review as an adoptability reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to determine how difficult this project is for a new, unfamiliar user or contributor to successfully use in practice. Focus on onboarding friction, integration effort, mental-model clarity, and time-to-first-success - not prose polish, code style, or abstract design purity.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **How hard is it for a new user to get from zero to first successful use?**
   Identify the concrete onboarding steps and where they are likely to get stuck.

2. **Is the project's high-level purpose and usage model understandable early enough?**
   Could a new user quickly answer: what this library does, who it is for, what the main usage modes are, and what "correct use" looks like?

3. **How difficult is integration into a real downstream project?**
   Consider build system expectations, dependency assumptions, API discoverability, and whether examples/docs make embedding the library realistic.

4. **What creates the most onboarding friction or cognitive overhead?**
   Identify the biggest sources of confusion, ambiguity, hidden prerequisites, terminology load, or workflow burden.

5. **What is the highest-value change that would most improve practical adoptability?**
   Prefer small, concrete improvements with clear payoff over broad wishlist items.

### What to Look For

- **Time-to-first-success friction**: A new user cannot quickly get a minimal example to build, run, and produce believable output.
- **Unclear entry point**: README or top-level docs do not make it obvious where to start, which API to use first, or what the simplest supported workflow is.
- **Mental-model gap**: The repo explains implementation details or internal structure before explaining the user-facing model.
- **Integration burden**: Realistic downstream use requires non-obvious build flags, module setup, compiler assumptions, MPI/OpenMP knowledge, or repository-local context not surfaced in the user docs.
- **Terminology overload**: Important concepts, modes, or distinctions are introduced without enough grounding for a first-time reader.
- **Discoverability problems**: The most important example, entry point, contract, or limitation exists somewhere in the repo but is not easy for a new user to find.
- **Error-guidance weakness**: Likely setup or usage failures would leave a new user confused rather than pointed toward a fix.
- **Advanced-first presentation**: The project foregrounds maintainer detail, future design, or edge-case complexity before establishing the basic happy path.
- **Install/build ambiguity**: It is unclear what dependencies, compilers, tools, or environment assumptions are required for ordinary use.
- **Example mismatch**: Examples are too idealized, incomplete, stale, or unlike how a downstream user would actually adopt the library.
- **Mode confusion**: Multiple usage paths exist (for example, OOP vs procedural, serial vs MPI, source-tree vs installed use), but the docs do not clearly tell a new user which path to choose first.
- **Hidden contract load**: A new user must infer important constraints from tests, source, issues, or maintainer docs instead of from the obvious user entry points.

### Reviewer Perspective

Evaluate the project from the perspective of a technically capable but unfamiliar engineer who:
- has not seen prior PRs, issues, or design discussions,
- does not already know repo-specific terminology,
- wants to decide quickly whether they can adopt this library,
- and needs a believable path from evaluation to real integration.

Do not assume the reviewer gets credit for already knowing the intended architecture or the maintainer's mental model.

### How to Report

- Start with a concise verdict: **easy to adopt**, **moderately difficult to adopt**, or **hard to adopt**, and justify it briefly.
- Cite the specific file, section, example, command, or workflow step for each finding.
- Classify each finding: **onboarding friction**, **integration friction**, **mental-model gap**, **discoverability problem**, **error-guidance gap**, **example weakness**, or **cognitive-overhead concern**.
- For each finding, explain the concrete failure mode:
  - where a new user would hesitate,
  - what they would likely misunderstand,
  - or what step would fail in practice.
- Prefer findings that materially affect whether a new user could successfully evaluate, integrate, or trust the library.
- Distinguish clearly between:
  - friction that blocks first success,
  - friction that slows integration,
  - and polish-level improvements that are nice but not important.
- Propose concrete improvements, prioritizing the smallest changes with the highest adoptability payoff.
- **Begin your response with "## Adoptability Review" so it is clear which review type this is.**

### Scope Budget

Start from:
1. README.md
2. the simplest user-facing example or test that demonstrates ordinary usage
3. build / install instructions actually relevant to a first-time user
4. touched source files and changed tests if a diff is being reviewed

Expand only when the review question requires it:
- `docs/semantics.md` — only when understanding the user-visible contract is necessary.
- `docs/design.md` — only when the user-facing model depends on architectural intent.
- `CLAUDE.md` or maintainer docs — only if they appear to contain setup facts a normal user is forced to rely on.
- test files — only to determine whether examples and claimed workflows are actually viable.

Do not perform a broad repo sweep. Prefer fewer, high-value findings over exhaustive commentary.
