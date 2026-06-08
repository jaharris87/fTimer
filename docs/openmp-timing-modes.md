> **When to read this:** When choosing how to instrument OpenMP or
> MPI+OpenMP code, when migrating from the current master-thread-only
> compatibility mode, or when reviewing opt-in OpenMP timing examples.

# OpenMP Timing Modes And Migration Guide

This guide is the user-facing companion to the OpenMP/hybrid strategy under
umbrella issue #237. It explains what exists on current `main`, how the opt-in
OpenMP object differs from the compatibility carve-out, and how examples should
evolve without making today's master-thread-only behavior look accidental.

Current `main` includes opt-in worker-thread timing through `ftimer_openmp`.
Timed-region worker `start_id`/`stop_id` calls are available inside explicit
level-1 OpenMP epochs, and stopped-run local OpenMP summaries, text reports,
and CSV exports are available through the same object. MPI+OpenMP builds also
provide strict rank/lane hybrid summaries, text reports, and CSV exports
through `ftimer_openmp_t`, plus separate sparse union rank/lane hybrid
summaries, text reports, and CSV exports for participation-aware reductions.

The `ftimer_openmp` module is installed in all package modes: serial, MPI,
OpenMP, and MPI+OpenMP. Packages built without `FTIMER_USE_OPENMP=ON` support
its lifecycle/configuration, timer catalog, and serial-lane `start_id`/`stop_id`
entry points from serial context. Timed OpenMP worker regions, OpenMP-region
rejection, and bounded worker diagnostics require an fTimer package built with
`FTIMER_USE_OPENMP=ON`; global OpenMP flags in a downstream application do not
retrofit OpenMP runtime introspection into a non-OpenMP fTimer package.

## Mode Summary

| Mode | Available on current `main` | What it means |
| --- | --- | --- |
| Serial timing | Yes | Use `ftimer` or `ftimer_core` normally. No OpenMP behavior is active. |
| Pure-MPI timing | Yes | Use the current `mpi_f08` `comm=` contract after `MPI_Init` and before `MPI_Finalize`. |
| `FTIMER_USE_OPENMP=OFF` with external OpenMP flags | Yes | fTimer keeps serial/pure-MPI semantics. Global OpenMP compiler flags do not activate the guard carve-out. |
| `FTIMER_USE_OPENMP=ON` compatibility mode | Yes | Current APIs run guarded timer operations only on OpenMP thread 0. Worker-thread calls are silent no-ops. |
| `FTIMER_USE_MPI=ON` plus `FTIMER_USE_OPENMP=ON` | Yes, as compatibility and strict hybrid smoke coverage | MPI and OpenMP package dependencies can coexist. Procedural and `ftimer_core` timing still use the master-thread-only OpenMP behavior. |
| True OpenMP worker timing | Yes, through `ftimer_openmp` | Use `ftimer_openmp_t`, pre-register timer ids, open a timed level-1 region from serial context, call `start_id`/`stop_id` on worker lanes, and consume the separate OpenMP summary/report family. |
| Strict MPI+OpenMP rank/lane reductions | Yes, through `ftimer_openmp` | Initialize `ftimer_openmp_t` in an MPI+OpenMP build, using the default captured `MPI_COMM_WORLD` or an explicit `comm=`, stop all timed regions/lanes, then call the strict `mpi_openmp_summary` report family. Descriptor and eligible-lane mismatches fail. |
| Sparse union MPI+OpenMP rank/lane reductions | Yes, through `ftimer_openmp` | Initialize the same `ftimer_openmp_t` surface, stop all timed regions/lanes, then call the sparse union `mpi_openmp_union_summary` report family. Rank- or lane-conditional descriptors are represented with explicit participation metadata rather than zero-filled contributors. |

## Current Accepted Patterns

Use current OpenMP support to time a parallel region as one wall-clock interval.
Put timing calls in serial context around the `!$omp parallel` region:

```fortran
call ftimer_start("parallel_region", ierr=ierr)
!$omp parallel
! worker work
!$omp end parallel
call ftimer_stop("parallel_region", ierr=ierr)
```

This records one timer call for `parallel_region`. It does not record one call
per worker and does not sum worker-thread work. If the timed region launches
asynchronous accelerator work, synchronize that work before `ftimer_stop` when
the intended measurement is completed device time.

For MPI+OpenMP compatibility builds, keep fTimer inside the MPI lifetime and
still bracket OpenMP work from serial context:

```fortran
call MPI_Init(ierr)
call ftimer_init(comm=MPI_COMM_WORLD, ierr=ierr)

call ftimer_start("rank_parallel_region", ierr=ierr)
!$omp parallel
! rank-local threaded work
!$omp end parallel
call ftimer_stop("rank_parallel_region", ierr=ierr)

call ftimer_mpi_summary(summary, ierr=ierr)
call ftimer_finalize(ierr=ierr)
call MPI_Finalize(ierr)
```

That pattern preserves the current pure-MPI summary contract. The MPI summary
reduces rank-local wall-clock intervals; fTimer does not add automatic MPI
barriers around the measured region.

For true OpenMP worker timing, use the explicit `ftimer_openmp_t` object
surface instead of the procedural default instance. Register timer ids in serial
context, open a timed level-1 region from serial context, and call id-first
worker timers inside the OpenMP region. With the `ftimer_openmp` types imported:

```fortran
type(ftimer_openmp_config_t) :: config
type(ftimer_openmp_parallel_region_t) :: region
type(ftimer_openmp_summary_t) :: summary
type(ftimer_openmp_t) :: timer
integer :: worker_work_id
integer :: ierr

call timer%init(config=config, ierr=ierr)
call timer%register_timer("worker_work", worker_work_id, ierr=ierr)

call timer%begin_parallel_region(region, ierr=ierr)
!$omp parallel private(ierr)
call timer%start_id(worker_work_id, ierr=ierr)
! worker-thread work
call timer%stop_id(worker_work_id, ierr=ierr)
!$omp end parallel
call timer%end_parallel_region(region, ierr=ierr)

call timer%get_openmp_summary(summary, ierr=ierr)
call timer%finalize(ierr=ierr)
```

OpenMP worker summaries are stopped-run merge points: call them only after the
timed region is closed and all lane-local timer stacks are inactive. Lifecycle,
registration, timed-region open/close, and summary/report calls belong in serial
context; only valid `start_id`/`stop_id` worker timing belongs inside the
opened level-1 OpenMP region.

For MPI+OpenMP worker timing, keep MPI initialization and finalization outside
the `ftimer_openmp_t` object lifetime, capture the communicator with
`init(config=..., comm=...)`, and use the same id-first worker hot path:

```fortran
call MPI_Init(ierr)

call timer%init(config=config, comm=MPI_COMM_WORLD, ierr=ierr)
call timer%register_timer("rank_worker_work", rank_worker_work_id, ierr=ierr)

call timer%begin_parallel_region(region, ierr=ierr)
!$omp parallel private(ierr)
call timer%start_id(rank_worker_work_id, ierr=ierr)
! rank-local worker-thread work
call timer%stop_id(rank_worker_work_id, ierr=ierr)
!$omp end parallel
call timer%end_parallel_region(region, ierr=ierr)

call timer%mpi_openmp_summary(strict_summary, ierr=ierr)
call timer%finalize(ierr=ierr)
call MPI_Finalize(ierr)
```

Use the strict `mpi_openmp_summary` family when every rank and eligible lane
participates in the same descriptor set. For rank- or lane-conditional hybrid
timing, keep the same stopped-run lifecycle but consume the sparse union
`mpi_openmp_union_summary` report family so missing contributors are represented
as explicit participation metadata rather than zero-filled timing samples.

These worker-timing snippets are concise user-facing versions of the accepted
source shapes used by the current OpenMP and MPI+OpenMP examples.

`examples/openmp_example.F90` is the reference compatibility example. It
intentionally exercises a worker-thread no-op call and verifies that only the
outer `parallel_region` timer appears in the summary.

`examples/openmp_worker_example.F90` is the reference true OpenMP worker-timing
example. It imports `ftimer_openmp`, constructs `type(ftimer_openmp_t)`,
registers timer ids in serial context, opens one timed level-1 OpenMP region,
uses id-first `start_id`/`stop_id` calls on worker lanes, and then consumes the
stopped-run local OpenMP summary/report/CSV family.

`examples/mpi_openmp_example.F90` is the reference MPI+OpenMP example. It keeps
MPI initialization and finalization outside the fTimer object lifetime, captures
`MPI_COMM_WORLD` through `init(config=..., comm=...)`, uses the same id-first
worker timing pattern, prints a strict `mpi_openmp_summary`, then records a
rank/lane-conditional timer and prints the separate sparse union
`mpi_openmp_union_summary`. fTimer does not add barriers around either timed
region; applications should add synchronization only when it is part of their
intended measurement.

## Patterns To Avoid On Current Main

Do not place current `ftimer_start`/`ftimer_stop` calls inside an OpenMP
parallel region expecting per-thread data:

```fortran
! Misleading on current main: worker calls are no-ops.
!$omp parallel
call ftimer_start("worker_work")
! worker work
call ftimer_stop("worker_work")
!$omp end parallel
```

Under `FTIMER_USE_OPENMP=ON`, only thread 0 contributes to current summaries.
Worker-only timer names do not appear at all, all-thread call counts are
master-only, and caller-provided `ierr` values on worker paths are left
unchanged.

Also avoid:

- scoped guards with block-local finalization inside OpenMP parallel regions;
- summary, report, reset, finalize, clock, or callback operations from inside
  a parallel region;
- expecting strict MPI+OpenMP summaries to relax into sparse/union behavior;
- using global OpenMP compiler flags as a substitute for `FTIMER_USE_OPENMP=ON`.

## Migration Story

Existing serial and pure-MPI users do not need source changes. The current API,
summary types, CSV schemas, and MPI result families remain the stable surface.

Existing OpenMP compatibility users should keep the current region-bracketing
pattern when they want one wall-clock interval for a parallel region. The most
important migration audit is expectation-setting: if an application currently
calls the procedural or `ftimer_core` APIs inside a parallel region and expects
each worker to contribute, that instrumentation is not producing those data.
Move such timing calls outside the parallel region for compatibility timing, or
migrate those hot paths to the explicit `ftimer_openmp_t` worker-timing object.

Applications that need both compatibility mode and true worker timing should
put fTimer calls behind an application-owned instrumentation facade. That keeps
the choice between current `ftimer` calls and `ftimer_openmp` calls in one
application module instead of spreading mode conditionals across scientific
kernels.

The additive migration surface starts with `ftimer_openmp`:

- import the `ftimer_openmp` module explicitly;
- construct a `type(ftimer_openmp_t)` object, not the procedural
  default instance;
- initialize it with a keyword `config=` object; in MPI-enabled builds,
  omitted `comm=` captures `MPI_COMM_WORLD`, while an explicit keyword `comm=`
  captures a caller-owned communicator;
- register timer names in serial context before hot worker use;
- pass timer ids into an explicitly opened timed OpenMP region; and
- for benchmark-only overhead studies, touch the same lane/timer/context
  combinations inside the same opened timed region/epoch before an externally
  measured loop when first-touch allocation should be separated from warmed
  steady-state cost; current fTimer summaries include those warm-up calls
  because no public reserve/warm API exists, and a fresh timed region still
  pays one team-size observation per participating lane; and
- consume `ftimer_openmp_summary_t` local summary/report output or
  `ftimer_mpi_openmp_summary_t` strict hybrid summary/report output, or
  `ftimer_mpi_openmp_union_summary_t` sparse union hybrid summary/report output
  instead of current `ftimer_summary_t`, `ftimer_mpi_summary_t`, or
  `ftimer_mpi_union_summary_t`.

The lifecycle/configuration, timer catalog, timed-region, and worker
`start_id`/`stop_id` pieces are functional today, along with stopped-run local
OpenMP summaries, strict MPI+OpenMP summaries, sparse union MPI+OpenMP
summaries, and report/CSV output.

The worker hot path is optimized for pre-registered ids and warmed contexts.
Internally, `ftimer_openmp_t` uses private catalog and lane-context indexes plus
per-lane timed-region team-size observation. Callers do not need a reserve API
for the current implementation: lane segment storage grows only on lanes that
participate. Benchmark harnesses that need warmed-loop overhead evidence can
touch the same lane/timer/context combinations inside the same opened timed
region before starting their external stopwatch; user-facing fTimer summaries
from that run still include the warm-up data.

## Example Policy

Keep current and future examples separate.

- `examples/openmp_example.F90` remains the compatibility example for
  `FTIMER_USE_OPENMP=ON`.
- `examples/openmp_worker_example.F90` uses `ftimer_openmp_t` and presents a
  complete stopped-run local OpenMP summary/CSV story without implying
  trace/profiler behavior.
- `examples/mpi_openmp_example.F90` uses the strict and sparse union
  `ftimer_openmp_t` hybrid summary paths, not the procedural default instance.
- True OpenMP and hybrid examples show the id-first worker hot path, explicit
  timed-region begin/end, stopped-run summaries, and participation-aware
  terminology.
- Examples must not imply support for nested OpenMP teams, OpenMP task
  migration, accelerator/device timing, hardware counters, automatic MPI
  barriers, callback event streams from workers, or full profiler behavior.

Release notes name the supported examples, the toolchain matrix that validates
them, and the remaining non-goals for the first release containing these APIs.

## Current Contract References

Use the regular documentation surface for current behavior:

- [`README.md`](../README.md) gives user-facing build commands, examples,
  current limitations, and CSV schema notes.
- [`docs/semantics.md`](semantics.md) owns the runtime contract, including
  worker no-op compatibility behavior, `ftimer_openmp_t` lifecycle errors,
  strict MPI+OpenMP descriptor matching, and sparse union participation
  semantics.
- [`docs/installed-api.md`](installed-api.md) owns the stable source-level
  module and public-symbol boundary.
- [`docs/design.md`](design.md) owns the current architecture and CI validation
  reality.

The durable OpenMP/hybrid contract is:

- existing `ftimer` and `ftimer_core` APIs remain master-thread-only when
  `FTIMER_USE_OPENMP=ON`;
- true worker timing is explicit and OOP-first through `ftimer_openmp_t`;
- worker hot paths use pre-registered ids inside an opened level-1 timed
  region;
- local OpenMP, strict MPI+OpenMP, and sparse union MPI+OpenMP summaries are
  stopped-run report families separate from serial local, strict MPI, and
  sparse MPI union summaries;
- strict hybrid reductions require matching descriptors and eligible lane
  participation across ranks; and
- sparse union hybrid reductions use separate APIs with explicit rank/lane
  participation metadata rather than zero-filled absent contributors.
