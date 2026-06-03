> **When to read this:** When revisiting whether fTimer should support real
> hybrid MPI+OpenMP timing beyond the current master-thread-only OpenMP
> carve-out.

# Hybrid OpenMP Timing Strategy Decision

Update: #237 reopened the product strategy as an explicit OpenMP/hybrid
umbrella, while preserving this document's compatibility conclusion for current
`main`. The opt-in API direction for that reopened work is recorded in
[`docs/openmp-hybrid-api-design.md`](openmp-hybrid-api-design.md).
The #239 runtime model is recorded in
[`docs/openmp-thread-lane-runtime-design.md`](openmp-thread-lane-runtime-design.md),
and the #240 summary/self-time model is recorded in
[`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md).
The #241 MPI+OpenMP reduction model is recorded in
[`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md).
The #242 user-facing timing modes and migration guide is recorded in
[`docs/openmp-timing-modes.md`](openmp-timing-modes.md).
Issue #268 landed the first public `ftimer_openmp` symbols for the opt-in
surface: configuration, lifecycle, timer registration/lookup, and deferred
timed-region/worker method names. True worker timing, OpenMP summaries, and
MPI+OpenMP reductions remain deferred under the #237 umbrella.

Issue #160 asked whether fTimer should ever support real hybrid MPI+OpenMP
timing beyond the documented master-thread-only carve-out.

## Decision

Real hybrid MPI+OpenMP timing was deferred pending concrete adopter demand under
#160. It was not planned for that release path, but it was not rejected forever.
Issue #237 now reopens the direction as staged work with child issues, starting
with the API and compatibility model in #238 and the initial API symbols in
#268.

The current `FTIMER_USE_OPENMP=ON` behavior stays unchanged: timer operations in
OpenMP parallel regions run only on the master thread, and worker-thread calls
remain silent no-ops. fTimer should not add partial worker-thread timing beyond
the current `ftimer_openmp` lifecycle/catalog surface until later issues define
and implement the runtime, aggregation model, summary data contract, migration
story, and test plan.

No child implementation issues were opened from #160. The later #237 umbrella is
the place that now tracks staged design, API, runtime, summary, reduction,
validation, and docs work before true worker timing code changes continue.

## Evidence

The current implementation and documentation are internally consistent:

- `src/ftimer_core.F90` guards timer lifecycle, start/stop, lookup, reset, clock,
  callback, and scoped-activation entry points with `!$omp master`.
- `tests/test_openmp_guards.pf` verifies that worker-thread calls do not create
  segments, do not increment call counts, do not clear active scoped guards, and
  leave caller-provided `ierr` values unchanged.
- `tests/test_openmp_guards.pf` also verifies that all-thread `start`/`stop`
  calls record only the master-thread invocation and that procedural wrappers
  match the OOP behavior.
- `docs/semantics.md`, `README.md`, and `examples/openmp_example.F90` describe
  OpenMP support as a narrow region-bracketing carve-out, not per-thread timing.
- Issue #120 and PR #131 resolved the previous product-positioning concern by
  narrowing current `main` around disciplined serial and pure-MPI timing.

## Rationale

Hybrid MPI+OpenMP codes are common, but adding credible worker-thread timing is
not a small extension of the existing guard model. The current runtime has one
mutable timer stack per `ftimer_t`, context-sensitive accounting tied to that
stack, callback events tied to runtime-local timer/context ids, and MPI summary
reductions that assume each rank has a well-defined local summary tree.

Real threaded timing would need to answer questions that the current contract
intentionally avoids:

- whether each OpenMP thread owns a private stack, a private timer instance, or
  a synchronized view of one shared instance
- how per-thread inclusive, self, and call-count data are represented in local
  and MPI summaries
- whether default reports show per-thread rows, aggregate rows, or both
- how thread participation and missing-thread data differ from real zero work
- what callback events mean when many threads start the same semantic timer
- how much synchronization overhead is acceptable in hot timing paths
- whether the current worker-thread no-op behavior remains the default for
  compatibility

Without an adopter-backed use case, choosing those answers now would risk a
large API and data-model commitment for a capability outside fTimer's strongest
current niche.

## Historical #160 Reconsideration Gate

The gate below records the condition that kept #160 from starting
implementation. Issue #237 has since reopened the strategy and created child
issues, so the gate is no longer a reason to treat true OpenMP timing as
hypothetical. It remains useful implementation evidence: later child issues
should still collect representative instrumentation patterns, summary
expectations, hybrid reduction needs, overhead constraints, and compatibility
requirements before landing runtime behavior.

Revisit this decision when there is a concrete adopter or benchmark that needs
timing inside OpenMP parallel regions and can state which data they expect. A
useful request should include:

- representative instrumentation patterns inside parallel regions
- expected local summary shape and call-count semantics
- expected MPI aggregation behavior in hybrid runs
- acceptable overhead constraints
- compatibility expectations for existing master-thread-only builds

Until that evidence exists, keep the documented master-thread-only carve-out and
do not infer worker-thread timing from `FTIMER_USE_OPENMP=ON`.

## Historical Potential Work Breakdown

The #237 umbrella now tracks this work explicitly. The original #160 breakdown
below is retained as historical context and maps onto #238 through #243:

- Define the opt-in hybrid API and compatibility model. Decide whether worker
  timing is a new mode, a new timer type, a new summary entry point, or a new
  explicit thread-local instance pattern.
- Define the hybrid summary data contract. Specify per-thread participation,
  aggregation, call-count semantics, self-time rules, and MPI reduction behavior.
  The #240 summary decision is now recorded in
  [`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md).
- Define the MPI+OpenMP reduction contract. Specify strict validation,
  participation-aware union behavior, descriptor identity, active-lane
  preflight, and hybrid report/CSV shape. The #241 reduction decision is now
  recorded in
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md).
- Prototype the core concurrency model. Compare thread-local stacks plus
  post-region aggregation against a synchronized shared instance and document
  the overhead and correctness tradeoffs. The #239 thread-lane runtime decision
  is now recorded in
  [`docs/openmp-thread-lane-runtime-design.md`](openmp-thread-lane-runtime-design.md).
- Add deterministic OpenMP tests. Preserve the existing worker no-op tests for
  the default mode, then add opt-in tests for worker-only timers, all-thread
  timers, nested per-thread stacks, callbacks, and summary generation. The
  #243 validation plan is now recorded in
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md),
  alongside current MPI+OpenMP compatibility smoke coverage.
- Update user-facing docs and examples. Keep the current region-bracketing
  example, explain migration risks, and add clearly separate true OpenMP or
  hybrid examples only after future public APIs exist.

## Non-Goals

This decision does not change current OpenMP semantics, make `ftimer_t`
thread-safe, add thread-local timer instances, reinterpret worker-thread no-ops
as errors, or add a hidden aggregation fallback to existing summaries.

## Validation

Issue #160 is investigation-only. Because this change records a strategic
decision without changing runtime behavior, validation is limited to Markdown
diff checks.
