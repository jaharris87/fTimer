# fTimer

fTimer is a lightweight, correctness-first wall-clock timing library for modern Fortran. Current `main` is positioned first for disciplined serial and pure-MPI codes that need hierarchical timers, predictable accounting, and summaries you can inspect programmatically instead of scraping from ad hoc text output.

> Current product position: fTimer's core supported stories are serial timing and pure-MPI timing. `FTIMER_USE_OPENMP=ON` is a narrow master-thread-only carve-out for bracketing a parallel region as a whole, not a general hybrid MPI+OpenMP timing model. The callback hook is a lightweight intra-run event hook, not a stable external-profiler integration contract.

For a first release, the focus is a small, dependable core:

- strict, stack-based start/stop timing by default
- context-sensitive accounting for the same timer name under different parents
- inclusive and self time in structured summaries with explicit tree linkage
- procedural wrappers and an OOP core API
- optional MPI global summaries plus first-class MPI report output
- an installable CMake package for downstream projects

## Why Use fTimer

fTimer fits best when you want timing behavior you can trust:

- nested timers are treated as a real hierarchy, not a flat label list
- mismatch handling is explicit and configurable (`strict`, `warn`, `repair`)
- summaries are available as data first (`get_summary()`), with text formatting layered on top
- local summary entries retain formatter-friendly preorder `name`/`depth` data and also expose explicit `node_id`/`parent_id` tree links
- pure-MPI reductions return a distinct `ftimer_mpi_summary_t` with globally meaningful fields on every participating rank
- an injectable clock supports deterministic tests and controlled benchmarking
- optional callback hooks let in-process code observe normal timer start/stop events during a run

If you need a tiny serial timing helper, you can use fTimer that way. If you need structured local summaries, opt-in pure-MPI reductions, and a clear error contract, that is where the library is strongest.

## Supported Workflows

fTimer currently supports these usage paths:

- Serial timing with local summaries and formatted reports
- Pure-MPI builds on the validated `use mpi` path that use `MPI_Wtime()`, produce global MPI summaries on every participating rank, and can emit communicator-level MPI reports
- A narrow OpenMP carve-out: master-thread-only timer guards for timing a parallel region as a whole
- Downstream consumption through `find_package(fTimer CONFIG REQUIRED)`

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

Use `ftimer` for the procedural API and `ftimer_types` for shared types and constants such as `ftimer_summary_t`, `ftimer_mpi_summary_t`, `ftimer_metadata_t`, and `FTIMER_MISMATCH_*`.

For metadata headers, construct `ftimer_metadata_t` values by assigning `%key` and `%value` directly. fTimer does not currently provide a helper constructor such as `ftimer_metadata(...)`.

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
Total time (s) : <small positive number>

Timer name  Inclusive (s)     Self (s)    Calls   % Total
---------------------------------------------------------
work            <positive>      <positive>       1   <nonzero>
```

The exact timings vary by machine and compiler, but a successful run should show:

- one recorded timer
- a positive total time
- a `work` row with one call and positive inclusive/self time

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

The downstream example under [`tests/install-consumer/`](tests/install-consumer/) is also part of the smoke path. It shows the supported installed-package happy path with `find_package(fTimer CONFIG REQUIRED)`, `use ftimer_types`, timer start/stop calls, and summary retrieval from an installed prefix.

The supported source-level module surface is intentionally narrow: `ftimer`, `ftimer_core`, and `ftimer_types`. Some install trees may still contain compiler module artifacts for implementation modules such as `ftimer_clock`, `ftimer_summary`, and `ftimer_mpi`, but those are internal implementation details, not stable user-facing API. The current validated toolchain matrix does not require any extra compiler-specific companion artifacts in the installed include tree. If a future compiler proves that such artifacts are truly required for downstream consumption, they should be added deliberately and documented as an explicit exception rather than leaked accidentally.

## API Surface

The public API supports two styles:

- Procedural API from `use ftimer`, including `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_print_summary`, `ftimer_write_summary`, `ftimer_print_mpi_summary`, `ftimer_write_mpi_summary`, and `ftimer_default_instance`
- OOP API through `type(ftimer_t)` in `ftimer_core`, including the explicit configuration methods `set_clock`, `clear_clock`, `set_callback`, and `clear_callback`

New users should start with the procedural API unless they already know they need instance-level control. Reach for `type(ftimer_t)` when you want multiple independent timer objects, want to avoid the default global instance, or need to manage clock or callback configuration on a specific timer object. Procedural callers that need those advanced controls can use `ftimer_default_instance%...` explicitly.

Operational notes:

- `ierr` is now the last optional argument in both `init` signatures (`comm`, `mismatch_mode`, `ierr`), so a single positional integer binds to `comm`, not `ierr`. Keywords are recommended for readability.
- `init`, `reset`, and `finalize` are correctness-first on active timers: with `ierr` they return `FTIMER_ERR_ACTIVE`; without `ierr` they warn and leave state unchanged. In `FTIMER_USE_OPENMP=ON` builds, that diagnostic contract applies on the master thread; worker-thread lifecycle calls remain silent no-ops. These paths do not force-stop active timers or synthesize summary data.
- Stop-mismatch repair remains an explicit `mismatch_mode` choice (`FTIMER_MISMATCH_WARN` or `FTIMER_MISMATCH_REPAIR`); omitted-`ierr` alone does not opt a caller into recovery.
- Name-based `start`/`stop` remains the default ergonomic path. The runtime now uses internal mapped lookup for both resident timer names and per-segment parent-stack contexts, plus capacity-based growth, so that this default path avoids repeated resident-timer linear scans and context-list scans in steady state as the timer set and parent-stack variants grow.
- `lookup()` plus `start_id()`/`stop_id()` remains an optional hot-path optimization when one call site times the same known region in a very tight loop.
- Configure custom clocks through `set_clock()` and restore the build-default wall clock through `clear_clock()`. Direct mutation of raw runtime clock internals is not part of the supported API.
- Clock changes are allowed before `init()` or before a run records timing data. After timing has started, `set_clock()` and `clear_clock()` return `FTIMER_ERR_ACTIVE` (or warn to stderr when `ierr` is omitted) and leave state unchanged. Use `reset()`, `init()`, or `finalize()` to begin a fresh run on a different clock.
- Configure callbacks through `set_callback()` and `clear_callback()`. Callback configuration is rejected while timers are active, `clear_callback()` also clears callback `user_data`, and `finalize()` clears callback configuration.
- `get_summary()`, `print_summary()`, and `write_summary()` are local-only summary/reporting paths.
- Local summary entries retain preorder formatting compatibility and now expose explicit tree structure through `node_id` and `parent_id`. `node_id` values are stable only within one produced summary object, and roots use `parent_id = 0`.
- `mpi_summary()` and `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON`, a fully stopped timer set, and collective agreement on the communicator captured by `init`.
- A successful MPI reduction returns a distinct `ftimer_mpi_summary_t` whose fields are globally meaningful on every participating rank.
- The MPI result includes communicator-local rank attribution for total-time extrema and per-entry inclusive-time extrema. Ties resolve to the lowest rank that attains the extremum.
- `print_mpi_summary()` and `write_mpi_summary()` are the first-class MPI reporting paths. They perform the collective MPI summary build and emit one report from communicator root.
- Callbacks configured on `type(ftimer_t)` are lightweight intra-run hooks. They report normal start/stop events with runtime-local numeric ids; current `main` does not promise a stable semantic id-to-name/path mapping for profiler backends or durable cross-run tooling.
- Import shared types and constants from `ftimer_types`; `use ftimer` does not re-export them.

## Examples

- `examples/basic_usage.F90`: serial start/stop plus summary retrieval and formatted output
- `examples/nested_timers.F90`: nested timers and metadata headers
- `examples/mpi_example.F90`: pure-MPI timing with a global MPI summary object and first-class MPI report output
- `examples/openmp_example.F90`: the narrow OpenMP carve-out, where timers bracket the parallel region instead of running inside worker threads

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

Supported toolchain matrix:

- Serial smoke/library build: GNU Fortran and LLVM Flang are validated in automation
- Serial plus pFUnit tests: GNU Fortran with a matching pFUnit installation
- MPI: an MPI wrapper compiler such as `mpifort`
- OpenMP: GNU Fortran only for the documented master-thread-only carve-out

Other serial compilers may still work, but they are not part of the current release-validated matrix unless the repo adds direct automation for them.

Use a separate build directory for each compiler or mode. Reconfiguring the same build tree with a different Fortran compiler is not a supported workflow in this repository.

## Current Limitations And Contracts

- CMake is the supported build and package path. FPM support is intentionally deferred.
- `FTIMER_USE_MPI=ON` is intended for wrapper-compiler setups such as `FC=mpifort`. Configure now fails early if the active compiler cannot compile a minimal `use mpi` probe against the discovered MPI installation.
- The current validated MPI interface contract is the `use mpi` path with integer communicator handles captured at `init`. Broader `mpif.h` or `mpi_f08` compatibility is not yet part of the documented release contract.
- `mpi_summary()` now returns a distinct `ftimer_mpi_summary_t`; it does not fall back to a local `ftimer_summary_t` on MPI-disabled or MPI-error paths. Call `get_summary()` separately if you need local data in those cases.
- Descriptor-preflight failures inside one communicator now report the disagreeing communicator-local ranks in the omitted-`ierr` diagnostic path when possible.
- Local summary `node_id` values are not a cross-run identity contract. Treat them as explicit links inside one produced summary object, not as durable ids across separate runs or independently produced summaries.
- All ranks that participate in `mpi_summary()` must agree on the communicator captured by `init`. If would-be participants diverge onto different communicators, the library cannot safely discover that mistake after the split; the practical failure mode is a hang, not a clean local fallback.
- `FTIMER_USE_OPENMP=ON` enables only limited master-thread-only guards. Worker-thread timer calls inside an OpenMP parallel region are silent no-ops. To time a parallel region as a whole, place `start`/`stop` outside the `!$omp parallel` block.
- The OpenMP path does not make fTimer thread-safe, does not provide thread-local timer instances, and should not be read as a general hybrid MPI+OpenMP timing model.
- `on_event` remains a lightweight intra-run hook, not a serious profiler-backend integration contract with stable semantic timer identity.
- If `FTIMER_USE_MPI=OFF`, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` and leaves the MPI result empty.
- Formatted local and MPI report output are separate paths: `print_summary()`/`write_summary()` are local, while `print_mpi_summary()`/`write_mpi_summary()` emit communicator-level MPI reports from root.

## Performance Measurement

The repository includes a standalone benchmark harness for measuring timer overhead and summary-generation cost:

```bash
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
```

This is useful for before/after regression checks when changing hot-path timing behavior. Compare the name-based lookup-scaling rows across resident timer counts to confirm the mapped default path stays much flatter than the old linear-scan baseline, and compare the context-scaling rows across larger `C` values to see how one hot timer behaves when it is reused under many distinct parent stacks. The flat name-based/id-based rows still help judge whether the optional cached-id path is worth it for one especially hot loop.

## More Detail

- Runtime semantics: [`docs/semantics.md`](docs/semantics.md)
- Current architecture reference: [`docs/design.md`](docs/design.md)

When current-state sources disagree, use this repository-wide precedence order:

1. current code under `src/`
2. current behavioral tests
3. `docs/semantics.md`
4. `README.md`
5. `docs/design.md`

## License

BSD-3-Clause. See [LICENSE](LICENSE).
