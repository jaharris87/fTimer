# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

**Under construction.** Phase 6 now provides the shared types/clock foundation, a real core timer runtime, structured local summaries and reporting, the expanded procedural convenience API, MPI-reduced structured summaries with deterministic pFUnit coverage, and limited OpenMP master-thread guards when built with `FTIMER_USE_OPENMP=ON`.

## Current Phase 6 Behavior

Current `main` provides:

- CMake-based serial and MPI builds
- `ftimer_types` exports shared kinds, constants, summary/container types, and abstract clock/hook interfaces
- `ftimer_clock` exports `ftimer_default_clock()`, `ftimer_mpi_clock()` for MPI-enabled builds, and `ftimer_date_string()`
- `ftimer_core` exports a real `ftimer_t` implementation with `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `mpi_summary`, `print_summary`, and `write_summary`
- `ftimer_summary` builds structured local summaries with hierarchical entries, inclusive time, self time, call counts, and formatted text output
- `ftimer_mpi` adds canonical descriptor hashing, cross-rank consistency preflight, and MPI reduction helpers for structured summaries
- Strict-by-default stack-based timing with context-sensitive accounting and configurable mismatch handling (`strict` / `warn` / `repair`)
- Optional OpenMP master-thread guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`; inside OpenMP parallel regions, non-master calls to the guarded core timer operations are no-ops instead of mutating shared timer state
- A default smoke-test path plus optional pFUnit behavioral/integration/MPI tests using an injectable mock clock
- Example programs that compile and link against the library
- An installable CMake package export (`fTimerTargets.cmake`, `fTimerConfig.cmake`, `fTimerConfigVersion.cmake`)

Current public surface still exposes the complete Phase 5 API surface for both usage styles:

- Procedural interface: `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_print_summary`, `ftimer_write_summary`, and `ftimer_default_instance`
  Current Phase 6 note: the safe, documented positional `init` forms are `call timer%init()` and `call ftimer_init()`. Pass `ierr`, `comm`, and `mismatch_mode` by keyword in both APIs. With the current Fortran interface, positional integer calls still compile but are ambiguous and can silently bind to `ierr`, so they are documented as unsupported traps.
- OOP core: `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `mpi_summary`, `print_summary`, and `write_summary`
- Procedural wrappers are thin forwarding calls over the existing OOP implementation and preserve the intended `ierr`/stderr error contract
- `get_summary()`, `print_summary()`, and `write_summary()` remain local-only
- `mpi_summary()` / `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON` plus a fully stopped timer set for cross-rank reduction, perform a hash-based preflight before any reduction, fall back to local-only summaries with `FTIMER_ERR_MPI_INCON` on inconsistent ranks, and populate min/max/avg/imbalance fields on root when `has_mpi_data` is valid
- OpenMP support is intentionally limited: Phase 6 does not make `fTimer` thread-safe or add thread-local timer instances; the supported model is still master-thread-only timing

## Target Capabilities

fTimer is intended to provide stack-based hierarchical timing with:

- Context-sensitive accounting (same timer name tracked independently under different parents)
- Configurable mismatch handling (strict / warn / repair)
- Structured summary data (`get_summary()`) and formatted text reports (`print_summary()`)
- Exclusive/self time alongside inclusive time
- Optional MPI cross-rank statistics (min/max/avg/imbalance)
- Callback hooks for external profiling tools (PAPI, likwid, etc.)
- Injectable clock for deterministic testing

## Build

```bash
# Serial build with pFUnit tests
cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure

# Smoke-test-only path
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure

# MPI build + MPI tests
cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi

# OpenMP-guard build + tests
cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
ctest --test-dir build-openmp --output-on-failure

# Or use the Makefile wrapper
make        # serial build
make mpi    # MPI build
make test   # build + test
```

Requires: a Fortran compiler with preprocess support, CMake >= 3.16, pFUnit when `FTIMER_BUILD_TESTS=ON`, and an MPI Fortran toolchain when `FTIMER_USE_MPI=ON`.

Current defaults:

- CMake is the only supported build path right now.
- Smoke tests are enabled by default and stay intentionally minimal.
- pFUnit-backed behavioral tests are opt-in via `FTIMER_BUILD_TESTS=ON`.
- Installing `fTimer` always exports the same consumer-facing library/modules whether or not `FTIMER_BUILD_TESTS=ON`; test-only modules stay build-tree-only and are not installed.
- FPM support is deferred until the public API stabilizes.
- MPI-reduced structured summaries require `FTIMER_USE_MPI=ON`; otherwise `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` and a local-only summary.
- OpenMP master-thread guards require `FTIMER_USE_OPENMP=ON`; otherwise the OpenMP directives compile away and fTimer behaves as the serial/MPI-only runtime already described above.
- Formatted summary/report output is still local-only.

## Deferred Items

These are intentionally postponed beyond Phase 6:

- broader OpenMP support beyond Phase 6's master-thread-only guards
- FPM manifest/support
- secondary repo hygiene such as Dependabot, `.editorconfig`, and broader governance files

## License

BSD-3-Clause. See [LICENSE](LICENSE).
