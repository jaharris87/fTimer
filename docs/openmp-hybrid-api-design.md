> **When to read this:** When designing or implementing true OpenMP or hybrid
> MPI+OpenMP timing beyond the current master-thread-only OpenMP compatibility
> mode.

# Opt-In OpenMP Timing API Design

Issue #238 settles the API and compatibility direction for the OpenMP/hybrid
umbrella in #237. The initial `ftimer_openmp` module added for #268 provides
the public lifecycle/configuration and timer-catalog surface described here, but
it does not implement per-thread stacks, threaded summaries, or hybrid MPI
reductions.

## Decision

True OpenMP worker-thread timing should use a separate, explicit API surface:

- a `ftimer_openmp` module;
- a `type(ftimer_openmp_t)` runtime object;
- a `type(ftimer_openmp_config_t)` configuration object;
- explicit named mode constants in that new module, with the first true timing
  mode defined around OpenMP thread lanes;
- future hybrid summary/result entry points that are separate from today's
  `get_summary()`, `mpi_summary()`, and `mpi_union_summary()` contracts.

The current `ftimer` procedural API, `type(ftimer_t)`, and pure-MPI APIs remain
unchanged. `FTIMER_USE_OPENMP=ON` continues to mean the existing
master-thread-only compatibility mode for those current APIs unless a caller
uses the future OpenMP-specific API. A build option by itself must not silently
turn existing `start`/`stop` calls into true worker-thread timing.

## Current Compatibility Contract

Current `main` remains the source of truth. The #268 API surface is available
for compile-time adoption, while later child issues implement runtime behavior.

- Serial users keep the current `use ftimer` and `type(ftimer_t)` behavior.
- Pure-MPI users keep the current `mpi_f08` `comm=` capture, strict
  `mpi_summary()`, sparse `mpi_union_summary()`, and report/CSV APIs.
- `FTIMER_USE_OPENMP=OFF` does not activate OpenMP guard behavior, even when a
  parent build uses global OpenMP compiler flags.
- `FTIMER_USE_OPENMP=ON` keeps the current master-thread-only carve-out:
  guarded timer operations run on OpenMP thread 0, non-master calls are silent
  no-ops, worker calls leave caller-provided `ierr` values unchanged, and worker
  calls do not create summary entries or callback events.
- `use ftimer_openmp` exposes the opt-in object surface. `init(config=...)`,
  `register_timer`, `lookup_timer`, `reset`, and `finalize` are real lifecycle
  and catalog operations. `begin_parallel_region`, `end_parallel_region`,
  `start_id`, and `stop_id` return `FTIMER_ERR_NOT_IMPLEMENTED` for otherwise
  valid calls until the thread-lane runtime lands; lifecycle/context/id
  validation still reports its own status first.
- The current OpenMP guard tests that defend worker no-op behavior remain
  compatibility tests, not tests to weaken during true OpenMP implementation.

## Recommended API Shape

The first implementation should be object-explicit and keyword-heavy:

The snippets below show the accepted source shape. The `ftimer_openmp` module,
configuration type, object type, timer catalog calls, and timed-region/timing
method names now exist as the initial implementation surface. Worker timing,
OpenMP summaries, and hybrid reductions remain non-functional until later
implementation issues add the thread-lane runtime and result families.

```fortran
! Accepted future worker-timing shape. Summary behavior is implemented later.
use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, &
                         ftimer_openmp_config_t, &
                         ftimer_openmp_parallel_region_t, &
                         ftimer_openmp_t

type(ftimer_openmp_config_t) :: config
type(ftimer_openmp_parallel_region_t) :: region
type(ftimer_openmp_t) :: timer
integer :: cell_update_id, ierr

config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
call timer%init(config=config, ierr=ierr)
call timer%register_timer("cell_update", cell_update_id, ierr=ierr)

call timer%begin_parallel_region(region, ierr=ierr)
!$omp parallel private(ierr)
call timer%start_id(cell_update_id, ierr=ierr)
! worker-thread work
call timer%stop_id(cell_update_id, ierr=ierr)
!$omp end parallel
call timer%end_parallel_region(region, ierr=ierr)

! Later #270:
! call timer%get_openmp_summary(summary, ierr=ierr)
call timer%finalize(ierr=ierr)
```

The proposed `THREAD_LANES` mode means "one strict nesting stack per
participating OpenMP execution lane," initially defined as one lane per OpenMP
thread id in a parallel region. OpenMP task migration, task dependency tracing,
accelerator/device timing, and profiler event streams remain out of scope.
Worker timing should be id-first in the first implementation: names are
registered from serial context, ids are passed into the team, and
`start_id`/`stop_id` run inside an explicitly opened timed parallel-region
epoch. Name-based worker calls may be added only as read-only lookup of
already-registered names, and they must not create catalog entries from inside
the team.

For hybrid runs, the communicator contract should stay keyword-based:

```fortran
! Accepted future hybrid shape. Hybrid summary behavior is implemented later.
call timer%init(config=config, comm=comm, ierr=ierr)
! Later #271/#272:
! call timer%mpi_openmp_summary(summary, ierr=ierr)
```

The future hybrid result type must be separate from `ftimer_mpi_summary_t` and
`ftimer_mpi_union_summary_t` so existing strict and sparse MPI callers do not
silently receive a rank/thread result shape.

## Procedural And OOP Interaction

The true OpenMP timing API should be OOP-first. The current procedural default
instance must never participate in true worker-thread timing.

That rule avoids three compatibility hazards:

- `ftimer_default_instance` is a single saved object with one mutable runtime
  state today.
- Existing procedural calls are often used as low-friction instrumentation in
  serial and pure-MPI code, where users do not expect per-thread allocation,
  synchronization, or a new summary shape.
- A global threaded default would be hard to configure safely for MPI
  communicator ownership, per-thread diagnostics, and report lifecycle.

If procedural helpers are later added for ergonomics, they should live in the
`ftimer_openmp` module and take an explicit `type(ftimer_openmp_t)`
object argument. They must not add a second global default instance and must not
overload the current `ftimer_init`, `ftimer_start`, or `ftimer_stop` names.

## Positional Compatibility Rules

No new OpenMP timing option should be added as a positional argument to current
`ftimer_init` or `type(ftimer_t)%init` signatures. In particular, do not add an
optional integer `openmp_mode` argument to the existing init overloads.

Future OpenMP options should be carried through a config object and passed by
keyword:

- `config=config` for OpenMP timing mode and lane policy;
- `comm=comm` for storing a non-owning MPI communicator handle in MPI-enabled
  builds, ready for later hybrid reduction work;
- `mismatch_mode=...` and `ierr=...` preserved as keyword-friendly arguments.

This keeps removed integer communicator handles, existing mismatch-mode
arguments, and status arguments from becoming ambiguous.

## Threaded Error Policy

The current `ierr` contract remains unchanged for current APIs. For the future
true OpenMP API:

- Examples and tests should pass a thread-private `ierr` in worker timing paths.
- With `ierr` present, each call reports the status observed by that calling
  lane and does not write to stderr.
- With `ierr` absent from a call made inside an OpenMP parallel region, the
  runtime should not emit unordered per-thread stderr diagnostics. It should
  record bounded, thread-safe diagnostics on the timer object and expose an
  aggregate status through later summary/finalize/diagnostic APIs. This applies
  to thread 0 as well when the object-level API rejects an in-parallel call.
- Serial lifecycle calls that observe queued diagnostics may emit one
  deterministic aggregate stderr diagnostic when their own `ierr` is omitted.
- Serial lifecycle calls that clear queued diagnostics with `ierr` present
  report the first queued status through `ierr` without writing stderr.
- Cross-thread start/stop mismatches are lane-local errors by default. A stop on
  a lane whose own stack top does not match must not repair or pop another
  lane's stack.

The exact diagnostic storage, overflow behavior, and aggregate status values
belong to #239 and #240, but the first implementation must not solve stderr
noise by silently treating worker errors as success.

## Callback Policy

Current `type(ftimer_t)%set_callback()` behavior stays unchanged for serial,
pure-MPI, and master-thread-only compatibility mode.

True OpenMP worker timing should not fire callbacks through today's
`ftimer_hook_proc` interface in the first implementation. The current callback
signature has only runtime-local timer/context ids and no rank, thread, lane, or
task identity. Reusing it for worker events would make callback consumers see
plausible but ambiguous event streams.

If callbacks are later approved for true OpenMP timing, they need a separate
callback interface that explicitly carries rank/lane identity, reentrancy rules,
ordering guarantees, and unsupported callback-side mutations.

## Summary And Report Direction

The future OpenMP summary model should distinguish at least these quantities:

- wall-clock envelope time for a region;
- summed lane work time;
- aggregate lane statistics for call counts and inclusive/self time;
- optional per-lane detail only through an explicit detail or diagnostic path;
- lane participation count and missing-lane semantics;
- rank/lane hierarchy for hybrid MPI+OpenMP summaries.

Existing local summaries remain local runtime snapshots. Existing strict MPI
summaries remain rank-only reductions over identical rank timer trees. Existing
sparse MPI summaries remain rank-participation unions. Hybrid rank/lane
summaries need their own result types and report/CSV schemas instead of
overloading those current meanings.

The #240 summary/self-time decision is recorded in
[`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md).

## Migration Story

Existing users do not need to change source code.

- Serial and pure-MPI code can keep current imports and APIs.
- Current OpenMP users who bracket parallel regions as a whole can keep
  `FTIMER_USE_OPENMP=ON` and the existing example pattern.
- Applications that want both compatibility mode and future true worker timing
  should put that choice behind an application-owned instrumentation facade.
- Users adopting true OpenMP timing should explicitly import `ftimer_openmp`,
  construct a `ftimer_openmp_t`, initialize it with `config=...`, and consume
  the new OpenMP/hybrid summary type.

The #242 migration guide keeps `examples/openmp_example.F90` as the
compatibility example. Later implementation issues should add a separate true
OpenMP example only after #239 and #240 define enough runtime and summary
behavior for that example to compile.

## Rejected Alternatives

- **Silently change `ftimer_t` when `FTIMER_USE_OPENMP=ON`.** This would break
  current master-thread-only users and could add overhead or new summary shapes
  to existing serial and pure-MPI instrumentation.
- **Add an optional integer mode to existing `ftimer_init`.** This would
  recreate the positional ambiguity that the current init contract deliberately
  avoids.
- **Use a thread-local procedural default instance.** This would make summary,
  lifecycle, MPI communicator ownership, and callback configuration ambiguous
  for callers that currently rely on one default instance.
- **Protect the existing single stack with locks.** A synchronized shared stack
  still cannot represent independent worker-thread nesting and would serialize
  hot timing paths without producing a credible thread summary model.
- **Record worker starts/stops now and aggregate them into existing summaries.**
  Partial worker timing without a new summary contract would make missing lanes,
  summed work, wall-clock envelope time, and self-time boundaries ambiguous.
- **Reuse the current callback hook for worker events.** The old callback
  interface lacks thread identity and ordering semantics.

## Dependencies On Later Child Issues

- #239 defines the runtime concurrency model in
  [`docs/openmp-thread-lane-runtime-design.md`](openmp-thread-lane-runtime-design.md),
  including per-lane stacks, lane identity, lifecycle boundaries, mismatch
  behavior, merge points, hot-path synchronization bounds, and diagnostic
  storage.
- #240 defines the OpenMP local summary model in
  [`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md),
  including envelope time, summed work, participation, self-time boundaries,
  and CSV/report schemas.
- #241 defines hybrid MPI+OpenMP reductions in
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md)
  without changing current `mpi_summary()` or `mpi_union_summary()` semantics
  by accident.
- #243 records the OpenMP/hybrid validation plan in
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md)
  and adds current MPI+OpenMP compatibility smoke coverage. Later
  implementation issues must add deterministic OpenMP and hybrid tests,
  including compatibility tests that prove current worker no-op behavior still
  holds for existing APIs.
- #242 records the user-facing timing modes and migration guide in
  [`docs/openmp-timing-modes.md`](openmp-timing-modes.md). Later
  implementation issues must add compile-checked true OpenMP and hybrid
  examples only after the corresponding public APIs exist.

## Non-Goals

- Implementing threaded runtime behavior in #238.
- Adding per-thread stacks or thread-local timer objects in this design PR.
- Changing current OpenMP guard semantics or test expectations.
- Changing serial or pure-MPI public API names, signatures, or result types.
- Adding hybrid MPI+OpenMP reductions before the summary model is settled.
- Supporting OpenMP tasks, accelerator/device timing, hardware counters,
  profiler traces, automatic MPI barriers, or stable callback identity.

## Validation For This Design

The original #238 design validation was limited to Markdown and diff checks.
Issue #268 has since added the public `ftimer_openmp` module surface and focused
compile/runtime coverage for the lifecycle and timer-catalog subset through
`ftimer_openmp_api_smoke`, installed-package consumers, and compile-fail probes
for unsupported positional `init` forms. The summary and hybrid-reduction
snippets in this document remain future examples until the later #267 child
issues add those public APIs and their validation.
