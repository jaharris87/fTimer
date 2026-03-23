# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

**Under construction.** Phase 1 provides buildable foundation modules for shared types and clock utilities, along with the existing placeholder core, examples, packaging, and smoke-test scaffolding. Behavioral implementation is tracked in [TODO.md](TODO.md).

## Current Phase 1 Behavior

Current `main` provides a buildable foundation plus placeholder runtime behavior:

- CMake-based serial and MPI builds
- `ftimer_types` exports shared kinds, constants, summary/container types, and abstract clock/hook interfaces
- `ftimer_clock` exports `ftimer_default_clock()`, `ftimer_mpi_clock()` for MPI-enabled builds, and `ftimer_date_string()`
- Placeholder example programs that compile and link against the library
- A default smoke-test path that verifies the scaffold builds and reports placeholder status honestly
- An installable CMake package export (`fTimerTargets.cmake`, `fTimerConfig.cmake`, `fTimerConfigVersion.cmake`)

Current timer behavior is still intentionally narrow:

- Procedural interface: `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, and `ftimer_default_instance`
- OOP core placeholder: `init`, `finalize`, `start`, `stop`, and `get_summary`
- `start` and `stop` preserve the intended error-reporting contract but still report "not implemented" after initialization

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
# Serial build
cmake -B build && cmake --build build

# Run the current smoke test
ctest --test-dir build --output-on-failure

# MPI build
cmake -B build-mpi -DFTIMER_USE_MPI=ON && cmake --build build-mpi

# Enable pFUnit tests later, once they exist
cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit && cmake --build build

# Or use the Makefile wrapper
make        # serial build
make mpi    # MPI build
make test   # build + test
```

Requires: gfortran (or compatible Fortran compiler), CMake >= 3.16, and an MPI Fortran toolchain when `FTIMER_USE_MPI=ON`.

Phase 1 defaults:

- CMake is the only supported build path right now.
- Smoke tests are enabled by default and are intentionally minimal.
- pFUnit-backed behavioral tests are not part of the default build yet.
- FPM support is deferred until the public API stabilizes.
- The timer runtime API is still placeholder-only: it compiles and preserves the error-reporting shape, but timer operations still report "not implemented" until later phases.

## Deferred Items

These are intentionally postponed beyond Phase 1:

- pFUnit behavioral test suite
- Core timer behavior
- Structured summary building and formatting
- MPI reductions and cross-rank summary statistics
- FPM manifest/support
- secondary repo hygiene such as Dependabot, `.editorconfig`, and broader governance files

## License

BSD-3-Clause. See [LICENSE](LICENSE).
