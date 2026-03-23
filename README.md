# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

**Under construction.** Phase 3 now provides the shared types/clock foundation, a real core timer runtime, structured summary building, and formatted local reporting with deterministic pFUnit coverage. Expanded procedural wrappers, MPI reductions, and OpenMP guards are still tracked in [TODO.md](TODO.md).

## Current Phase 3 Behavior

Current `main` provides:

- CMake-based serial and MPI builds
- `ftimer_types` exports shared kinds, constants, summary/container types, and abstract clock/hook interfaces
- `ftimer_clock` exports `ftimer_default_clock()`, `ftimer_mpi_clock()` for MPI-enabled builds, and `ftimer_date_string()`
- `ftimer_core` exports a real `ftimer_t` implementation with `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `print_summary`, and `write_summary`
- `ftimer_summary` builds structured local summaries with hierarchical entries, inclusive time, self time, call counts, and formatted text output
- Strict-by-default stack-based timing with context-sensitive accounting and configurable mismatch handling (`strict` / `warn` / `repair`)
- A default smoke-test path plus optional pFUnit behavioral/integration tests using an injectable mock clock
- Example programs that compile and link against the library
- An installable CMake package export (`fTimerTargets.cmake`, `fTimerConfig.cmake`, `fTimerConfigVersion.cmake`)

Current public surface is still intentionally narrower than the target design:

- Procedural interface: `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, and `ftimer_default_instance`
- OOP core: `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `print_summary`, and `write_summary`
- `start`/`stop` are now real timer operations with the intended `ierr`/stderr error contract
- Summary/reporting is local-only in this phase; procedural summary wrappers and MPI-reduced summaries remain deferred

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

# MPI build compatibility check
cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi

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
- FPM support is deferred until the public API stabilizes.
- MPI reductions are not implemented yet.

## Deferred Items

These are intentionally postponed beyond Phase 3:

- Procedural API expansion beyond the current wrapper surface
- MPI reductions and cross-rank summary statistics
- MPI behavioral tests
- OpenMP guards
- FPM manifest/support
- secondary repo hygiene such as Dependabot, `.editorconfig`, and broader governance files

## License

BSD-3-Clause. See [LICENSE](LICENSE).
