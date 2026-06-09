# fTimer

fTimer is a lightweight, correctness-first wall-clock timing library for modern Fortran. Current `main` is positioned first for disciplined serial and pure-MPI codes that need hierarchical timers, predictable accounting, and summaries you can inspect programmatically instead of scraping from ad hoc text output.

> Current product position: fTimer's core supported stories are serial timing and pure-MPI timing. `FTIMER_USE_OPENMP=ON` keeps the existing procedural and `ftimer_core` APIs on a master-thread-only carve-out, while `ftimer_openmp_t` provides an explicit opt-in serial-lane and level-1 OpenMP worker timing runtime with stopped-run local OpenMP summaries, text reports, CSV output, strict MPI+OpenMP rank/lane summaries, and sparse MPI+OpenMP union summaries over its captured MPI communicator. MPI+OpenMP builds default that communicator to `MPI_COMM_WORLD` unless `comm=` is supplied at init. The callback hook is a lightweight intra-run event hook, not a stable external-profiler integration contract.

For a first release, the focus is a small, dependable core:

- strict, stack-based start/stop timing by default
- context-sensitive accounting for the same timer name under different parents
- inclusive and self time in structured summaries with explicit tree linkage
- small procedural and explicit OOP scoped guards for lexical blocks with early exits
- procedural wrappers and an OOP core API
- optional MPI global summaries plus first-class strict text/CSV and sparse text/CSV report output
- an explicit `ftimer_openmp_t` runtime for id-first serial-lane and level-1 OpenMP worker timing
- strict MPI+OpenMP rank/lane summaries, reports, and CSV output through `ftimer_openmp_t`
- sparse MPI+OpenMP union summaries, reports, and CSV output with explicit rank/lane participation through `ftimer_openmp_t`
- an installable CMake package for downstream projects

## Why Use fTimer

fTimer fits best when you want timing behavior you can trust:

- nested timers are treated as a real hierarchy, not a flat label list
- mismatch handling is explicit and configurable (`strict`, `warn`, `repair`)
- summaries are available as data first (`get_summary()`), with text formatting layered on top
- stable CSV export is available for dashboards, CI comparisons, plotting, and archives
- local summaries are live snapshots: active timers are included explicitly and marked in the data model/report output
- local summary entries retain formatter-friendly preorder `name`/`depth` data and also expose explicit `node_id`/`parent_id` tree links
- local summaries expose context-cardinality diagnostics so callers can spot one timer name accumulating many parent-stack contexts
- pure-MPI reductions return a distinct `ftimer_mpi_summary_t` with globally meaningful fields on every participating rank
- rank-conditional MPI reductions and reports are available through opt-in sparse/union APIs and `ftimer_mpi_union_summary_t`
- an injectable clock supports deterministic tests and controlled benchmarking
- optional callback hooks let in-process code observe normal timer start/stop events during a run

If you need a tiny serial timing helper, you can use fTimer that way. If you need structured local summaries, opt-in pure-MPI reductions, and a clear error contract, that is where the library is strongest.

## Supported Workflows

fTimer currently supports these usage paths:

- Serial timing with local summaries plus formatted text and CSV reports
- Pure-MPI builds on the validated `mpi_f08` path that are used after `MPI_Init` and before `MPI_Finalize`, use `MPI_Wtime()`, produce global MPI summaries on every participating rank, and can emit strict communicator-level text/CSV reports or opt-in sparse union text/CSV reports
- OpenMP compatibility guards for timing a parallel region as a whole through the existing APIs
- Explicit opt-in OpenMP worker timing through `ftimer_openmp_t`, with local OpenMP summaries/reports plus strict and sparse union MPI+OpenMP hybrid summaries/reports/CSV over `MPI_COMM_WORLD` by default in MPI builds, or over an explicit `comm=` when supplied
- Downstream consumption through `find_package(fTimer CONFIG REQUIRED)`
- Application-owned instrumentation facades that can select either the real fTimer implementation or a dependency-free no-op implementation at build time

Choose the smallest mode that matches the measurement you need. Use serial
timing for one process, pure MPI for rank-local intervals reduced across a
communicator, OpenMP compatibility mode when one wall-clock timer should bracket
an entire parallel region, true OpenMP worker timing when per-lane participation
matters inside one level-1 team, strict MPI+OpenMP when all ranks and lanes must
share the same descriptor tree, and sparse union MPI+OpenMP when rank- or
lane-conditional work should be represented with explicit participation metadata.

### First-Hour Timing Mode Chooser

Start with the row that matches the measurement you want, then move to a more
specialized mode only when the participation pattern requires it.

| Measurement goal | Use this mode | First API or report family | Caveat to keep visible |
| --- | --- | --- | --- |
| One process, one thread, or rank-local data before any MPI reduction | Serial/local timing through `ftimer` or `ftimer_core` | `get_summary()`, `print_summary()`, `write_summary_csv()` | Local summaries are live snapshots. Active timers are included and marked; stop all timers first for a final report. |
| Same timer tree on every MPI rank | Strict pure-MPI timing | `mpi_summary()`, `print_mpi_summary()`, `write_mpi_summary_csv()` | fTimer reduces rank-local intervals and does not add barriers. Descriptor mismatches are errors. |
| Rank-conditional pure-MPI timers | Sparse pure-MPI union timing | `mpi_union_summary()`, `print_mpi_union_summary()`, `write_mpi_union_summary_csv()` | Missing ranks are explicit nonparticipants, not zero-time contributors. |
| One wall-clock interval around an OpenMP parallel region | OpenMP compatibility timing with current `ftimer` / `ftimer_core` calls outside the parallel region | Local summaries, or strict/sparse pure-MPI summaries in MPI builds | Worker-thread calls through these existing APIs are silent no-ops; this does not produce per-worker data. |
| Per-lane OpenMP worker participation inside one level-1 team | Explicit worker timing through `ftimer_openmp_t` | `get_openmp_summary()`, `print_openmp_summary()`, `write_openmp_summary_csv()` | OpenMP worker summaries are stopped-run merge points. Close the timed region and stop all lane stacks first. |
| Same worker timer tree on every MPI rank and eligible lane | Strict MPI+OpenMP worker timing through `ftimer_openmp_t` | `mpi_openmp_summary()`, `print_mpi_openmp_summary()`, `write_mpi_openmp_summary_csv()` | These collective stopped-run APIs require matching rank/lane descriptors and eligible-lane participation. |
| Rank- or lane-conditional MPI+OpenMP worker timers | Sparse MPI+OpenMP union timing through `ftimer_openmp_t` | `mpi_openmp_union_summary()`, `print_mpi_openmp_union_summary()`, `write_mpi_openmp_union_summary_csv()` | Missing ranks and lanes are explicit participation metadata, not zero-filled samples. |

CSV schemas follow the same mode choice: local/strict MPI share one v2 family,
while sparse MPI union, local OpenMP, strict MPI+OpenMP, and sparse
MPI+OpenMP union each use dedicated schemas that are not append-compatible with
one another. For the full OpenMP and hybrid lifecycle, see
[`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md).

Important limitations are documented later in this README. The short version is that serial and pure-MPI are the core supported stories on current `main`; OpenMP has a legacy master-thread-only compatibility path plus the explicit `ftimer_openmp_t` worker-timing object, local stopped-run summaries, strict MPI+OpenMP rank/lane reductions, and separate sparse union MPI+OpenMP rank/lane reductions.

## Operational Support Matrix

Support tiers mean:

- **Core validated**: release-critical paths covered by CI smoke, install, and
  behavior checks where the required toolchain is available.
- **Supported advanced**: validated feature paths with a narrower runtime or
  toolchain contract than the serial and pure-MPI core.
- **Plausible but unvalidated**: paths that may work from the implementation
  design, but are not part of release validation today.
- **Experimental/deferred**: future ecosystem or integration work with no
  current support commitment.
- **Unsupported**: known out-of-contract paths, removed interfaces, or
  combinations intentionally rejected by configure checks.

| Area | Current support tier |
| --- | --- |
| Serial library, smoke tests, examples, and installed consumer | **Core validated** with GNU Fortran and LLVM Flang. Other modern Fortran compilers are **plausible but unvalidated** until a release issue adds direct automation. |
| Serial pFUnit behavior suite | **Core validated** with GNU Fortran and a matching pFUnit installation. LLVM Flang pFUnit and other compiler/pFUnit combinations are **plausible but unvalidated**. |
| Pure MPI | **Core validated** for GNU Fortran MPI wrapper compilers with OpenMPI and MPICH, using `mpi_f08`, after `MPI_Init` and before `MPI_Finalize`. OpenMPI and MPICH smoke/install-consumer paths are validated; MPI pFUnit coverage is validated where matching pFUnit is available. Legacy `mpif.h`, integer communicator handles, and MPI use outside the MPI lifetime are **unsupported**. |
| OpenMP compatibility through `ftimer` / `ftimer_core` | **Supported advanced** with GNU Fortran pFUnit guard coverage and LLVM Flang smoke/example coverage. The contract is master-thread-only; worker-thread calls through these existing APIs are silent no-ops. |
| Explicit `ftimer_openmp_t` worker timing | **Supported advanced** with GNU Fortran and LLVM Flang OpenMP smoke/example coverage. Use this object API for serial-lane and level-1 worker timing; active-region rejection and queued diagnostics are part of this path, not the legacy worker no-op carve-out. |
| MPI+OpenMP hybrid summaries, reports, CSV, and installed consumer | **Supported advanced** today for OpenMPI wrapper builds with GNU Fortran and OpenMP, with focused MPICH wrapper smoke/install-consumer evidence recorded in the release ledger. Other MPI/compiler/OpenMP runtime combinations are **plausible but unvalidated** until separate release evidence promotes them. |
| Installed CMake package and `.mod` artifacts | **Core validated** for matching compiler, toolchain, and feature mode. Installed Fortran `.mod` files are compiler/toolchain/mode specific; cross-compiler or cross-mode reuse is **unsupported**. |
| FPM/package-manager installs, profiler backends, hardware counters, traces, dashboards, accelerator timelines | **Experimental/deferred**. These are not part of the current release support claim. |

For failure-oriented guidance, see
[`docs/troubleshooting.md`](docs/troubleshooting.md). For the architecture,
validation context, and claim evidence behind the matrix, see
[`docs/design.md`](docs/design.md) and
[`docs/release-evidence.md`](docs/release-evidence.md).
For installed package stability details, see
[`docs/installed-api.md`](docs/installed-api.md).

## Quick Start

```fortran
program quick_start
   use ftimer, only: ftimer_finalize, ftimer_get_summary, ftimer_init, &
                     ftimer_print_summary, ftimer_start, ftimer_stop
   use ftimer_types, only: ftimer_summary_t
   implicit none

   type(ftimer_summary_t) :: summary

   call ftimer_init()
   call ftimer_start("work")
   call ftimer_stop("work")

   call ftimer_get_summary(summary)
   call ftimer_print_summary()
   call ftimer_finalize()
end program quick_start
```

For lexical blocks with early exits, the procedural API also provides a scalar scoped guard:

```fortran
block
   use ftimer, only: ftimer_guard_t, ftimer_scope
   type(ftimer_guard_t) :: guard
   integer :: ierr

   call ftimer_scope(guard, "work", ierr=ierr)
   if (ierr /= 0) error stop

   ! work that may return or exit the block early
end block
```

The guard starts the named timer through the default procedural instance and stops that same activation when the guard leaves scope. Call `guard%stop(ierr=ierr)` when you need to observe the stop result before scope exit. For non-lexical lifetimes, cached-id hot paths, or complex ownership, prefer explicit `ftimer_start`/`ftimer_stop`.

OOP users can use the same scoped pattern when they make the borrowed timer
lifetime explicit with a pointer:

```fortran
use ftimer_core, only: ftimer_oop_guard_t, ftimer_oop_scope, ftimer_t

type(ftimer_t), target :: timer_storage
type(ftimer_t), pointer :: timer

timer => timer_storage
call timer%init()

block
   type(ftimer_oop_guard_t) :: guard

   call ftimer_oop_scope(timer, guard, "work")
end block

call timer%finalize()
```

The OOP guard stores a non-owning pointer to the timer, so the timer target must outlive the guard and remain initialized until the guard is inactive. Keep explicit `timer%start()` / `timer%stop()` as the primary OOP API when a pointer-borrowed lexical guard would make ownership less clear.

Use `ftimer` for the procedural API and `ftimer_types` for shared types and constants such as `ftimer_summary_t`, `ftimer_context_diagnostic_t`, `ftimer_mpi_summary_t`, `ftimer_mpi_union_summary_t`, `ftimer_metadata_t`, and `FTIMER_MISMATCH_*`.

For metadata headers, construct `ftimer_metadata_t` values by assigning `%key` and `%value` directly. These fields use allocatable-length storage, so assigned strings are not silently capped at the legacy 64-character threshold. Human-readable text reports escape metadata C0/C1 control bytes, UTF-8 encoded C1 controls, terminal escape bytes, backslashes, and leading blanks with the same visible policy used for formatted timer names, while valid non-control UTF-8 text is preserved. fTimer does not currently provide a helper constructor such as `ftimer_metadata(...)`; for formatted numeric metadata, write to a temporary character variable and then assign that string to `%value`.

## First Success

The fastest evaluation path is the serial smoke build plus the `basic_usage` example:

```bash
cmake -B build-smoke
cmake --build build-smoke --target basic_usage
./build-smoke/examples/basic_usage
```

You should see output shaped like this:

```text
Recorded timers: 1
Total time (s) : <nonnegative elapsed time>

Timer name  Inclusive (s)     Self (s)    Calls   % Total
---------------------------------------------------------
work         <nonnegative>   <nonnegative>       1   <nonnegative>
```

The exact timings vary by machine and compiler, but a successful run should show:

- one recorded timer
- a nonnegative total time, usually positive on typical runs
- a `work` row with one call and nonnegative inclusive/self time

This is the default happy path for first-time evaluation. It exercises the library build, links an example program, and produces believable summary output without requiring MPI or pFUnit.

If the first build, MPI path, OpenMP path, CSV export, or first example fails,
see the symptom-oriented [`docs/troubleshooting.md`](docs/troubleshooting.md)
guide before digging into the full semantics reference.

## Install And Use From Another Project

Install fTimer to a prefix:

```bash
cmake -B build-install -DCMAKE_INSTALL_PREFIX=/path/to/ftimer-install
cmake --build build-install
cmake --install build-install
```

Then consume it from a downstream CMake project:

```cmake
cmake_minimum_required(VERSION 3.16)
project(my_app LANGUAGES Fortran)

find_package(fTimer CONFIG REQUIRED)

add_executable(my_app main.F90)
target_link_libraries(my_app PRIVATE fTimer::ftimer)
```

Configure the downstream build with `CMAKE_PREFIX_PATH` pointing at the installed prefix:

```bash
cmake -S my_app -B my_app/build -DCMAKE_PREFIX_PATH=/path/to/ftimer-install
cmake --build my_app/build
```

The supported downstream contract is the installed package export. New adopters should not need to infer the intended consumption model from the test suite.

Pre-1.0 CMake package compatibility is intentionally limited to the same minor release line. For example, a `0.2.z` install may satisfy `find_package(fTimer 0.2 CONFIG REQUIRED)` or an older compatible `0.2.x` request, but it will not satisfy a `0.1.x`, `0.3.x`, or later-minor request. Versionless `find_package(fTimer CONFIG REQUIRED)` remains available for consumers that deliberately accept whichever installed fTimer package appears on `CMAKE_PREFIX_PATH`. The `0.2` package line is the first line whose stable summary/result types expose local `call_count` and MPI `min_call_count`/`max_call_count` fields as `integer(int64)`; MPI `avg_call_count` remains `real(wp)`.

The downstream examples under [`tests/install-consumer/`](tests/install-consumer/) are also part of the smoke path. They show the supported installed-package happy path with `find_package(fTimer CONFIG REQUIRED)`, `use ftimer`, `use ftimer_types`, scoped timing, summary retrieval, and the explicit `use ftimer_openmp` API surface from an installed prefix.

The supported source-level module surface is intentionally narrow: `ftimer`, `ftimer_core`, `ftimer_openmp`, and `ftimer_types`. `ftimer_openmp` is the explicit opt-in OpenMP timing surface; its lifecycle/configuration, timer registration/lookup, timed parallel-region, id-first thread-lane timing, local OpenMP summary/report entry points, strict MPI+OpenMP hybrid summary/report/CSV entry points, and sparse union MPI+OpenMP hybrid summary/report/CSV entry points are real. Module-level public symbols are checked against `tests/public_symbol_allowlist.txt`; visible implementation helpers are documented as unstable rather than implied stable API. The installed include tree is a curated compiler module artifact set and currently includes `ftimer_clock.mod`, `ftimer_csv_validation.mod`, `ftimer_summary.mod`, and `ftimer_mpi.mod` so consumers get a coherent Fortran module set. Those implementation modules are not stable import targets. The installed package includes `share/doc/fTimer/installed-api.md` with the same stability contract and `share/doc/fTimer/LICENSE` with the BSD terms. The smoke tests verify the exact module artifact set and installed documentation artifacts.

## Compile-Out / No-Op Instrumentation Pattern

For production builds that should keep timing calls in source but remove fTimer overhead and dependencies, the recommended pattern is an application-owned facade module with two implementations selected by the application's build system:

- an enabled implementation that delegates to `use ftimer`
- a disabled implementation with the same application-facing procedures, but no `use ftimer`, no fTimer link dependency, and no timer state

This keeps normal fTimer users away from preprocessor macros, keeps fTimer's core semantics unconditional, and lets each application decide which calls should remain unconditional in disabled builds.

For example, application code can depend only on its own facade:

```fortran
program my_app
   use my_timing, only: timing_finalize, timing_init, timing_start, timing_stop
   implicit none

   call timing_init()
   call timing_start("advance")
   ! application work
   call timing_stop("advance")
   call timing_finalize()
end program my_app
```

Then CMake can select one facade source:

```cmake
option(MY_APP_ENABLE_TIMING "Enable fTimer instrumentation" ON)

if(MY_APP_ENABLE_TIMING)
  find_package(fTimer CONFIG REQUIRED)
  target_sources(my_app PRIVATE my_timing_enabled.F90)
  target_link_libraries(my_app PRIVATE fTimer::ftimer)
else()
  target_sources(my_app PRIVATE my_timing_disabled.F90)
endif()
```

The disabled facade should make instrumentation entry points silent no-ops. If an `ierr` argument is present, set it to `0`, matching `FTIMER_SUCCESS`; if `ierr` is absent, do not write to stderr. Disabled wrappers should not validate names, maintain a stack, create summaries, write timing files, fire callbacks, or enter MPI collectives. If a dependency-free build is required, keep fTimer summary types out of unconditional application code; expose application-level report helpers or simple status/count values instead.

fTimer intentionally does not install a drop-in no-op `ftimer` module. Providing a second module with the same public name as the real library is easy to misconfigure and can hide which semantics are active. The supported strategy is to put the build switch at the application facade boundary.

The repository includes a worked example under `examples/instrumentation_facade_*.F90`. The smoke test builds and runs both `instrumentation_facade_enabled`, which links fTimer and records one timer, and `instrumentation_facade_disabled`, which does not link fTimer and verifies that the same timing calls compile and execute as no-ops.

## API Surface

The public API supports four stable import surfaces:

- Procedural API from `use ftimer`, including `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_scope`, `ftimer_guard_t`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_mpi_union_summary`, `ftimer_print_summary`, `ftimer_write_summary`, `ftimer_write_summary_csv`, `ftimer_print_mpi_summary`, `ftimer_write_mpi_summary`, `ftimer_write_mpi_summary_csv`, `ftimer_print_mpi_union_summary`, `ftimer_write_mpi_union_summary`, `ftimer_write_mpi_union_summary_csv`, and `ftimer_default_instance`
- OOP API through `type(ftimer_t)` in `ftimer_core`, including explicit `start`/`stop`, the configuration methods `set_clock`, `clear_clock`, `set_callback`, and `clear_callback`, plus pointer-based scoped timing with `ftimer_oop_guard_t` and `ftimer_oop_scope`
- Explicit opt-in OpenMP API through `type(ftimer_openmp_t)` in `ftimer_openmp`, including keyword-required `init(config=...)`, optional MPI `comm=` in MPI builds, `reset`, `finalize`, `register_timer`, `lookup_timer`, `begin_parallel_region`, `end_parallel_region`, `start_id`, `stop_id`, `get_openmp_summary`, `print_openmp_summary`, `write_openmp_summary`, `write_openmp_summary_csv`, `mpi_openmp_summary`, `print_mpi_openmp_summary`, `write_mpi_openmp_summary`, `write_mpi_openmp_summary_csv`, `mpi_openmp_union_summary`, `print_mpi_openmp_union_summary`, `write_mpi_openmp_union_summary`, and `write_mpi_openmp_union_summary_csv`
- Shared stable types, constants, and callback/clock interfaces from `ftimer_types`, including the summary/result types and `FTIMER_*` status, event, and mismatch constants

New users should start with the procedural API unless they already know they need instance-level control. Reach for `type(ftimer_t)` when you want multiple independent timer objects, want to avoid the default global instance, or need to manage clock or callback configuration on a specific timer object. Procedural callers that need those advanced controls can use `ftimer_default_instance%...` explicitly.

Some implementation-detail symbols are publicly visible from stable modules because current Fortran module layering requires them: `ftimer_call_stack_t`, `ftimer_context_list_t`, `ftimer_segment_t`, `ftimer_internal_start_scope_activation`, and `ftimer_internal_stop_scope_activation`. They are unstable public-by-necessity names, not supported downstream API. User code should avoid importing them and should rely on `ftimer_scope()`, `ftimer_oop_scope()`, explicit start/stop calls, and the structured summary result types instead. Test-only helper exports such as `ftimer_test_get_state`, `ftimer_test_set_call_count`, and `ftimer_test_state_t` are confined to `FTIMER_BUILD_TESTS` helper builds.

Operational notes:

- `ierr` is now the last optional argument in the `init` signatures. In MPI builds, communicator capture uses `comm :: type(MPI_Comm)` from `mpi_f08`; integer communicator handles are not accepted. Integer `init` options such as `mismatch_mode` and `ierr` must be passed by keyword so legacy positional communicator handles cannot be mistaken for supported options. Keywords are recommended for readability on all `init` calls.
- `ftimer_openmp_t%init` requires `config=` and accepts `comm=` only by keyword in MPI builds. If `comm=` is omitted in an MPI+OpenMP build, the object captures `MPI_COMM_WORLD`; pass `comm=` to use a caller-owned communicator explicitly. The MPI communicator handle is used by the strict and sparse union `mpi_openmp` report families and is otherwise non-owning; local OpenMP summary/report behavior does not consume it. Current `ftimer_openmp_t` timing uses the non-MPI wall clock even in MPI-enabled packages, so worker timing does not call `MPI_Wtime()` from OpenMP threads or require an `MPI_Init_thread` support level. The OpenMP object keeps registered timer ids valid across `reset()` and invalidates them across `finalize()`/reinit without recycling ids in the same object. `config%max_lanes` counts the serial lane plus worker lanes. In `FTIMER_USE_OPENMP=ON` fTimer builds, `begin_parallel_region`/`end_parallel_region` are called from serial context and `start_id`/`stop_id` may run inside the open level-1 OpenMP region. Worker calls outside an open timed region, over `config%max_lanes`, or on the wrong lane return errors without mutating unrelated lane state. Calls made inside an OpenMP parallel region without `ierr` queue bounded diagnostics instead of writing unordered stderr, except for valid worker timing calls. A later serial lifecycle call without `ierr` emits one aggregate message and proceeds. With `ierr`, a lifecycle call that observes queued worker diagnostics returns the first queued status without stderr and leaves lifecycle state unchanged; repeat the lifecycle call after that explicit drain to proceed. Local OpenMP summaries are stopped-run-only, use `ftimer_openmp_summary_t`, distinguish timed-region wall-clock envelope time from summed lane work, compute self time on each lane before aggregation, and report missing lanes from observed eligible team lanes rather than configured capacity. Strict MPI+OpenMP summaries are stopped-run collectives over the captured communicator, use `ftimer_mpi_openmp_summary_t`, require identical timer descriptors and eligible lane participation across ranks, and reject mismatches rather than zero-filling missing rank/lane data. Sparse union MPI+OpenMP summaries are stopped-run collectives over the same captured communicator, use `ftimer_mpi_openmp_union_summary_t`, build a descriptor union across ranks and lanes, and report explicit rank/lane participation so absent contributors are not confused with present zero work. In non-OpenMP fTimer packages, `ftimer_openmp` is a serial-context lifecycle/catalog/timing surface only, even if a downstream application separately enables OpenMP. In non-MPI fTimer packages, initialized `ftimer_openmp_t` objects return `FTIMER_ERR_NOT_IMPLEMENTED` from the MPI+OpenMP summary/report methods; the usual lifecycle checks still take precedence, so uninitialized objects return `FTIMER_ERR_NOT_INIT`.
- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`. The MPI build-default clock calls `MPI_Wtime()`, and MPI summaries/reports enter MPI collectives, so initializing, timing, summarizing, reporting, resetting, or finalizing an MPI-enabled timer outside the MPI lifetime is unsupported.
- `init(config=...)` in an MPI build captures `MPI_COMM_WORLD` by default. `init(comm=...)` captures a caller-selected communicator to use for later MPI summaries and reports, but fTimer stores that communicator as a non-owning handle. It does not call `MPI_Comm_dup` or `MPI_Comm_free` for caller-provided communicators. If you pass a subcommunicator, keep it valid until all fTimer summaries, reports, `finalize()`, or any `init()` reinitialization that may use the old communicator are complete.
- Current `ftimer` and `type(ftimer_t)` `init`, `reset`, and `finalize` calls are correctness-first on active timers: with `ierr` they return `FTIMER_ERR_ACTIVE`; without `ierr` they warn and leave state unchanged. In `FTIMER_USE_OPENMP=ON` builds, that diagnostic contract applies on the master thread; worker-thread lifecycle calls through the current APIs remain silent no-ops. These paths do not force-stop active timers or synthesize summary data.
- Stop-mismatch repair remains an explicit `mismatch_mode` choice (`FTIMER_MISMATCH_WARN` or `FTIMER_MISMATCH_REPAIR`); omitted-`ierr` alone does not opt a caller into recovery.
- The `ierr` contract covers normal validation, lifecycle, mismatch, unsupported-feature, MPI consistency, MPI datatype/collective, file/CSV I/O, stale-id, and explicit integer-space exhaustion checks. Arbitrary allocation failure and process resource exhaustion are not currently recoverable fTimer status paths; the Fortran runtime may terminate before fTimer can return an `ierr`. Remaining production `error stop` paths are reserved for impossible clock/backend conditions or internal stack/index invariants where continuing could corrupt timing data.
- Timer names are right-trimmed and must be non-empty, must not begin with a blank, and must not contain ASCII control characters. fTimer does not silently truncate timer names and no longer rejects names solely for exceeding the legacy `FTIMER_NAME_LEN = 64` threshold.
- Name-based `start`/`stop` remains the default ergonomic path. The runtime now uses internal mapped lookup for both resident timer names and per-segment parent-stack contexts, plus capacity-based growth, so that this default path avoids repeated resident-timer linear scans and context-list scans in steady state as the timer set and parent-stack variants grow.
- For `ftimer_openmp_t`, register names in serial context and pass ids into worker regions for the hot path. The OpenMP runtime keeps private catalog and lane-context indexes and grows segment storage only on participating lanes, so a public reserve/warm API is not currently required. For benchmark-only overhead studies, callers may touch the same lane/timer/context combinations inside the same opened timed region/epoch before starting an external measurement loop, then ignore the fTimer summary from that run; current fTimer summaries include those warm-up calls, and a fresh timed region still pays one team-size observation per participating lane.
- `ftimer_scope(guard, name, ierr)` is a small safety layer for scalar lexical-block timing on the default procedural instance. `call ftimer_oop_scope(timer_pointer, guard, name, ierr)` provides OOP scoped timing through `ftimer_core` when the caller passes an associated `type(ftimer_t), pointer` and uses `type(ftimer_oop_guard_t)`.
- Scoped guards do not replace explicit `start`/`stop`; explicit `timer%start()` / `timer%stop()` remains the primary OOP API. A guard may stop only the exact activation it started; if that activation was already stopped, invalidated by lifecycle, or displaced by other timer operations, `guard%stop(ierr)` returns `FTIMER_ERR_MISMATCH` or the relevant lifecycle error and the finalizer warns when it cannot report `ierr`.
- OOP scoped guards store a non-owning timer pointer. The timer target must outlive the guard and remain initialized until the guard is inactive; use a nested block/procedure for the guard or call `guard%stop(ierr=...)` before leaving a shared scope or calling timer lifecycle operations. Lifecycle calls reject the guard-owned activation while it is still active on the timer stack; if user code manually stops that activation first, the guard becomes stale and later `guard%stop(ierr=...)` reports a mismatch instead. Do not rely on finalization order for an automatic timer object and an active guard declared in the same scoping unit.
- Guard assignment/copy is unsupported and does not copy or transfer active ownership; assignment involving an active guard warns and leaves ownership with the original guard. Guard arrays, saved/global guards, function-return guard constructors, cross-procedure lifetime patterns, deallocated timer targets, and block-local finalization inside OpenMP parallel regions are unsupported. `ftimer_scope_id` is deferred.
- `lookup()` plus `start_id()`/`stop_id()` remains an optional hot-path optimization when one call site times the same known region in a very tight loop. That path is especially useful when a long scientific label would otherwise be validated and hashed on every name-based call.
- Cached IDs returned by `lookup()` are opaque handles for the current timer runtime state, not segment-array indexes. They remain valid across `reset()`, but successful `init()` and `finalize()` calls invalidate them. Calls made while finalized follow the normal `FTIMER_ERR_NOT_INIT` lifecycle contract; after a later successful `init()`, passing a stale cached ID to `start_id()` or `stop_id()` returns `FTIMER_ERR_UNKNOWN` and leaves timer state unchanged.
- Configure custom clocks through `set_clock()` and restore the build-default wall clock through `clear_clock()`. Direct mutation of raw runtime clock internals is not part of the supported API.
- Clock changes are allowed before `init()` or before a run records timing data. If configured before `init()`, the next `init()` starts the local summary window in the selected clock epoch. If changed after `init()` but before timing data exists, `set_clock()` or `clear_clock()` immediately restarts that window in the newly selected clock epoch; the first later `start()` does not move it. Empty local summaries, text reports, and CSV exports therefore use one clock epoch for `summary%total_time` and `% Total`.
- After timing has started, `set_clock()` and `clear_clock()` return `FTIMER_ERR_ACTIVE` (or warn to stderr when `ierr` is omitted) and leave state unchanged. Use `reset()`, `init()`, or `finalize()` to begin a fresh run on a different clock.
- In non-MPI builds, the build-default wall clock is Fortran `system_clock(count, rate)` converted to seconds. fTimer assumes a positive rate and a nondecreasing count during a timing run; it does not clamp backward movement or compensate for counter wrap, so those backend behaviors remain visible in elapsed times and summaries.
- The default serial clock's nominal resolution is `1 / count_rate` seconds and its uninterrupted useful range depends on the compiler/runtime `count_max` and `count_rate`. Current summary schemas and reports do not expose clock-rate or wrap metadata; applications that need to archive toolchain-specific clock characteristics can include them as user metadata.
- Configure callbacks through `set_callback()` and `clear_callback()`. Callback configuration is rejected while timers are active, `clear_callback()` also clears callback `user_data`, and `finalize()` clears callback configuration.
- `get_summary()`, `print_summary()`, and `write_summary()` are local-only summary/reporting paths.
- `get_summary()`, `print_summary()`, and `write_summary()` are live snapshot APIs. They include active local timer contexts through the snapshot timestamp without stopping them, and mark that state with `summary%has_active_timers`, each entry's `is_active`, and, when active entries exist, the formatted report's `Active timers`/`Active` fields. For a final local report, stop all timers first and verify `summary%has_active_timers == .false.`.
- Human-readable local, strict MPI, and sparse MPI text reports escape metadata header keys and values before writing them. Tabs, newlines, carriage returns, delete, terminal escape bytes, other C0/C1 controls, UTF-8 encoded C1 controls, backslashes, and leading blanks are rendered visibly instead of being emitted as raw log-control text; valid non-control UTF-8 text is preserved and blank metadata values remain blank.
- Local summary entries retain preorder formatting compatibility and now expose explicit tree structure through `node_id` and `parent_id`. `node_id` values are stable only within one produced summary object, and roots use `parent_id = 0`.
- Local structured summaries also expose context-cardinality diagnostics without changing runtime behavior by default. `summary%total_contexts` is the total number of allocated parent-stack contexts across resident timers, `summary%max_contexts_per_timer` is the largest per-timer context count, and `summary%context_diagnostics(:)` names each resident timer with its allocated context count, including timers whose contexts are currently hidden from visible summary rows. Each visible entry's `timer_context_count` repeats the count for that entry's timer name. These are structured-summary fields only; text and CSV report schemas are unchanged, no warning threshold or hard cap is enabled by default, and context-sensitive accounting remains unchanged.
- Local summary `call_count` fields are signed-64-bit counts. If a timer context ever reaches the signed-64-bit maximum, the next `start` fails with `FTIMER_ERR_UNKNOWN` or the normal omitted-`ierr` warning path rather than wrapping the count. If the classic timer object's unique timer-id space is exhausted, new timer creation through `lookup()` or name-based `start()` also fails with `FTIMER_ERR_UNKNOWN` or the omitted-`ierr` warning path.
- `write_summary_csv()` and `ftimer_write_summary_csv()` export local summaries as stable CSV records for dashboards, CI comparisons, plotting, and archives. The text report remains human-facing; consumers should use the CSV or structured Fortran summary rather than scraping fixed-width report output.
- `mpi_summary()` and `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON`, a fully stopped timer set, and collective agreement on the communicator captured by `init`.
- A successful MPI reduction returns a distinct `ftimer_mpi_summary_t` whose fields are globally meaningful on every participating rank.
- The MPI result includes communicator-local rank attribution for total-time extrema and per-entry inclusive-time extrema. Ties resolve to the lowest rank that attains the extremum.
- MPI call-count extrema remain exact `integer(int64)` fields. `avg_call_count` remains `real(wp)` and is computed without integer-sum overflow by reducing exact `integer(int64)` extrema first, then averaging nonnegative deltas from the exact minimum count. The final average is clamped to the representable `real(wp)` conversions of the exact min/max counts. Because `real(wp)` cannot represent every signed-64-bit integer exactly, a near-limit average may differ from the exact integer average by representable real rounding.
- Sparse/union MPI summaries use the separate `mpi_union_summary()` / `ftimer_mpi_union_summary()` API and `ftimer_mpi_union_summary_t` result type. This opt-in path builds a canonical descriptor union across ranks instead of weakening strict `mpi_summary()`.
- `ftimer_mpi_union_summary_t` keeps communicator total-time fields as all-rank statistics. Each entry records `participating_rank_count`; missing rank count is derived as `num_ranks - participating_rank_count`, and entry min/avg/max statistics are defined over participating ranks only.
- Sparse entries are materialized from descriptors emitted by each rank's local summary. Lookup-only timer definitions are not a first-class sparse-registration contract, absent ranks are not zero-filled, and no all-rank amortized compatibility fields are included in the initial result model.
- `print_mpi_union_summary()` / `ftimer_print_mpi_union_summary()` and `write_mpi_union_summary()` / `ftimer_write_mpi_union_summary()` are the explicit sparse text report paths. `write_mpi_union_summary_csv()` / `ftimer_write_mpi_union_summary_csv()` is the explicit sparse CSV export path. They build `ftimer_mpi_union_summary_t`, emit one communicator-root artifact, and expose `Participating` plus derived `Missing` rank counts so absent ranks are not confused with zero work.
- Sparse union report entry statistics are over participating ranks only. A present zero-elapsed timer with a real start/stop contributes to participation and call-count statistics; lookup-only names are still not sparse registrations. Sparse CSV export keeps those same participation-only semantics in explicitly named columns.
- `print_mpi_summary()` and `write_mpi_summary()` are the first-class strict MPI reporting paths. They perform the collective strict MPI summary build, emit one abbreviated report from communicator root, and synchronize root output failures so every participant observes `FTIMER_ERR_IO`. The printed per-entry table is not a serialization of every `ftimer_mpi_summary_t` field; inspect `mpi_summary()` results for min/max self time, self imbalance, min/max call counts, min/max rank-local `% Total`, and explicit `node_id`/`parent_id` tree links.
- `write_mpi_summary_csv()` and `ftimer_write_mpi_summary_csv()` perform the same collective MPI summary build and write one CSV artifact from communicator root. The CSV includes the complete reduced MPI entry fields, including explicit tree links and inclusive-time extrema ranks.
- In MPI text reports, `Avg %` means the arithmetic mean of each rank's local `% Total` for that timer, not `100*Avg Incl/Avg total time`.
- Callbacks configured on `type(ftimer_t)` are lightweight intra-run hooks. They report normal start/stop events with runtime-local numeric ids; current `main` does not promise a stable semantic id-to-name/path mapping for profiler backends or durable cross-run tooling. Scoped guards produce only the normal underlying start/stop callback events; mutating timer state from callbacks during scoped guard start/stop is unsupported.
- Import shared types and constants from `ftimer_types`; `use ftimer` does not re-export them.
- `FTIMER_NAME_LEN` remains exported so code that only imports the constant still compiles, but timer names, summary names, MPI summary names, and metadata key/value fields now use allocatable-length storage rather than that fixed width. Pre-1.0 callers that treated those public components as preallocated fixed buffers, such as internal writes directly into `%value`, should write to a temporary string and assign the result.

## Examples

- `examples/basic_usage.F90`: serial start/stop plus summary retrieval and formatted output
- `examples/nested_timers.F90`: nested timers and metadata headers
- `examples/instrumentation_facade_*.F90`: enabled and disabled application-owned timing facade implementations that demonstrate the supported compile-out/no-op pattern
- `examples/mpi_example.F90`: pure-MPI timing with a global MPI summary object and first-class MPI report output
- `examples/openmp_example.F90`: the OpenMP compatibility carve-out, where existing API timers bracket the parallel region instead of running inside worker threads
- `examples/openmp_worker_example.F90`: true OpenMP worker timing with `ftimer_openmp_t`, pre-registered ids, an explicit timed region, local OpenMP summary output, and local OpenMP CSV output
- `examples/mpi_openmp_example.F90`: strict MPI+OpenMP worker timing followed by sparse union MPI+OpenMP participation reporting through `ftimer_openmp_t`

See [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md) for the current OpenMP/MPI+OpenMP migration guide. Existing serial, pure-MPI, and OpenMP compatibility users do not need source changes to keep their current behavior; the true OpenMP and hybrid examples are additive opt-in paths.

## CSV Export

The first stable machine-readable export format is CSV, chosen because fTimer summaries are snapshot tables rather than event streams. The local and strict MPI schema is versioned by the `format_version` column and currently uses version `2`. Sparse union MPI CSV uses a separate participation-aware schema with `format_version=1` and `summary_kind=mpi_union`; local OpenMP CSV uses its own schema with `format_version=1` and `summary_kind=openmp`; strict MPI+OpenMP CSV uses a separate schema with `format_version=1` and `summary_kind=mpi_openmp`; sparse union MPI+OpenMP CSV uses a separate schema with `format_version=1`, `summary_kind=mpi_openmp_union`, and `participation_policy=sparse_union`. These dedicated schemas are intentionally not append-compatible with the local/strict MPI v2 header or with each other.

See [`docs/csv-schema.md`](docs/csv-schema.md) for the compact field dictionary,
schema-family signatures, denominator choices, active snapshot fields, append
constraints, and sparse participation interpretation used by CSV readers.

Each CSV starts with one header row followed by typed records. All schemas use:

- `record_type=summary` carries run-level fields.
- `record_type=metadata` carries caller-supplied metadata as `key`/`value`.
- `record_type=entry` carries one timer node per row.

Participation-aware schemas may add records for their own aggregate surface.
Strict MPI+OpenMP CSV also emits `record_type=rank` rows for per-rank
summary-window, envelope, and summed-lane fields.

Common local/strict columns include `summary_kind`, `node_id`, `parent_id`, `depth`, and `name`. Local entry rows populate `inclusive_time`, `self_time`, `call_count`, `avg_time`, `pct_time`, and `is_active`. Strict MPI entry rows keep `summary_kind=mpi` and populate the reduced fields from `ftimer_mpi_summary_t`, including min/avg/max inclusive and self time, call count extrema, rank-local percent extrema, imbalance fields, and inclusive-time extrema ranks. Local `call_count` and MPI `min_call_count`/`max_call_count` are `integer(int64)` values and are emitted as decimal text without narrowing to default integer. MPI `avg_call_count` remains a real-valued CSV field. CSV format version `2` is the compatibility signal for those widened integer count ranges; consumers should parse local `call_count` and MPI call-count extrema fields as at least signed 64-bit decimal integers.

Sparse union CSV rows use `summary_kind=mpi_union`. Entry rows include `participating_rank_count` and explicit `missing_rank_count`, derived as `num_ranks - participating_rank_count`. Per-entry statistic columns are deliberately labeled as participating-rank fields, for example `min_participating_inclusive_time`, `avg_participating_self_time`, and `max_participating_call_count`. Participating call-count extrema are emitted as signed-64-bit decimal text. Missing ranks are not zero-filled, and no all-rank amortized entry view is emitted.

OpenMP CSV rows use `summary_kind=openmp`. Summary rows distinguish `summary_window_time`, `timed_region_envelope_time`, `sum_lane_root_inclusive_time`, and `sum_lane_self_time`. Entry rows include explicit tree links, `eligible_lane_count`, `participating_lane_count`, `missing_lane_count`, `missing_lane_count_known`, and lane aggregate fields such as `sum_lane_inclusive_time`, `avg_lane_self_time`, and `max_lane_call_count`. Missing lanes are not zero-filled, and the schema is an aggregate summary table rather than a trace or profiler event stream. When one descriptor spans timed-region epochs with different OpenMP team sizes, `eligible_lane_count` is the maximum/union eligible lane count retained for that aggregate row and `missing_lane_count_known=false` marks `missing_lane_count` as non-precise; the text report prints `unknown` for that missing value.

Strict MPI+OpenMP CSV rows use `summary_kind=mpi_openmp`. Summary rows carry communicator-level rank extrema, rank rows carry per-rank summary-window/envelope/summed-lane fields, and entry rows carry descriptor aggregates over participating rank/lane samples. Entry rows include `execution_domain`, `eligible_rank_lane_sample_count`, `participating_rank_lane_sample_count`, explicit missing-sample fields, participating-lane inclusive/self/call-count/percent extrema, and imbalance fields. Strict mismatches are rejected before numeric reductions; missing rank/lane data is not zero-filled.

Sparse union MPI+OpenMP CSV rows use `summary_kind=mpi_openmp_union` and `participation_policy=sparse_union`. Summary and rank rows preserve the same communicator and per-rank OpenMP summary-window fields as the strict hybrid schema, while entry rows add `participating_rank_count`, `missing_rank_count`, `eligible_rank_lane_sample_count`, `participating_rank_lane_sample_count`, and explicit missing-sample fields. Per-entry statistics are over participating rank/lane samples only. Absent ranks and absent lanes are not zero-filled, and strict hybrid CSV append targets remain incompatible with this sparse union schema. Mixed OpenMP epochs with different team sizes retain aggregate eligible rank/lane sample counts but set `missing_rank_lane_sample_count_known=false`; sparse hybrid text reports print `unknown` rather than a precise missing-sample count.

Appending to an existing non-empty CSV requires the existing first row to match the exact header for the API being used, existing rows to be well-formed CSV logical records with that header's field count and recognized `summary_kind`/`record_type` combinations, and the target to end with a newline; mismatched headers, older-format records, malformed record shape or quote placement, or unterminated final records are rejected instead of mixing schemas silently. Append validation is a schema-shape and CSV-syntax guard for existing files, not a semantic reparse of every numeric, logical, or timing payload field already present. CSV text fields emit trimmed raw timer names and metadata key/value text with standard CSV quoting; unlike human-readable text reports, they do not apply the visible `\t`/`\n`/`\xNN` display escaping. They are not spreadsheet-formula-sanitized, so treat CSV opened in spreadsheet software as data from the generating program.

Example:

```fortran
call ftimer_write_summary_csv("ftimer-summary.csv", ierr=ierr)

! In an FTIMER_USE_MPI=ON build, collectively writes from communicator root.
call ftimer_write_mpi_summary_csv("ftimer-mpi-summary.csv", ierr=ierr)

! For rank-conditional timer trees, use the explicit sparse union CSV schema.
call ftimer_write_mpi_union_summary_csv("ftimer-mpi-union-summary.csv", ierr=ierr)

! For local OpenMP worker timing, use type(ftimer_openmp_t)'s CSV method.
call omp_timer%write_openmp_summary_csv("ftimer-openmp-summary.csv", ierr=ierr)

! For rank/lane-conditional MPI+OpenMP worker timing, use the sparse union schema.
call omp_timer%write_mpi_openmp_union_summary_csv("ftimer-mpi-openmp-union-summary.csv", ierr=ierr)
```

## Build And Test

Minimum requirements:

- CMake 3.16 or newer
- A Fortran compiler with preprocess support
- pFUnit only when `FTIMER_BUILD_TESTS=ON`
- An MPI wrapper/compiler pair only when `FTIMER_USE_MPI=ON`
- GNU Fortran or LLVM Flang with a discoverable OpenMP runtime when `FTIMER_USE_OPENMP=ON`
- CMake 3.24 or newer for the LLVM Flang OpenMP path

```bash
# Smoke-test path (includes install/export consumer verification)
cmake -B build-smoke
cmake --build build-smoke
cmake -E chdir build-smoke ctest --output-on-failure

# Serial build with pFUnit tests
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
cmake -E chdir build ctest --output-on-failure

# MPI smoke/install-consumer build (validated with GNU OpenMPI and GNU MPICH wrappers)
FC=mpifort cmake -B build-mpi-smoke -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=OFF
cmake --build build-mpi-smoke
cmake -E chdir build-mpi-smoke ctest --output-on-failure

# MPI pFUnit build (validated with GNU OpenMPI and GNU MPICH wrappers)
FC=/path/to/mpi-mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/mpi-pfunit -DMPIEXEC_EXECUTABLE=/path/to/mpi-mpiexec
cmake --build build-mpi
cmake -E chdir build-mpi ctest --output-on-failure -L mpi

# MPI+OpenMP smoke build for compatibility plus strict and sparse union hybrid examples/summaries
FC=mpifort cmake -B build-mpi-openmp -DFTIMER_USE_MPI=ON -DFTIMER_USE_OPENMP=ON
cmake --build build-mpi-openmp
cmake -E chdir build-mpi-openmp ctest --output-on-failure

# OpenMP build with pFUnit tests (GNU Fortran)
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
cmake -E chdir build-openmp ctest --output-on-failure

# OpenMP smoke build (LLVM Flang)
FC=flang-19 cmake -B build-openmp-flang -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=OFF
cmake --build build-openmp-flang
cmake -E chdir build-openmp-flang ctest --output-on-failure \
  -R '^(ftimer_openmp_example_smoke|ftimer_openmp_worker_example_smoke)$'

# Convenience Makefile wrapper
make
make mpi
make openmp
make test
```

If CMake cannot discover LLVM Flang's OpenMP runtime automatically, pass
`-DOpenMP_ROOT=/path/to/libomp` for that toolchain.
Cross-compiling or execution-restricted package builds may set
`-DFTIMER_OPENMP_ASSUME_MASTER_PROBE_OK=ON` only after independently validating
equivalent OpenMP master-thread and worker-lane runtime semantics for the selected
compiler/runtime pair.

The smoke-test path also runs the enabled and disabled instrumentation facade examples so the documented compile-out strategy stays buildable.

For practical remedies to first-use build failures, MPI summary hangs, OpenMP
worker-call surprises, and CSV append errors, see
[`docs/troubleshooting.md`](docs/troubleshooting.md).

Supported toolchain matrix:

- Serial smoke/library build: GNU Fortran and LLVM Flang are validated in automation
- Serial plus pFUnit tests: GNU Fortran with a matching pFUnit installation
- MPI: GNU Fortran wrapper compiler paths are validated with OpenMPI and MPICH; smoke/install-consumer coverage runs for both, and MPI pFUnit coverage runs for OpenMPI plus MPICH on hosted Ubuntu 22.04 with a matching MPICH-built pFUnit
- OpenMP: GNU Fortran with pFUnit guard coverage, plus LLVM Flang smoke/example coverage for the documented master-thread-only carve-out and the opt-in `examples/openmp_worker_example.F90` path
- MPI+OpenMP: OpenMPI wrapper builds with OpenMP are smoke-tested in CI for current compatibility mode, `examples/mpi_openmp_example.F90`, the opt-in `ftimer_openmp` worker API, strict and sparse union MPI+OpenMP hybrid summary/report/CSV output, and MPI-initialized OpenMP installed consumers; MPICH wrapper builds have focused local smoke/install-consumer evidence recorded in `docs/release-evidence.md`

Other serial compilers may still work, but they are not part of the current release-validated matrix unless the repo adds direct automation for them.

Use a separate build directory for each compiler or mode. Reconfiguring the same build tree with a different Fortran compiler is not a supported workflow in this repository.

## Current Limitations And Contracts

- CMake is the supported build and package path. FPM support is intentionally deferred.
- fTimer is wall-clock only. It does not synchronize asynchronous accelerator/device work, so callers must perform any required device synchronization before `stop` when they intend to measure completed device work rather than host launch/enqueue latency.
- fTimer does not insert MPI barriers around timed regions. MPI summaries reduce rank-local intervals; callers must add any desired MPI synchronization themselves when they intend to measure a synchronized global phase.
- `FTIMER_USE_MPI=ON` is intended for wrapper-compiler setups such as `FC=mpifort`. Configure now fails early if the active compiler cannot compile a minimal `mpi_f08` probe against the discovered MPI installation, or if that `mpi_f08` path cannot compile the `MPI_Type_match_size`/`MPI_ERRORS_RETURN` calls fTimer uses to validate reduction datatypes.
- The current MPI interface contract is `mpi_f08` with `type(MPI_Comm)` communicator handles captured at `init`. Legacy integer communicator handles and `mpif.h` are not supported interface paths.
- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`. The runtime does not currently provide a separate pre-init/post-finalize guard contract for all MPI clock and collective entry points.
- Communicators passed to `init(comm=...)` remain owned by the caller. fTimer stores a non-owning handle and may use it later in `mpi_summary()`, `mpi_union_summary()`, MPI report writers, `finalize()`, or reinitialization. Do not free a subcommunicator until those fTimer operations that could use it are complete.
- MPI summary reductions select MPI datatypes with `MPI_Type_match_size` for fTimer's actual `real(wp)` and `integer(int64)` storage sizes instead of assuming fixed `MPI_DOUBLE_PRECISION`, `MPI_2DOUBLE_PRECISION`, or `MPI_INTEGER8` mappings. The compile-time MPI probe validates that this API is available through the `mpi_f08` path; if the API exists but no matching runtime datatype can be returned, `mpi_summary()` temporarily requests MPI error returns for the datatype lookup, fails with `FTIMER_ERR_UNKNOWN`, and leaves the MPI result empty.
- `mpi_summary()` now returns a distinct `ftimer_mpi_summary_t`; it does not fall back to a local `ftimer_summary_t` on MPI-disabled or MPI-error paths. Call `get_summary()` separately if you need local data in those cases.
- Descriptor-preflight failures inside one communicator now report the disagreeing communicator-local ranks in the omitted-`ierr` diagnostic path when possible.
- Rank-conditional timer reductions are not supported by the strict `mpi_summary()` API. Use the separate opt-in `mpi_union_summary()` / `ftimer_mpi_union_summary()` API with `ftimer_mpi_union_summary_t` for sparse descriptor-union reductions. Sparse entries report explicit participation metadata and participating-rank statistics instead of zero-filling absent ranks.
- Local summary `node_id` values are not a cross-run identity contract. Treat them as explicit links inside one produced summary object, not as durable ids across separate runs or independently produced summaries.
- All ranks that participate in `mpi_summary()` must agree on the communicator captured by `init`. If would-be participants diverge onto different communicators, the library cannot safely discover that mistake after the split; the practical failure mode is a hang, not a clean local fallback.
- `FTIMER_USE_OPENMP=ON` enables limited master-thread-only guards for the current `ftimer` and `ftimer_core` APIs. Worker-thread timer calls through those APIs inside an OpenMP parallel region are silent no-ops. To time a parallel region as a whole through existing APIs, place `start`/`stop` outside the `!$omp parallel` block. To time level-1 worker lanes, use the explicit `ftimer_openmp_t` object with pre-registered ids and an opened timed region.
- `use ftimer_openmp` exposes the opt-in worker-timing API without changing current `ftimer` behavior. The object lifecycle/configuration, timer catalog, timed parallel-region, and id-first thread-lane timing calls are available now. Serial timing uses lane 0; worker timing uses one lane per level-1 OpenMP thread id inside an explicitly opened timed region. Cross-lane mismatches, calls outside an open timed region, and out-of-capacity lanes return errors without repairing or popping another lane.
- `ftimer_openmp_t%get_openmp_summary`, `print_openmp_summary`, `write_openmp_summary`, and `write_openmp_summary_csv` are separate from current local and MPI summary/report APIs. They require a stopped OpenMP run and return `FTIMER_ERR_ACTIVE` without a normal artifact if any lane is active or a timed region remains open.
- In MPI+OpenMP builds, `ftimer_openmp_t%mpi_openmp_summary`, `print_mpi_openmp_summary`, `write_mpi_openmp_summary`, and `write_mpi_openmp_summary_csv` provide the strict hybrid rank/lane result and report surface. These entry points are collective, require matching descriptor and lane-participation structure across ranks, and do not relax to sparse/union behavior.
- In MPI+OpenMP builds, `ftimer_openmp_t%mpi_openmp_union_summary`, `print_mpi_openmp_union_summary`, `write_mpi_openmp_union_summary`, and `write_mpi_openmp_union_summary_csv` provide the separate sparse union hybrid rank/lane result and report surface. These entry points are collective, build a descriptor union across ranks and lanes, and expose explicit rank/lane participation metadata instead of pretending all ranks and lanes contributed.
- `FTIMER_USE_OPENMP` is the source-level switch for that carve-out; global OpenMP compiler flags alone do not enable the guards when the option is `OFF`.
- The `ftimer`/`ftimer_core` OpenMP guard path does not make those APIs thread-safe, does not provide thread-local timer instances, and should not be read as a general hybrid MPI+OpenMP timing model.
- OpenMP mode selection, accepted instrumentation patterns, and migration
  guidance are collected in
  [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md). Strict and
  sparse union MPI+OpenMP hybrid timing are separate `ftimer_openmp_t` report
  families, not extensions of the master-thread-only compatibility mode.
  Summary, report, and CSV contracts for those APIs are described in this
  README, [`docs/semantics.md`](docs/semantics.md), and
  [`docs/installed-api.md`](docs/installed-api.md).
- `on_event` remains a lightweight intra-run hook, not a serious profiler-backend integration contract with stable semantic timer identity.
- If `FTIMER_USE_MPI=OFF`, `mpi_summary()` and `mpi_union_summary()` return `FTIMER_ERR_NOT_IMPLEMENTED` and leave their MPI result objects empty. MPI report APIs, including the sparse union report and CSV APIs, return `FTIMER_ERR_NOT_IMPLEMENTED` without emitting report output or creating/replacing report files. Initialized `ftimer_openmp_t` objects return the same status from both strict and sparse union MPI+OpenMP report families in non-MPI packages.
- Formatted local, MPI, and MPI+OpenMP report output are separate paths: `print_summary()`/`write_summary()` are local, `print_mpi_summary()`/`write_mpi_summary()` are strict MPI reports, `print_mpi_union_summary()`/`write_mpi_union_summary()` are opt-in sparse MPI union reports, `print_mpi_openmp_summary()`/`write_mpi_openmp_summary()` are strict hybrid reports on `ftimer_openmp_t`, and `print_mpi_openmp_union_summary()`/`write_mpi_openmp_union_summary()` are sparse union hybrid reports on `ftimer_openmp_t`. MPI reports are deliberately abbreviated; `ftimer_mpi_summary_t`, `ftimer_mpi_union_summary_t`, `ftimer_mpi_openmp_summary_t`, and `ftimer_mpi_openmp_union_summary_t` remain the complete structured data models.

## Performance Measurement

The repository includes a standalone benchmark harness for measuring timer overhead and summary-generation cost:

```bash
cmake -S . -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
./build-bench/bench/ftimer_bench /tmp/ftimer_bench_results.csv
```

For a clean benchmark reconfigure, remove or use a separate `build-bench/`
directory first. With CMake 3.24 or newer, `cmake --fresh` may be added to the
configure command as a convenience for a clean reconfigure.

This is useful for before/after regression checks when changing hot-path timing behavior. Compare the name-based lookup-scaling rows across resident timer counts to confirm the mapped default path stays much flatter than the old linear-scan baseline, and compare the context-scaling rows across larger `C` values to see how one hot timer behaves when it is reused under many distinct parent stacks. The first-touch rows measure the remaining allocation/growth cost for newly discovered timer names and parent-stack contexts after setup has prebuilt labels and initialized independent timer objects. The long-name rows show the extra validation/hash cost for labels above the legacy threshold. The flat name-based/id-based rows still help judge whether the optional cached-id path is worth it for one especially hot loop.

Use benchmark evidence for PRs that touch start/stop hot paths, lookup or
cached-id behavior, context growth or parent-stack accounting, summary
construction, report/CSV formatting, MPI summary/report paths, and for
release-readiness sweeps. Compare CSV rows first for flat name-based
start/stop, cached-id start/stop, lookup scaling across resident timer counts,
context scaling across parent-stack counts, timer/context first-touch
allocation, summary builds, local text/CSV reports, sparse MPI-union
formatting, and the strict MPI CSV row when MPI is enabled. For OpenMP worker
hot-path changes, compare the `ftimer_openmp_t` serial-lane id, timed-region
open/close, worker-lane id, worker context-scaling, OpenMP catalog
register/lookup, concurrent worker-lane, split-object worker-lane,
participating-lane first-touch, and local OpenMP summary-merge rows. For
MPI+OpenMP changes, compare the strict and sparse union MPI+OpenMP CSV report
rows.

The benchmark harness also includes reporting-scale rows for local text reports, local CSV reports, sparse MPI-union text formatting, long timer names, metadata-heavy output, and the `ftimer_openmp_t` serial-lane id path. When fTimer is built with `FTIMER_USE_MPI=ON`, the harness adds a strict MPI CSV report row. When built with `FTIMER_USE_OPENMP=ON`, it adds timed-region open/close, worker-lane, worker context-scaling, OpenMP catalog register/lookup, concurrent worker-lane, split-object worker-lane, participating-lane first-touch, and local OpenMP summary-merge rows. When built with both `FTIMER_USE_MPI=ON` and `FTIMER_USE_OPENMP=ON`, it adds strict and sparse union MPI+OpenMP CSV report rows. Passing a file path as the first argument writes parseable CSV benchmark observations; durable PR or release trend evidence should keep the provenance sidecar context described in [`docs/release.md`](docs/release.md) beside that CSV. The serial benchmark CI job uploads the validated CSV as a `ftimer-bench-serial-<sha>` artifact. OpenMP and MPI+OpenMP benchmark CI jobs build `ftimer_bench` and run CSV smoke checks, but durable CSV artifact upload for those feature-enabled benchmark jobs is deferred; run the feature-enabled harness locally when trend evidence beyond smoke coverage is needed. Report-writing rows use per-run scratch files in the system temporary directory and delete only those scratch files when they finish. The harness records trend evidence only, does not enforce timing thresholds, and GitHub-hosted runner numbers should be treated cautiously because absolute timings are noisy.

## More Detail

- Runtime semantics: [`docs/semantics.md`](docs/semantics.md)
- Troubleshooting guide: [`docs/troubleshooting.md`](docs/troubleshooting.md)
- Current architecture reference: [`docs/design.md`](docs/design.md)
- OpenMP timing modes and migration guide: [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md)
- Release checklist and artifact policy: [`docs/release.md`](docs/release.md)
- Contributor guidance: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Support and security reporting: [`SUPPORT.md`](SUPPORT.md), [`SECURITY.md`](SECURITY.md)

When current-state sources disagree, use this repository-wide precedence order:

1. current code under `src/`
2. current behavioral tests
3. `docs/semantics.md`
4. `README.md`
5. `docs/design.md`

## License

BSD-3-Clause. See [LICENSE](LICENSE).
