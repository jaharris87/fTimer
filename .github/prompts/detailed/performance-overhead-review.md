## Performance / Overhead Review

You are performing a long-form review as a performance and instrumentation-overhead reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to identify changes or existing conditions that could make the timer library too expensive, distort measurements, or scale poorly as timer count and nesting depth increase. Focus on hot-path cost and scalability - not premature micro-optimization or code style issues.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.
Before expanding context, briefly state your initial review scope in one sentence.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **Does this diff add cost to the hot path (`start`, `stop`, lookup, summary collection)?**
2. **Could the added overhead materially distort the timings the library is supposed to measure?**
3. **What is the asymptotic behavior of the key operations after this change?**
4. **Does this diff introduce avoidable allocation, copying, formatting, or traversal work in performance-sensitive paths?**
5. **At what timer count, nesting depth, or rank count would this approach become problematic?**

### What to Look For

- **Hot-path work**: Extra formatting, repeated scans, unnecessary copies, or repeated clock calls in `start`/`stop`.
- **Allocation churn**: Repeated allocation/deallocation or array growth on frequently executed paths.
- **Asymptotic regressions**: A path that was O(N) becomes O(N^2), or summary construction repeatedly re-traverses structures.
- **Measurement distortion**: The profiler overhead becomes large enough to perturb the thing being measured.
- **Needless recomputation**: Canonical lists, summaries, or descriptor strings rebuilt more often than needed.
- **Scaling blind spots**: Behavior is fine for tiny tests but likely poor for many timers, deep nesting, or many ranks.

### How to Report

- Cite the specific file and code path for each finding.
- Classify each finding: **hot-path overhead**, **allocation churn**, **scaling risk**, **measurement distortion**, or **performance concern**.
- Explain the practical impact: slower instrumentation, distorted timings, excessive summary time, or poor rank scaling.
- When possible, suggest a lower-overhead alternative or a measurement/benchmark that would clarify whether the concern is real.
- **Begin your response with "## Performance / Overhead Review" so it is clear which review type this is.**

## Scope Budget

Start with the smallest review context that can answer the review question.

Default review starting point:

1. the PR diff
2. the touched files
3. the relevant tests changed by the PR

Expand beyond that only when necessary.

### Expand context only if the review question requires it

- Read `docs/semantics.md` only when the diff changes runtime behavior, public contract, or edge-case semantics.
- Read `README.md` only when the PR changes user-facing behavior, examples, installation guidance, or public documentation.
- Read `docs/design.md` only when the PR introduces new abstractions, architecture changes, or future-design alignment questions.
- Read workflow docs only when the review specifically concerns issue / PR / disposition process rather than code correctness.

### Anti-churn rules

- Do not perform a broad repo sweep by default.
- Do not reread unchanged files without a specific reason.
- Prefer fewer, more serious findings over speculative exploration.
- If additional context is needed, expand incrementally and state why.

For this review, start from hot-path diffs, changed tests, and benchmark-related files. Do not broaden into unrelated repo areas unless overhead claims require it.