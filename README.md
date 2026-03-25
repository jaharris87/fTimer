# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

> **When to read this**
>
> Read this file when you need the public-facing overview of `fTimer`: current capabilities on `main`, quick-start usage, build/install guidance, examples, and user-visible behavior.
>
> Do **not** treat this file as the canonical detailed runtime contract. For behavior edge cases and exact semantics, use `docs/semantics.md`.

## Status

Current `main` implements the Phase 6 runtime surface:

- shared types and clock foundation
- a real core timer runtime
- local structured summaries and reporting
- the procedural convenience API
- MPI-reduced structured summaries
- limited OpenMP master-thread guards when built with `FTIMER_USE_OPENMP=ON`

For the exact runtime contract and edge-case behavior, see `docs/semantics.md`.

Future-facing design notes live in `docs/design.md`. When a design note conflicts with this README or the implementation under `src/`, current `main` is the source of truth.

## What fTimer Provides

`fTimer` is intended to provide wall-clock timing with:

- strict stack-based nesting
- context-sensitive accounting
- hierarchical structured summaries
- configurable mismatch handling (`strict`, `warn`, `repair`)
- inclusive and self time
- optional MPI cross-rank summary fields
- callback hooks for external profiling tools
- an injectable clock for deterministic tests

## Important Current Limitations

A few limitations are important enough to call out here:

- `mpi_summary()` requires `FTIMER_USE_MPI=ON`.
- OpenMP support is intentionally limited to master-thread-only timing when built with `FTIMER_USE_OPENMP=ON`.
- CMake is the only supported build path on current `main`.
- FPM support is deferred.

For exact MPI and OpenMP semantics, see `docs/semantics.md`.

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

## Public Surface

Current `main` supports both usage styles.

### Procedural API

`use ftimer` exports:

* `ftimer_init`
* `ftimer_finalize`
* `ftimer_start`
* `ftimer_stop`
* `ftimer_start_id`
* `ftimer_stop_id`
* `ftimer_lookup`
* `ftimer_reset`
* `ftimer_get_summary`
* `ftimer_mpi_summary`
* `ftimer_print_summary`
* `ftimer_write_summary`
* `ftimer_default_instance`

### OOP Core

The core `ftimer_t` supports:

* `init`
* `finalize`
* `start`
* `stop`
* `start_id`
* `stop_id`
* `lookup`
* `reset`
* `get_summary`
* `mpi_summary`
* `print_summary`
* `write_summary`

### Shared Types and Constants

`use ftimer` does not re-export shared types or constants.
Import shared definitions such as summary types, metadata types, mismatch constants, and MPI summary-state constants from `ftimer_types`.

## Examples

* `examples/basic_usage.F90`: serial procedural usage with `start`, `stop`, `get_summary`, and `print_summary`
* `examples/nested_timers.F90`: nested timers with manual metadata fields
* `examples/mpi_example.F90`: MPI usage with `ftimer_init(comm=...)` and root-side reduced fields from `ftimer_mpi_summary()`

## Build

### Smoke-test-only path

```bash
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure
```

### Serial build with behavioral tests

```bash
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure
```

### MPI build with MPI tests

```bash
FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi
```

### OpenMP-guard build with tests

```bash
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
ctest --test-dir build-openmp --output-on-failure
```

### Benchmark harness

```bash
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
```

## Supported Toolchain Notes

* Serial smoke/library build: any Fortran compiler CMake can use successfully.
* Serial behavioral tests: GNU Fortran with a matching pFUnit installation.
* MPI: an MPI wrapper compiler such as `mpifort`.
* OpenMP: GNU Fortran only for the documented path.

Use a separate build directory for each compiler / mode combination.

## Current Defaults and Packaging Notes

* Smoke tests are enabled by default.
* Behavioral tests are opt-in via `FTIMER_BUILD_TESTS=ON`.
* Installing `fTimer` exports the consumer-facing library and module files regardless of whether behavioral tests were enabled.
* MPI-reduced structured summaries require `FTIMER_USE_MPI=ON`.
* OpenMP master-thread guards require `FTIMER_USE_OPENMP=ON`.
* Installing and building are CMake-only on current `main`.

## Additional References

* `docs/semantics.md` — exact runtime contract and edge-case behavior
* `docs/design.md` — future-facing design intent
* `docs/agent-context.md` — shared coding-agent context
* `docs/maintainer.md` — issue / PR / review workflow

## License

BSD-3-Clause. See [LICENSE](LICENSE).