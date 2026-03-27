# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

Current `main` implements the Phase 6 runtime contract: shared types/clock foundation, a real core timer runtime, structured local summaries and reporting, the procedural convenience API, MPI-reduced structured summaries, and limited OpenMP master-thread guards when built with `FTIMER_USE_OPENMP=ON`.

Future-facing design notes still live in `docs/design.md`; when a design note conflicts with this README or the source in `src/`, the current implementation on `main` is the source of truth.

## Current Phase 6 Behavior

Current `main` provides:

- CMake-based serial and MPI builds
- `ftimer_types` exports shared kinds, constants, summary/container types, and abstract clock/hook interfaces
- `ftimer_clock` exports `ftimer_default_clock()`, `ftimer_mpi_clock()` for MPI-enabled builds, and `ftimer_date_string()`
- `ftimer_core` exports a real `ftimer_t` implementation with `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `mpi_summary`, `print_summary`, and `write_summary`
- `ftimer_summary` builds structured local summaries with hierarchical entries, inclusive time, self time, call counts, and formatted text output
- `ftimer_mpi` adds canonical descriptor hashing, cross-rank consistency preflight, and MPI reduction helpers for structured summaries
- Strict-by-default stack-based timing with context-sensitive accounting and configurable mismatch handling (`strict` / `warn` / `repair`)
- Timer names are right-trimmed for normal Fortran character compatibility, but they must otherwise be non-empty, fit within `FTIMER_NAME_LEN`, must not begin with a blank, and must not contain ASCII control characters
- Optional OpenMP master-thread guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`; inside OpenMP parallel regions, non-master calls to the guarded core timer operations are silent no-ops: no summary entry is created, no call count is incremented, no `ierr` is set, and no stderr warning is emitted. Timer calls made exclusively on worker threads vanish silently and produce no summary entry. When all threads in a parallel region call start/stop for the same timer, only the master thread's call is recorded — the call count reflects 1, not the thread count. To time a parallel region as a whole, place start/stop calls outside the `!$omp parallel` block.
- A default smoke-test path plus optional pFUnit behavioral/integration/MPI tests using an injectable mock clock
- Example programs that compile and link against the library
- An installable CMake package export (`fTimerTargets.cmake`, `fTimerConfig.cmake`, `fTimerConfigVersion.cmake`)

Current public surface on `main` supports both usage styles:

- `use ftimer` exports `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_mpi_summary`, `ftimer_print_summary`, `ftimer_write_summary`, and `ftimer_default_instance`
  `ierr` is now the last optional argument in both `init` signatures (`comm`, `mismatch_mode`, `ierr`). A single positional integer safely binds to `comm` (`intent(in)`), not `ierr` (`intent(out)`), eliminating the silent-clobber trap from earlier phases. Keywords are recommended for readability.
- OOP core: `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `mpi_summary`, `print_summary`, and `write_summary`
- `use ftimer` does not re-export shared types or constants. Import `ftimer_summary_t`, `ftimer_metadata_t`, `FTIMER_MISMATCH_*`, and `FTIMER_MPI_SUMMARY_*` from `ftimer_types`.
- Procedural wrappers are thin forwarding calls over the existing OOP implementation and preserve the intended `ierr`/stderr error contract
- `get_summary()`, `print_summary()`, and `write_summary()` remain local-only
- Formatted local summaries escape unsafe raw summary-entry names instead of emitting them literally: leading blanks render as `\x20`, backslashes render as `\\`, tabs/newlines/carriage returns render as `\t`/`\n`/`\r`, other ASCII control characters render as `\xNN`, and blank/empty raw names render as `<blank>`
- `mpi_summary()` / `ftimer_mpi_summary()` require `FTIMER_USE_MPI=ON`, a fully stopped timer set, and collective agreement on the communicator captured by `init` (`MPI_COMM_WORLD` when `comm` is omitted). They perform a hash-based timer-descriptor preflight before reduction, fall back to a plain local-only summary with `FTIMER_ERR_MPI_INCON` on inconsistent ranks, populate min/max/avg/imbalance fields only on communicator root, and do not attempt to rescue mismatched communicator choices across would-be participants
- After a successful `mpi_summary()`, `start_date`, `end_date`, `total_time`, `inclusive_time`, `self_time`, `call_count`, `avg_time`, and `pct_time` still describe only the calling rank's local summary
- On rank 0 only, a successful `mpi_summary()` also populates `min_time`, `max_time`, `avg_across_ranks`, and `imbalance`; `has_mpi_data=.true.` means only those reduced MPI entry fields are valid on this rank, not that the whole summary is globally reduced
- `summary%mpi_summary_state` makes the result shape explicit: `FTIMER_MPI_SUMMARY_LOCAL_ONLY` for plain local summaries, `FTIMER_MPI_SUMMARY_ROOT_LOCAL_PLUS_REDUCED` for the root-local-plus-reduced root result, and `FTIMER_MPI_SUMMARY_NONROOT_LOCAL_AFTER_REDUCE` for successful non-root calls that still expose only local fields
- OpenMP support is intentionally limited: Phase 6 does not make `fTimer` thread-safe or add thread-local timer instances; the supported model is master-thread-only timing. Timings reported in a summary reflect only what the master thread observed; worker-thread work is not separately captured.

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

For metadata headers, construct `ftimer_metadata_t` values directly by assigning `%key` and `%value`. Current `main` does not provide a helper constructor such as `ftimer_metadata(...)`.

## Examples

- `examples/basic_usage.F90`: serial procedural usage with `start`, `stop`, `get_summary`, and `print_summary`
- `examples/nested_timers.F90`: nested timers plus manual `ftimer_metadata_t` header fields
- `examples/mpi_example.F90`: MPI-only example showing `ftimer_init(comm=...)` and root-side reduced summary fields from `ftimer_mpi_summary()`

## Target Capabilities

fTimer is intended to provide stack-based hierarchical timing with:

- Context-sensitive accounting (same timer name tracked independently under different parents)
- Configurable mismatch handling (strict / warn / repair)
- Structured summary data (`get_summary()`) and formatted text reports (`print_summary()`)
- Exclusive/self time alongside inclusive time
- Optional MPI cross-rank statistics (min/max/avg/imbalance)
- Callback hooks for external profiling tools (PAPI, likwid, etc.)
- Injectable clock for deterministic testing

## Performance Measurement

A standalone measurement harness (`bench/ftimer_bench.F90`) covers the main overhead risks: hot-path start/stop, name-lookup scaling with timer count, call-stack push/pop scaling with nesting depth, and summary-generation scaling with timer count. No pFUnit required.

```bash
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
```

This produces a structured table of per-operation nanosecond costs useful for identifying regression targets and comparing before/after optimizations. See `bench/ftimer_bench.F90` for scenario descriptions.

## Build

```bash
# Smoke-test-only path (includes install/export consumer verification)
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure

# Serial build with pFUnit tests (documented path: GNU Fortran + matching pFUnit install)
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure

# MPI build + MPI tests (documented path: MPI wrapper compiler)
FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi

# OpenMP-guard build + tests (currently supported with GNU Fortran)
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
ctest --test-dir build-openmp --output-on-failure

# Or use the Makefile wrapper
make        # serial build
make mpi    # MPI build (defaults FC=mpifort)
make openmp # OpenMP build (defaults FC=gfortran)
make test   # build + test
```

Supported toolchain matrix:

- Serial smoke/library build: the active Fortran compiler that CMake selects, as long as it can build the project normally.
- Serial + pFUnit tests: GNU Fortran (`gfortran`) with a pFUnit installation built for the same compiler/toolchain.
- MPI: an MPI wrapper compiler such as `mpifort`. `FTIMER_USE_MPI=ON` now probes a minimal `use mpi` compile at configure time and fails early if the active compiler cannot consume the discovered MPI module files.
- OpenMP: GNU Fortran (`gfortran`) only for the documented/supported path. Other compiler families are not currently an advertised OpenMP build path for this repo.

Use a separate build directory for each mode/compiler combination. Reconfiguring an existing CMake build tree with a different Fortran compiler is not a supported workflow here.

Requires: a Fortran compiler with preprocess support, CMake >= 3.16, pFUnit when `FTIMER_BUILD_TESTS=ON`, an MPI wrapper/compiler pair when `FTIMER_USE_MPI=ON`, and GNU Fortran when `FTIMER_USE_OPENMP=ON`.

Current defaults:

- CMake is the only supported build path right now.
- Smoke tests are enabled by default and cover both the in-tree phase-0 smoke executable and an out-of-tree installed-package consumer configure/build check.
- pFUnit-backed behavioral tests are opt-in via `FTIMER_BUILD_TESTS=ON`.
- Installing `fTimer` always exports the same consumer-facing library/modules whether or not `FTIMER_BUILD_TESTS=ON`; test-only modules stay build-tree-only and are not installed.
- `FTIMER_USE_MPI=ON` is intended for wrapper-compiler setups such as `FC=mpifort`; incompatible default-compiler MPI paths now fail during configure with guidance instead of reaching a later compile failure.
- FPM support is deferred until the public API stabilizes.
- MPI-reduced structured summaries require `FTIMER_USE_MPI=ON`; otherwise `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` and a local-only summary.
- OpenMP master-thread guards require `FTIMER_USE_OPENMP=ON` with GNU Fortran; otherwise the OpenMP directives compile away and fTimer behaves as the serial/MPI-only runtime already described above.
- Formatted summary/report output is still local-only.

## Deferred Items

These are intentionally postponed beyond Phase 6:

- broader OpenMP support beyond Phase 6's master-thread-only guards
- FPM manifest/support
- secondary repo hygiene such as Dependabot, `.editorconfig`, and broader governance files

## License

BSD-3-Clause. See [LICENSE](LICENSE).
