# fTimer

fTimer is a lightweight, correctness-first wall-clock timing library for modern Fortran. It is built for codes that need hierarchical timers, predictable accounting, and summaries you can inspect programmatically instead of scraping from ad hoc text output.

For a first release, the focus is a small, dependable core:

- strict, stack-based start/stop timing by default
- context-sensitive accounting for the same timer name under different parents
- inclusive and self time in structured summaries
- procedural wrappers and an OOP core API
- optional MPI summary reduction for cross-rank min/max/avg/imbalance data
- an installable CMake package for downstream projects

## Why Use fTimer

fTimer fits best when you want timing behavior you can trust:

- nested timers are treated as a real hierarchy, not a flat label list
- mismatch handling is explicit and configurable (`strict`, `warn`, `repair`)
- summaries are available as data first (`get_summary()`), with text formatting layered on top
- an injectable clock supports deterministic tests and controlled benchmarking
- callback hooks let external tools react to timer start/stop events

If you need a tiny serial timing helper, you can use fTimer that way. If you need structured local summaries, optional MPI reductions, and a clear error contract, that is where the library is strongest.

## Supported Workflows

fTimer currently supports these usage paths:

- Serial timing with local summaries and formatted reports
- MPI builds that use `MPI_Wtime()` and can populate root-side reduced timing fields
- OpenMP builds with master-thread-only timer guards for timing a parallel region as a whole
- Downstream consumption through `find_package(fTimer CONFIG REQUIRED)`

Important limitations are documented later in this README. The short version is that MPI support is real but opt-in, and OpenMP support is intentionally limited to the documented master-thread-only model.

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

Use `ftimer` for the procedural API and `ftimer_types` for shared types and constants such as `ftimer_summary_t`, `ftimer_metadata_t`, `FTIMER_MISMATCH_*`, and `FTIMER_MPI_SUMMARY_*`.

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

## API Surface

The public API supports two styles:

- Procedural API from `use ftimer`, including `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_print_summary`, `ftimer_write_summary`, and `ftimer_default_instance`
- OOP API through `type(ftimer_t)` in `ftimer_core`

Operational notes:

- `ierr` is now the last optional argument in both `init` signatures (`comm`, `mismatch_mode`, `ierr`), so a single positional integer binds to `comm`, not `ierr`. Keywords are recommended for readability.
- `get_summary()`, `print_summary()`, and `write_summary()` are local-only summary/reporting paths.
- `mpi_summary()` and `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON`, a fully stopped timer set, and collective agreement on the communicator captured by `init`.
- On a successful MPI reduction, reduced `min_time`, `max_time`, `avg_across_ranks`, and `imbalance` fields are populated only on communicator root.
- Import shared types and constants from `ftimer_types`; `use ftimer` does not re-export them.

## Examples

- `examples/basic_usage.F90`: serial start/stop plus summary retrieval and formatted output
- `examples/nested_timers.F90`: nested timers and metadata headers
- `examples/mpi_example.F90`: MPI timing with root-side reduced summary fields
- `examples/openmp_example.F90`: the supported OpenMP pattern, where timers bracket the parallel region instead of running inside worker threads

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

- Serial smoke/library build: any Fortran compiler that can build the project normally
- Serial plus pFUnit tests: GNU Fortran with a matching pFUnit installation
- MPI: an MPI wrapper compiler such as `mpifort`
- OpenMP: GNU Fortran only for the documented supported path

Use a separate build directory for each compiler or mode. Reconfiguring the same build tree with a different Fortran compiler is not a supported workflow in this repository.

## Current Limitations And Contracts

- CMake is the supported build and package path. FPM support is intentionally deferred.
- `FTIMER_USE_MPI=ON` is intended for wrapper-compiler setups such as `FC=mpifort`. Configure now fails early if the active compiler cannot compile a minimal `use mpi` probe against the discovered MPI installation.
- `mpi_summary()` does not produce a fully global summary object on every rank. After a successful collective, local summary fields still describe the calling rank's local data; only communicator root also receives reduced cross-rank fields.
- `FTIMER_USE_OPENMP=ON` enables limited master-thread-only guards. Worker-thread timer calls inside an OpenMP parallel region are silent no-ops. To time a parallel region as a whole, place `start`/`stop` outside the `!$omp parallel` block.
- OpenMP support does not make fTimer thread-safe and does not provide thread-local timer instances.
- If `FTIMER_USE_MPI=OFF`, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` and leaves the result local-only.
- Formatted summary/report output is local-only.

## Performance Measurement

The repository includes a standalone benchmark harness for measuring timer overhead and summary-generation cost:

```bash
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
```

This is useful for before/after regression checks when changing hot-path timing behavior.

## More Detail

- Runtime semantics: [`docs/semantics.md`](docs/semantics.md)
- Forward-looking design notes: [`docs/design.md`](docs/design.md)

When those sources disagree, the current implementation under `src/` is the source of truth.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
