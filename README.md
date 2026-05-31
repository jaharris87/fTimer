# fTimer

fTimer is a lightweight, correctness-first wall-clock timing library for modern Fortran. Current `main` is positioned first for disciplined serial and pure-MPI codes that need hierarchical timers, predictable accounting, and summaries you can inspect programmatically instead of scraping from ad hoc text output.

> Current product position: fTimer's core supported stories are serial timing and pure-MPI timing. `FTIMER_USE_OPENMP=ON` is a narrow master-thread-only carve-out for bracketing a parallel region as a whole, not a general hybrid MPI+OpenMP timing model. The callback hook is a lightweight intra-run event hook, not a stable external-profiler integration contract.

For a first release, the focus is a small, dependable core:

- strict, stack-based start/stop timing by default
- context-sensitive accounting for the same timer name under different parents
- inclusive and self time in structured summaries with explicit tree linkage
- a small procedural scoped guard for lexical blocks with early exits
- procedural wrappers and an OOP core API
- optional MPI global summaries plus first-class strict text/CSV and sparse text report output
- an installable CMake package for downstream projects

## Why Use fTimer

fTimer fits best when you want timing behavior you can trust:

- nested timers are treated as a real hierarchy, not a flat label list
- mismatch handling is explicit and configurable (`strict`, `warn`, `repair`)
- summaries are available as data first (`get_summary()`), with text formatting layered on top
- stable CSV export is available for dashboards, CI comparisons, plotting, and archives
- local summaries are live snapshots: active timers are included explicitly and marked in the data model/report output
- local summary entries retain formatter-friendly preorder `name`/`depth` data and also expose explicit `node_id`/`parent_id` tree links
- pure-MPI reductions return a distinct `ftimer_mpi_summary_t` with globally meaningful fields on every participating rank
- rank-conditional MPI reductions and text reports are available through opt-in sparse/union APIs and `ftimer_mpi_union_summary_t`
- an injectable clock supports deterministic tests and controlled benchmarking
- optional callback hooks let in-process code observe normal timer start/stop events during a run

If you need a tiny serial timing helper, you can use fTimer that way. If you need structured local summaries, opt-in pure-MPI reductions, and a clear error contract, that is where the library is strongest.

## Supported Workflows

fTimer currently supports these usage paths:

- Serial timing with local summaries plus formatted text and CSV reports
- Pure-MPI builds on the validated `mpi_f08` path that are used after `MPI_Init` and before `MPI_Finalize`, use `MPI_Wtime()`, produce global MPI summaries on every participating rank, and can emit strict communicator-level text/CSV reports or opt-in sparse union text reports
- A narrow OpenMP carve-out: master-thread-only timer guards for timing a parallel region as a whole
- Downstream consumption through `find_package(fTimer CONFIG REQUIRED)`
- Application-owned instrumentation facades that can select either the real fTimer implementation or a dependency-free no-op implementation at build time

Important limitations are documented later in this README. The short version is that serial and pure-MPI are the core supported stories on current `main`; OpenMP support is intentionally limited to the documented master-thread-only model.

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

Use `ftimer` for the procedural API and `ftimer_types` for shared types and constants such as `ftimer_summary_t`, `ftimer_mpi_summary_t`, `ftimer_mpi_union_summary_t`, `ftimer_metadata_t`, and `FTIMER_MISMATCH_*`.

For metadata headers, construct `ftimer_metadata_t` values by assigning `%key` and `%value` directly. These fields use allocatable-length storage, so assigned strings are not silently capped at the legacy 64-character threshold. fTimer does not currently provide a helper constructor such as `ftimer_metadata(...)`; for formatted numeric metadata, write to a temporary character variable and then assign that string to `%value`.

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

The downstream example under [`tests/install-consumer/`](tests/install-consumer/) is also part of the smoke path. It shows the supported installed-package happy path with `find_package(fTimer CONFIG REQUIRED)`, `use ftimer`, `use ftimer_types`, scoped timing, and summary retrieval from an installed prefix.

The supported source-level module surface is intentionally narrow: `ftimer`, `ftimer_core`, and `ftimer_types`. Their module-level public symbols are checked against `tests/public_symbol_allowlist.txt`; visible implementation helpers are documented as unstable rather than implied stable API. The installed include tree is a curated compiler module artifact set and currently includes `ftimer_clock.mod`, `ftimer_summary.mod`, and `ftimer_mpi.mod` so consumers get a coherent Fortran module set. Those implementation modules are not stable import targets. The installed package includes `share/doc/fTimer/installed-api.md` with the same stability contract and `share/doc/fTimer/LICENSE` with the BSD terms. The smoke tests verify the exact module artifact set and installed documentation artifacts.

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

The public API supports two styles:

- Procedural API from `use ftimer`, including `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_scope`, `ftimer_guard_t`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_mpi_union_summary`, `ftimer_print_summary`, `ftimer_write_summary`, `ftimer_write_summary_csv`, `ftimer_print_mpi_summary`, `ftimer_write_mpi_summary`, `ftimer_write_mpi_summary_csv`, `ftimer_print_mpi_union_summary`, `ftimer_write_mpi_union_summary`, and `ftimer_default_instance`
- OOP API through `type(ftimer_t)` in `ftimer_core`, including the explicit configuration methods `set_clock`, `clear_clock`, `set_callback`, and `clear_callback`
- Shared stable types, constants, and callback/clock interfaces from `ftimer_types`, including the summary/result types and `FTIMER_*` status, event, and mismatch constants

New users should start with the procedural API unless they already know they need instance-level control. Reach for `type(ftimer_t)` when you want multiple independent timer objects, want to avoid the default global instance, or need to manage clock or callback configuration on a specific timer object. Procedural callers that need those advanced controls can use `ftimer_default_instance%...` explicitly.

Some implementation-detail symbols are publicly visible from stable modules because current Fortran module layering requires them: `ftimer_call_stack_t`, `ftimer_context_list_t`, `ftimer_segment_t`, `ftimer_internal_start_scope_activation`, and `ftimer_internal_stop_scope_activation`. They are unstable public-by-necessity names, not supported downstream API. User code should avoid importing them and should rely on `ftimer_scope()`, explicit start/stop calls, and the structured summary result types instead. Test-only helper exports such as `ftimer_test_get_state`, `ftimer_test_set_call_count`, and `ftimer_test_state_t` are confined to `FTIMER_BUILD_TESTS` helper builds.

Operational notes:

- `ierr` is now the last optional argument in the `init` signatures. In MPI builds, the primary communicator form is `type(MPI_Comm)` from `mpi_f08`; integer communicator handles are accepted as transitional compatibility. A single positional integer still binds to that compatibility `comm` path, not `ierr`. Keywords are recommended for readability.
- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`. The MPI build-default clock calls `MPI_Wtime()`, and MPI summaries/reports enter MPI collectives, so initializing, timing, summarizing, reporting, resetting, or finalizing an MPI-enabled timer outside the MPI lifetime is unsupported.
- `init(comm=...)` captures the communicator to use for later MPI summaries and reports, but fTimer stores that communicator as a non-owning handle. It does not call `MPI_Comm_dup` or `MPI_Comm_free` for caller-provided communicators. If you pass a subcommunicator, keep it valid until all fTimer summaries, reports, `finalize()`, or any `init()` reinitialization that may use the old communicator are complete.
- `init`, `reset`, and `finalize` are correctness-first on active timers: with `ierr` they return `FTIMER_ERR_ACTIVE`; without `ierr` they warn and leave state unchanged. In `FTIMER_USE_OPENMP=ON` builds, that diagnostic contract applies on the master thread; worker-thread lifecycle calls remain silent no-ops. These paths do not force-stop active timers or synthesize summary data.
- Stop-mismatch repair remains an explicit `mismatch_mode` choice (`FTIMER_MISMATCH_WARN` or `FTIMER_MISMATCH_REPAIR`); omitted-`ierr` alone does not opt a caller into recovery.
- Timer names are right-trimmed and must be non-empty, must not begin with a blank, and must not contain ASCII control characters. fTimer does not silently truncate timer names and no longer rejects names solely for exceeding the legacy `FTIMER_NAME_LEN = 64` threshold.
- Name-based `start`/`stop` remains the default ergonomic path. The runtime now uses internal mapped lookup for both resident timer names and per-segment parent-stack contexts, plus capacity-based growth, so that this default path avoids repeated resident-timer linear scans and context-list scans in steady state as the timer set and parent-stack variants grow.
- `ftimer_scope(guard, name, ierr)` is a small safety layer for scalar lexical-block timing on the default procedural instance. The guard may stop only the exact activation it started; if that activation was already stopped or displaced by other timer operations, `guard%stop(ierr)` returns `FTIMER_ERR_MISMATCH` and the finalizer warns when it cannot report `ierr`.
- Scoped guards do not replace explicit `start`/`stop`. Guard assignment/copy is unsupported and does not copy or transfer active ownership; assignment involving an active guard warns and leaves ownership with the original guard. Guard arrays, saved/global guards, function-return guard constructors, cross-procedure lifetime patterns, and block-local finalization inside OpenMP parallel regions are unsupported. `ftimer_scope_id` and OOP scoped guards are deferred.
- `lookup()` plus `start_id()`/`stop_id()` remains an optional hot-path optimization when one call site times the same known region in a very tight loop. That path is especially useful when a long scientific label would otherwise be validated and hashed on every name-based call.
- Cached IDs returned by `lookup()` are opaque handles for the current timer runtime state, not segment-array indexes. They remain valid across `reset()`, but `init()` and `finalize()` invalidate them. Calls made while finalized follow the normal `FTIMER_ERR_NOT_INIT` lifecycle contract; after a later successful `init()`, passing a stale cached ID to `start_id()` or `stop_id()` returns `FTIMER_ERR_UNKNOWN` and leaves timer state unchanged.
- Configure custom clocks through `set_clock()` and restore the build-default wall clock through `clear_clock()`. Direct mutation of raw runtime clock internals is not part of the supported API.
- Clock changes are allowed before `init()` or before a run records timing data. If configured before `init()`, the next `init()` starts the local summary window in the selected clock epoch. If changed after `init()` but before timing data exists, `set_clock()` or `clear_clock()` immediately restarts that window in the newly selected clock epoch; the first later `start()` does not move it. Empty local summaries, text reports, and CSV exports therefore use one clock epoch for `summary%total_time` and `% Total`.
- After timing has started, `set_clock()` and `clear_clock()` return `FTIMER_ERR_ACTIVE` (or warn to stderr when `ierr` is omitted) and leave state unchanged. Use `reset()`, `init()`, or `finalize()` to begin a fresh run on a different clock.
- In non-MPI builds, the build-default wall clock is Fortran `system_clock(count, rate)` converted to seconds. fTimer assumes a positive rate and a nondecreasing count during a timing run; it does not clamp backward movement or compensate for counter wrap, so those backend behaviors remain visible in elapsed times and summaries.
- The default serial clock's nominal resolution is `1 / count_rate` seconds and its uninterrupted useful range depends on the compiler/runtime `count_max` and `count_rate`. Current summary schemas and reports do not expose clock-rate or wrap metadata; applications that need to archive toolchain-specific clock characteristics can include them as user metadata.
- Configure callbacks through `set_callback()` and `clear_callback()`. Callback configuration is rejected while timers are active, `clear_callback()` also clears callback `user_data`, and `finalize()` clears callback configuration.
- `get_summary()`, `print_summary()`, and `write_summary()` are local-only summary/reporting paths.
- `get_summary()`, `print_summary()`, and `write_summary()` are live snapshot APIs. They include active local timer contexts through the snapshot timestamp without stopping them, and mark that state with `summary%has_active_timers`, each entry's `is_active`, and, when active entries exist, the formatted report's `Active timers`/`Active` fields. For a final local report, stop all timers first and verify `summary%has_active_timers == .false.`.
- Local summary entries retain preorder formatting compatibility and now expose explicit tree structure through `node_id` and `parent_id`. `node_id` values are stable only within one produced summary object, and roots use `parent_id = 0`.
- Local summary `call_count` fields are signed-64-bit counts. If a timer context ever reaches the signed-64-bit maximum, the next `start` fails with `FTIMER_ERR_UNKNOWN` or the normal omitted-`ierr` warning path rather than wrapping the count.
- `write_summary_csv()` and `ftimer_write_summary_csv()` export local summaries as stable CSV records for dashboards, CI comparisons, plotting, and archives. The text report remains human-facing; consumers should use the CSV or structured Fortran summary rather than scraping fixed-width report output.
- `mpi_summary()` and `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON`, a fully stopped timer set, and collective agreement on the communicator captured by `init`.
- A successful MPI reduction returns a distinct `ftimer_mpi_summary_t` whose fields are globally meaningful on every participating rank.
- The MPI result includes communicator-local rank attribution for total-time extrema and per-entry inclusive-time extrema. Ties resolve to the lowest rank that attains the extremum.
- MPI call-count extrema remain exact `integer(int64)` fields. `avg_call_count` remains `real(wp)` and is computed without integer-sum overflow by reducing exact `integer(int64)` extrema first, then averaging nonnegative deltas from the exact minimum count. The final average is clamped to the representable `real(wp)` conversions of the exact min/max counts. Because `real(wp)` cannot represent every signed-64-bit integer exactly, a near-limit average may differ from the exact integer average by representable real rounding.
- Sparse/union MPI summaries use the separate `mpi_union_summary()` / `ftimer_mpi_union_summary()` API and `ftimer_mpi_union_summary_t` result type. This opt-in path builds a canonical descriptor union across ranks instead of weakening strict `mpi_summary()`.
- `ftimer_mpi_union_summary_t` keeps communicator total-time fields as all-rank statistics. Each entry records `participating_rank_count`; missing rank count is derived as `num_ranks - participating_rank_count`, and entry min/avg/max statistics are defined over participating ranks only.
- Sparse entries are materialized from descriptors emitted by each rank's local summary. Lookup-only timer definitions are not a first-class sparse-registration contract, absent ranks are not zero-filled, and no all-rank amortized compatibility fields are included in the initial result model.
- `print_mpi_union_summary()` / `ftimer_print_mpi_union_summary()` and `write_mpi_union_summary()` / `ftimer_write_mpi_union_summary()` are the explicit sparse text report paths. They build `ftimer_mpi_union_summary_t`, emit one communicator-root report, and display `Participating` plus derived `Missing` rank counts so absent ranks are not confused with zero work.
- Sparse union report entry statistics are over participating ranks only. A present zero-elapsed timer with a real start/stop contributes to participation and call-count statistics; lookup-only names are still not sparse registrations. Sparse CSV export is not part of the current API and is tracked separately in #194.
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
- `examples/openmp_example.F90`: the narrow OpenMP carve-out, where timers bracket the parallel region instead of running inside worker threads

## CSV Export

The first stable machine-readable export format is CSV, chosen because fTimer summaries are snapshot tables rather than event streams. The schema is versioned by the `format_version` column and currently uses version `2`.

Each CSV starts with one header row followed by typed records:

- `record_type=summary` carries run-level fields.
- `record_type=metadata` carries caller-supplied metadata as `key`/`value`.
- `record_type=entry` carries one timer node per row.

Common columns include `summary_kind`, `node_id`, `parent_id`, `depth`, and `name`. Local entry rows populate `inclusive_time`, `self_time`, `call_count`, `avg_time`, `pct_time`, and `is_active`. MPI entry rows populate the reduced fields from `ftimer_mpi_summary_t`, including min/avg/max inclusive and self time, call count extrema, rank-local percent extrema, imbalance fields, and inclusive-time extrema ranks. Local `call_count` and MPI `min_call_count`/`max_call_count` are `integer(int64)` values and are emitted as decimal text without narrowing to default integer. MPI `avg_call_count` remains a real-valued CSV field. CSV format version `2` is the compatibility signal for those widened integer count ranges; consumers should parse local `call_count` and MPI call-count extrema fields as at least signed 64-bit decimal integers.

Appending to an existing non-empty CSV requires the existing first row to match the fTimer CSV format-version-2 header, existing rows to be well-formed CSV logical records with the exact v2 header field count and recognized `summary_kind`/`record_type` combinations, and the target to end with a newline; mismatched headers, older-format records, malformed v2 record shape or quote placement, or unterminated final records are rejected instead of mixing schemas silently. Append validation is a schema-shape and CSV-syntax guard for existing files, not a semantic reparse of every numeric, logical, or timing payload field already present. CSV text fields emit the same trimmed timer names and metadata key/value text used by fTimer reports, with standard CSV quoting. They are not spreadsheet-formula-sanitized, so treat CSV opened in spreadsheet software as data from the generating program.

Example:

```fortran
call ftimer_write_summary_csv("ftimer-summary.csv", ierr=ierr)

! In an FTIMER_USE_MPI=ON build, collectively writes from communicator root.
call ftimer_write_mpi_summary_csv("ftimer-mpi-summary.csv", ierr=ierr)
```

Sparse/union MPI summaries currently expose machine-readable data through `ftimer_mpi_union_summary_t`. Use `ftimer_write_mpi_union_summary()` for human-readable sparse text reports; sparse CSV export is intentionally deferred to #194 until the CSV schema has explicit participation columns.

## Build And Test

Minimum requirements:

- CMake 3.16 or newer
- A Fortran compiler with preprocess support
- pFUnit only when `FTIMER_BUILD_TESTS=ON`
- An MPI wrapper/compiler pair only when `FTIMER_USE_MPI=ON`
- GNU Fortran only when `FTIMER_USE_OPENMP=ON`

```bash
# Smoke-test path (includes install/export consumer verification)
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure

# Serial build with pFUnit tests
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure

# MPI build with pFUnit tests
FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi

# OpenMP build with pFUnit tests
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
ctest --test-dir build-openmp --output-on-failure

# Convenience Makefile wrapper
make
make mpi
make openmp
make test
```

The smoke-test path also runs the enabled and disabled instrumentation facade examples so the documented compile-out strategy stays buildable.

Supported toolchain matrix:

- Serial smoke/library build: GNU Fortran and LLVM Flang are validated in automation
- Serial plus pFUnit tests: GNU Fortran with a matching pFUnit installation
- MPI: an MPI wrapper compiler such as `mpifort`
- OpenMP: GNU Fortran only for the documented master-thread-only carve-out

Other serial compilers may still work, but they are not part of the current release-validated matrix unless the repo adds direct automation for them.

Use a separate build directory for each compiler or mode. Reconfiguring the same build tree with a different Fortran compiler is not a supported workflow in this repository.

## Current Limitations And Contracts

- CMake is the supported build and package path. FPM support is intentionally deferred.
- fTimer is wall-clock only. It does not synchronize asynchronous accelerator/device work, so callers must perform any required device synchronization before `stop` when they intend to measure completed device work rather than host launch/enqueue latency.
- fTimer does not insert MPI barriers around timed regions. MPI summaries reduce rank-local intervals; callers must add any desired MPI synchronization themselves when they intend to measure a synchronized global phase.
- `FTIMER_USE_MPI=ON` is intended for wrapper-compiler setups such as `FC=mpifort`. Configure now fails early if the active compiler cannot compile a minimal `mpi_f08` probe against the discovered MPI installation, or if that `mpi_f08` path cannot compile the `MPI_Type_match_size`/`MPI_ERRORS_RETURN` calls fTimer uses to validate reduction datatypes.
- The current primary MPI interface contract is `mpi_f08` with `type(MPI_Comm)` communicator handles captured at `init`. Legacy integer communicator handles are accepted as transitional compatibility pending #187; `mpif.h` is not a supported interface path.
- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`. The runtime does not currently provide a separate pre-init/post-finalize guard contract for all MPI clock and collective entry points.
- Communicators passed to `init(comm=...)` remain owned by the caller. fTimer stores a non-owning handle and may use it later in `mpi_summary()`, `mpi_union_summary()`, MPI report writers, `finalize()`, or reinitialization. Do not free a subcommunicator until those fTimer operations that could use it are complete.
- MPI summary reductions select MPI datatypes with `MPI_Type_match_size` for fTimer's actual `real(wp)` and `integer(int64)` storage sizes instead of assuming fixed `MPI_DOUBLE_PRECISION`, `MPI_2DOUBLE_PRECISION`, or `MPI_INTEGER8` mappings. The compile-time MPI probe validates that this API is available through the `mpi_f08` path; if the API exists but no matching runtime datatype can be returned, `mpi_summary()` temporarily requests MPI error returns for the datatype lookup, fails with `FTIMER_ERR_UNKNOWN`, and leaves the MPI result empty.
- `mpi_summary()` now returns a distinct `ftimer_mpi_summary_t`; it does not fall back to a local `ftimer_summary_t` on MPI-disabled or MPI-error paths. Call `get_summary()` separately if you need local data in those cases.
- Descriptor-preflight failures inside one communicator now report the disagreeing communicator-local ranks in the omitted-`ierr` diagnostic path when possible.
- Rank-conditional timer reductions are not supported by the strict `mpi_summary()` API. Use the separate opt-in `mpi_union_summary()` / `ftimer_mpi_union_summary()` API with `ftimer_mpi_union_summary_t` for sparse descriptor-union reductions. See [`docs/mpi-sparse-summary-decision.md`](docs/mpi-sparse-summary-decision.md).
- Local summary `node_id` values are not a cross-run identity contract. Treat them as explicit links inside one produced summary object, not as durable ids across separate runs or independently produced summaries.
- All ranks that participate in `mpi_summary()` must agree on the communicator captured by `init`. If would-be participants diverge onto different communicators, the library cannot safely discover that mistake after the split; the practical failure mode is a hang, not a clean local fallback.
- `FTIMER_USE_OPENMP=ON` enables only limited master-thread-only guards. Worker-thread timer calls inside an OpenMP parallel region are silent no-ops. To time a parallel region as a whole, place `start`/`stop` outside the `!$omp parallel` block.
- `FTIMER_USE_OPENMP` is the source-level switch for that carve-out; global OpenMP compiler flags alone do not enable the guards when the option is `OFF`.
- The OpenMP path does not make fTimer thread-safe, does not provide thread-local timer instances, and should not be read as a general hybrid MPI+OpenMP timing model.
- Future real hybrid MPI+OpenMP timing is deferred pending concrete adopter demand; see [`docs/openmp-hybrid-strategy-decision.md`](docs/openmp-hybrid-strategy-decision.md).
- `on_event` remains a lightweight intra-run hook, not a serious profiler-backend integration contract with stable semantic timer identity.
- If `FTIMER_USE_MPI=OFF`, `mpi_summary()` and `mpi_union_summary()` return `FTIMER_ERR_NOT_IMPLEMENTED` and leave their MPI result objects empty. MPI report APIs, including the sparse union report APIs, return `FTIMER_ERR_NOT_IMPLEMENTED` without emitting report output or creating/replacing report files.
- Formatted local and MPI report output are separate paths: `print_summary()`/`write_summary()` are local, `print_mpi_summary()`/`write_mpi_summary()` are strict MPI reports, and `print_mpi_union_summary()`/`write_mpi_union_summary()` are opt-in sparse MPI union reports. MPI reports are deliberately abbreviated; `ftimer_mpi_summary_t` and `ftimer_mpi_union_summary_t` remain the complete structured data models.

## Performance Measurement

The repository includes a standalone benchmark harness for measuring timer overhead and summary-generation cost:

```bash
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
```

This is useful for before/after regression checks when changing hot-path timing behavior. Compare the name-based lookup-scaling rows across resident timer counts to confirm the mapped default path stays much flatter than the old linear-scan baseline, and compare the context-scaling rows across larger `C` values to see how one hot timer behaves when it is reused under many distinct parent stacks. The first-touch rows measure the remaining allocation/growth cost for newly discovered timer names and parent-stack contexts after setup has prebuilt labels and initialized independent timer objects. The long-name rows show the extra validation/hash cost for labels above the legacy threshold. The flat name-based/id-based rows still help judge whether the optional cached-id path is worth it for one especially hot loop.

## More Detail

- Runtime semantics: [`docs/semantics.md`](docs/semantics.md)
- Current architecture reference: [`docs/design.md`](docs/design.md)
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
