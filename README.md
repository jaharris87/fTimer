# fTimer

fTimer is a lightweight, correctness-first wall-clock timing library for modern Fortran. It is strongest today when you want a dependable way to time named regions in a serial code or a pure-MPI code and inspect the result as structured summary data instead of scraping ad hoc text output.

If you are deciding whether fTimer fits your codebase, start with the serial path below. You can get to a first successful timing result without MPI, pFUnit, or a long mode-selection read, then move to MPI, OpenMP, CSV, or install-package details only if you need them.

> Current product position: serial timing and pure-MPI timing are the core supported stories on current `main`. `FTIMER_USE_OPENMP=ON` keeps the existing procedural and `ftimer_core` APIs on a master-thread-only compatibility carve-out, while `ftimer_openmp_t` is the explicit opt-in surface for serial-lane and level-1 OpenMP worker timing, local OpenMP summaries/reports/CSV, and strict or sparse MPI+OpenMP rank/lane summaries over its captured communicator. The callback hook remains a lightweight intra-run event hook, not a stable external-profiler integration contract.

## Why Use fTimer

fTimer fits best when you want timing behavior you can trust:

- nested timers are treated as a real hierarchy, not a flat label list
- mismatch handling is explicit and configurable (`strict`, `warn`, `repair`)
- summaries are available as data first (`get_summary()`), with text formatting layered on top
- local summaries expose inclusive time, self time, call counts, and tree structure without forcing you into a text-only workflow
- pure-MPI reductions and sparse rank-conditional reductions are available when your serial instrumentation needs to grow into communicator-level reporting
- an injectable clock supports deterministic tests and controlled benchmarking

If you need a tiny serial timing helper, you can use fTimer that way. If you need structured local summaries, optional MPI reductions, and a clear error contract, that is where the library is strongest.

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

Local summaries are live snapshots, so stop all timers before you treat the output as a final report.

If the first build, MPI path, OpenMP path, CSV export, or first example fails,
see the symptom-oriented [`docs/troubleshooting.md`](docs/troubleshooting.md)
guide before digging into the full semantics reference.

## Quick Start

The smallest procedural example looks like this:

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

Use `ftimer` for the procedural API and `ftimer_types` for shared types and constants such as `ftimer_summary_t`, `ftimer_context_diagnostic_t`, `ftimer_mpi_summary_t`, `ftimer_mpi_union_summary_t`, `ftimer_metadata_t`, and `FTIMER_MISMATCH_*`.

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

For metadata headers, construct `ftimer_metadata_t` values by assigning `%key` and `%value` directly. These fields use allocatable-length storage, so assigned strings are not silently capped at the legacy 64-character threshold. Human-readable text reports escape metadata C0/C1 control bytes, UTF-8 encoded C1 controls, terminal escape bytes, backslashes, and leading blanks with the same visible policy used for formatted timer names, while valid non-control UTF-8 text is preserved. fTimer does not currently provide a helper constructor such as `ftimer_metadata(...)`; for formatted numeric metadata, write to a temporary character variable and then assign that string to `%value`.

## Where To Go Next

Use the shortest path that matches your role:

- First-time user: stay in this README for `First Success`, `Quick Start`, and `Install And Use From Another Project`, then see the symptom-oriented [`docs/troubleshooting.md`](docs/troubleshooting.md) guide if first use goes sideways.
- Advanced user: use [Supported Workflows](#supported-workflows) to choose a mode, then jump to [`docs/semantics.md`](docs/semantics.md), [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md), [`docs/csv-schema.md`](docs/csv-schema.md), or [`docs/installed-api.md`](docs/installed-api.md) for the exact contract.
- Maintainer or release reviewer: use [`docs/release-evidence.md`](docs/release-evidence.md), [`docs/release.md`](docs/release.md), and [`docs/maintainer.md`](docs/maintainer.md).
- Coding agent: use [`AGENTS.md`](AGENTS.md) or [`CLAUDE.md`](CLAUDE.md) for repo workflow and source-of-truth rules, then read [`docs/semantics.md`](docs/semantics.md) and [`docs/maintainer.md`](docs/maintainer.md) as needed.

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

The supported downstream contract is the installed CMake package export. New adopters should not need to infer the consumption model from the test suite.

Pre-1.0 CMake package compatibility is intentionally limited to the same minor release line. For example, a `0.2.z` install may satisfy `find_package(fTimer 0.2 CONFIG REQUIRED)` or an older compatible `0.2.x` request, but it will not satisfy a `0.1.x`, `0.3.x`, or later-minor request. Versionless `find_package(fTimer CONFIG REQUIRED)` remains available for consumers that deliberately accept whichever installed fTimer package appears on `CMAKE_PREFIX_PATH`.

The downstream examples under [`tests/install-consumer/`](tests/install-consumer/) stay in the smoke path as the supported installed-package happy path. For the full installed-module stability contract, public symbol boundary, installed docs/artifacts, and pre-1.0 compatibility notes, see [`docs/installed-api.md`](docs/installed-api.md).

## Supported Workflows

fTimer currently supports a small set of distinct stories:

- Serial/local timing through `ftimer` or `ftimer_core`
- Strict pure-MPI timing and sparse pure-MPI union timing on the validated `mpi_f08` path
- OpenMP compatibility timing through the existing APIs when one timer brackets a parallel region
- Explicit worker timing through `ftimer_openmp_t`, including strict and sparse MPI+OpenMP report families
- Downstream consumption through `find_package(fTimer CONFIG REQUIRED)`
- Application-owned instrumentation facades that can select either the real fTimer implementation or a dependency-free no-op implementation at build time

Choose the smallest mode that matches the measurement you need. Start with serial, add strict MPI only when every rank shares the same descriptor tree, add sparse MPI union when participation is rank-conditional, keep existing OpenMP calls outside the parallel region for compatibility timing, and use `ftimer_openmp_t` only when you need per-lane worker data.

CSV schemas follow the same split: local/strict MPI share one v2 family, while sparse MPI union, local OpenMP, strict MPI+OpenMP, and sparse MPI+OpenMP union each use dedicated schemas that are not append-compatible with one another.

For the full OpenMP and hybrid lifecycle, accepted source shapes, and migration guidance, see [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md).

## Operational Support Matrix

Support tiers still matter, but the detailed claim ledger lives outside the README:

- **Core validated** today: serial/library smoke, installed consumer coverage, and pure-MPI on the documented GNU wrapper path.
- **Supported advanced**: OpenMP compatibility through `ftimer` / `ftimer_core`, plus explicit worker timing and strict/sparse MPI+OpenMP reporting through `ftimer_openmp_t`.
- **Plausible but unvalidated**: compiler, MPI, or OpenMP combinations not yet backed by direct automation or recorded local evidence.
- **Experimental/deferred**: package-manager installs, profiler backends, hardware counters, traces, dashboards, and similar ecosystem work.
- Exact status, evidence, and caveats for each release-facing claim live in [`docs/release-evidence.md`](docs/release-evidence.md). Use that ledger, not this README, when you need release-review wording.

For failure-oriented guidance, see [`docs/troubleshooting.md`](docs/troubleshooting.md). For architecture and validation context, see [`docs/design.md`](docs/design.md). For installed package stability details, see [`docs/installed-api.md`](docs/installed-api.md).

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

The stable source-level import surfaces are `ftimer`, `ftimer_core`, `ftimer_openmp`, and `ftimer_types`.

- Start with `use ftimer` unless you already need instance-level control.
- Use `ftimer_core` for `type(ftimer_t)`, clock/callback configuration, or pointer-based scoped timing with `ftimer_oop_guard_t` and `ftimer_oop_scope`.
- Use `ftimer_openmp` only for the explicit opt-in worker-timing API, not as a general replacement for the existing procedural path.
- Use `ftimer_types` for shared summary types, status codes, mismatch constants, and callback/clock interfaces.
- Some helper names remain public by necessity, but they are not stable downstream API. The exact stable/unstable/test-only split lives in [`docs/installed-api.md`](docs/installed-api.md).

A few contract details are worth keeping visible here:

- `ierr` is now the last optional argument in the `init` signatures. In MPI builds, communicator capture uses `comm :: type(MPI_Comm)` from `mpi_f08`; integer communicator handles are not accepted. Integer `init` options such as `mismatch_mode` and `ierr` must be passed by keyword so legacy positional communicator handles cannot be mistaken for supported options. Keywords are recommended for readability on all `init` calls.
- `ftimer_openmp_t%init` requires `config=` and accepts `comm=` only by keyword in MPI builds. Omitted `comm=` captures `MPI_COMM_WORLD`, while local OpenMP summaries remain separate from the MPI and local-summary families.
- `ftimer_scope(guard, name, ierr)` and `ftimer_oop_scope(timer_pointer, guard, name, ierr)` are the scoped helpers. Keep explicit `start`/`stop` as the primary OOP API when ownership is not purely lexical.

For the exhaustive symbol list, installed `.mod` artifact contract, public-surface change map, and detailed API notes, see [`docs/installed-api.md`](docs/installed-api.md).

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

CSV is the first stable machine-readable export format because fTimer summaries are snapshot tables rather than event streams.

- Local and strict MPI share the `format_version=2` family.
- Sparse MPI union, local OpenMP, strict MPI+OpenMP, and sparse MPI+OpenMP union each use their own dedicated schema families.
- Those families are intentionally not append-compatible with one another.
- Missing sparse ranks or lanes are explicit participation metadata, not zero-filled samples.

See [`docs/csv-schema.md`](docs/csv-schema.md) for the compact field dictionary, schema-family signatures, denominator choices, active snapshot fields, append constraints, and the tiny reader-aid fixtures used by the docs checks.

For machine consumption, prefer structured summaries or CSV. Treat the fixed-width text reports as human-facing output.

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

- Serial smoke/library build: GNU Fortran and LLVM Flang are validated in automation.
- Serial plus pFUnit tests: GNU Fortran with a matching pFUnit installation.
- OpenMP: GNU Fortran plus LLVM Flang coverage for the documented compatibility and worker examples.
- MPI and MPI+OpenMP: see [`docs/release-evidence.md`](docs/release-evidence.md) for the exact OpenMPI/MPICH scope, CI coverage, and caveats.

Other serial compilers may still work, but they are not part of the current release-validated matrix unless the repo adds direct automation for them.

Use a separate build directory for each compiler or mode. Reconfiguring the same build tree with a different Fortran compiler is not a supported workflow in this repository.

## Current Limitations And Contracts

- CMake is the supported build and package path. FPM support is intentionally deferred.
- fTimer is wall-clock only. It does not synchronize asynchronous accelerator/device work, and it does not insert MPI barriers around timed regions.
- The current MPI interface contract is `mpi_f08` with `type(MPI_Comm)` communicator handles captured at `init`. Legacy integer communicator handles and `mpif.h` are not supported interface paths.
- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`.
- `init(comm=...)` captures a caller-selected communicator for later MPI summaries and reports, and fTimer stores that communicator as a non-owning handle.
- `FTIMER_USE_OPENMP=ON` keeps the existing `ftimer` / `ftimer_core` APIs on the master-thread-only compatibility carve-out. Worker-thread calls through those existing APIs are silent no-ops.
- Use `ftimer_openmp_t` when you need serial-lane or level-1 worker timing, stopped-run local OpenMP summaries, or strict/sparse MPI+OpenMP hybrid reports.
- `on_event` remains a lightweight intra-run hook, not a serious profiler-backend integration contract with stable semantic timer identity.

The full runtime contract, reporting details, error-model edge cases, and OpenMP migration guidance live in [`docs/semantics.md`](docs/semantics.md), [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md), and [`docs/installed-api.md`](docs/installed-api.md).

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

Use the benchmark harness for before/after trend checks when a change touches start/stop hot paths, lookup or cached-id behavior, context growth, summary/report/CSV formatting, or MPI/OpenMP timing internals.

The detailed release policy and provenance-sidecar expectations live in [`docs/release.md`](docs/release.md). The current support boundary and evidence status for benchmark claims live in [`docs/release-evidence.md`](docs/release-evidence.md).

The harness records trend evidence, not pass/fail thresholds, and GitHub-hosted runner numbers should be treated cautiously because absolute timings are noisy.

## More Detail

- Runtime semantics: [`docs/semantics.md`](docs/semantics.md)
- Troubleshooting guide: [`docs/troubleshooting.md`](docs/troubleshooting.md)
- Current architecture reference: [`docs/design.md`](docs/design.md)
- Installed API stability and public symbol boundary: [`docs/installed-api.md`](docs/installed-api.md)
- CSV schema dictionary: [`docs/csv-schema.md`](docs/csv-schema.md)
- OpenMP timing modes and migration guide: [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md)
- Release claim evidence: [`docs/release-evidence.md`](docs/release-evidence.md)
- Maintainer workflow: [`docs/maintainer.md`](docs/maintainer.md)
- Release checklist and artifact policy: [`docs/release.md`](docs/release.md)
- Coding-agent workflow guide: [`AGENTS.md`](AGENTS.md), [`CLAUDE.md`](CLAUDE.md)
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
