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
through `ftimer_openmp_t`; sparse/union hybrid participation reductions remain
deferred to later implementation issues.

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
| Strict MPI+OpenMP rank/lane reductions | Yes, through `ftimer_openmp` | Initialize `ftimer_openmp_t` in an MPI+OpenMP build, using the default captured `MPI_COMM_WORLD` or an explicit `comm=`, stop all timed regions/lanes, then call the strict `mpi_openmp_summary` report family. Descriptor and eligible-lane mismatches fail; sparse/union hybrid participation remains deferred. |

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

`examples/openmp_example.F90` is the reference compatibility example. It
intentionally exercises a worker-thread no-op call and verifies that only the
outer `parallel_region` timer appears in the summary.

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
- reading MPI+OpenMP smoke coverage as proof of sparse/union hybrid rank/lane
  reductions;
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
- initialize it with a keyword `config=` object and, for hybrid runs, a keyword
  `comm=`;
- register timer names in serial context before hot worker use;
- pass timer ids into an explicitly opened timed OpenMP region; and
- run an untimed warm-up region for short hot loops when first-touch allocation
  would otherwise contaminate the measurement; and
- consume `ftimer_openmp_summary_t` local summary/report output or
  `ftimer_mpi_openmp_summary_t` strict hybrid summary/report output instead of
  current `ftimer_summary_t`, `ftimer_mpi_summary_t`, or
  `ftimer_mpi_union_summary_t`.

The lifecycle/configuration, timer catalog, timed-region, and worker
`start_id`/`stop_id` pieces are functional today, along with stopped-run local
OpenMP summaries, strict MPI+OpenMP summaries, and report/CSV output. Sparse
or union hybrid reduction examples should wait
until the corresponding MPI+OpenMP result family lands.

## Future Example Policy

Keep current and future examples separate.

- `examples/openmp_example.F90` remains the compatibility example for
  `FTIMER_USE_OPENMP=ON`.
- Future true OpenMP worker examples should use `ftimer_openmp_t` and should be
  added only when the example can present a complete stopped-run reporting story
  without implying trace/profiler behavior.
- MPI+OpenMP examples should use the strict `ftimer_openmp_t` hybrid summary
  path, not the procedural default instance. Sparse/union hybrid examples
  should wait for the later participation-aware API.
- Future examples should show the id-first worker hot path, explicit timed
  region begin/end, stopped-run summaries, and participation-aware terminology.
- Examples must not imply support for nested OpenMP teams, OpenMP task
  migration, accelerator/device timing, hardware counters, automatic MPI
  barriers, callback event streams from workers, or full profiler behavior.

When future APIs become available, release notes should say which mode was
added, which examples compile on that release, which toolchain matrix validates
the examples, and which non-goals still apply.

## Design References

- API and compatibility direction:
  [`docs/openmp-hybrid-api-design.md`](openmp-hybrid-api-design.md)
- Thread-lane runtime model:
  [`docs/openmp-thread-lane-runtime-design.md`](openmp-thread-lane-runtime-design.md)
- Local OpenMP summary and report model:
  [`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md)
- MPI+OpenMP reduction model:
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md)
- Validation plan:
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md)
