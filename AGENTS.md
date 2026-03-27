# AGENTS.md

This file provides guidance to Codex and other coding-agent workflows in this repository.

## Project Overview

**fTimer** — A lightweight, correctness-first wall-clock timing library for modern Fortran. Inspired by Flash-X's MPINative Timers but designed as a standalone profiling substrate with strict nesting, context-sensitive accounting, hierarchical summaries, and extensibility hooks for external tools.

## Build & Run Commands

```bash
# Performance measurement harness (serial, no pFUnit required)
cmake --fresh -B build-bench -DFTIMER_BUILD_BENCH=ON
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench

# Smoke-test-only build (includes install/export consumer verification)
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure

# Serial build (documented path: GNU Fortran + matching pFUnit install)
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure

# MPI build (documented path: MPI wrapper compiler)
FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi

# OpenMP guard build (currently supported with GNU Fortran)
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
ctest --test-dir build-openmp --output-on-failure

# Lint / format check
find src -name '*.F90' -exec fprettify --diff {} +
find tests -name '*.pf' -exec fprettify --diff {} +
find tests -name '*.F90' -exec fprettify --diff {} +
find examples -name '*.F90' -exec fprettify --diff {} +

# Convenience Makefile (delegates to cmake)
make            # build (serial)
make mpi        # build (MPI, defaults FC=mpifort)
make openmp     # build (OpenMP, defaults FC=gfortran)
make test       # build + run tests
make clean      # remove build/
make install    # install to CMAKE_INSTALL_PREFIX
```

Supported toolchain matrix:

- Serial smoke/library build: the active Fortran compiler that CMake selects, as long as it can build the project normally.
- Serial + pFUnit tests: GNU Fortran (`gfortran`) with a pFUnit installation built for the same compiler/toolchain.
- MPI: an MPI wrapper compiler such as `mpifort`. `FTIMER_USE_MPI=ON` now runs a configure-time `use mpi` probe and fails early if the active compiler cannot consume the discovered MPI module files.
- OpenMP: GNU Fortran (`gfortran`) only for the documented/supported path.

Use a separate build directory for each mode/compiler combination. Reconfiguring an existing CMake build tree with a different Fortran compiler is not a supported workflow here.

## Architecture

### High-Level Flow

```
ftimer.F90  (procedural wrappers + default global instance)
  └─► ftimer_core.F90  (ftimer_t OOP class: init, start, stop, reset, finalize)
        ├─► ftimer_types.F90   (derived types, kinds, constants, enums, summary types, callback interface)
        ├─► ftimer_clock.F90   (injectable wall-clock: MPI_Wtime vs system_clock)
        ├─► ftimer_summary.F90 (structured summary building + text formatting)
        └─► ftimer_mpi.F90    (MPI gather/reduce for cross-rank summaries)
```

### Module Dependency Order (build order)

1. `ftimer_types` — no dependencies (all types, enums, error codes, abstract interfaces)
2. `ftimer_clock` — depends on `ftimer_types`
3. `ftimer_core` — depends on `ftimer_types`, `ftimer_clock`
4. `ftimer_summary` — depends on `ftimer_types`, `ftimer_core`
5. `ftimer_mpi` — depends on `ftimer_types`, `ftimer_core`, `ftimer_summary`
6. `ftimer` — depends on all above (procedural wrappers)

### Key Design Decisions

- **Strict nesting by default**: Stack-based timer model. Mismatch handling is configurable (`strict`/`warn`/`repair`), default `strict`. `repair` mode exists for Flash-X compatibility.
- **Data first, report second**: `get_summary()` returns structured `ftimer_summary_t` data. Text formatting is a separate step built on top of structured data.
- **Injectable clock**: All timing goes through a `clock` function pointer. Tests inject a mock clock for deterministic results — no sleeps, no timing jitter.
- **Error contract**: All public routines accept optional `integer, intent(out) :: ierr`. Present → set error code, no stderr. Absent → warn to stderr, continue.
- **Context-sensitive accounting**: The same timer name under different parent call stacks is tracked independently.
- **Exclusive/self time**: Computed as inclusive time minus sum of direct children's inclusive times.
- **Callback hooks**: `on_event` procedure pointer fires on start/stop. Internal repair transitions do NOT fire callbacks.
- **MPI via integer comm handle**: Compatible with both `include 'mpif.h'` and `use mpi_f08` (via `comm%MPI_VAL`).
- **OpenMP master-thread-only timing**: When built with `FTIMER_USE_OPENMP=ON`, all guarded timer operations run only on the master thread (thread 0). Worker-thread calls are silent no-ops: no summary entry is created, no call count is incremented, and no `ierr` is set. Timer calls made exclusively on worker threads produce no summary entry. The supported pattern is to place `start`/`stop` outside `!$omp parallel` blocks. Placing `start`/`stop` inside a parallel region expecting each thread to contribute is the misleading anti-pattern. See `docs/semantics.md` "Consequences for timing data" for the full contract.

### Key Data Flow

`start("name")` → lookup/create segment → find/create context (current call stack) → push onto call stack → record start_time. `stop("name")` → verify top-of-stack match → pop call stack → find context (now-current stack) → accumulate elapsed time.

The call stack state CHANGES between start and stop — this is the most common source of context attribution bugs.

### Correctness Priorities

#### Timing Correctness (highest priority)

- **Context mismatch in start/stop ordering**: `stop` must pop the call stack BEFORE looking up the context index. If the lookup happens before the pop, the context will be the "timer is running" stack instead of the "timer's parent" stack, silently zeroing times or attributing them to the wrong context.
- **Iterative repair timestamp consistency**: When repairing a nesting mismatch, all unwound timers and the target timer must use a single `now` timestamp captured once. Independent clock reads for each step create timing gaps or double-counting that is invisible in output but makes times not sum correctly.
- **Repair must NOT fire user callbacks**: Internal repair transitions (unwinding/restarting timers during mismatch repair) must not fire the `on_event` callback. If they do, external profiling tools (PAPI, likwid) will see phantom start/stop events that corrupt their measurements.
- **Self-time computation boundaries**: Exclusive/self time is `inclusive - sum(direct children)`. If child iteration boundaries are wrong (e.g., iterating past the next sibling into cousins), self_time can go negative or exceed inclusive_time. Both conditions indicate a bug.

#### Numerical Precision

- **Double-precision truncation**: All timing arithmetic must use `real(wp)` where `wp = selected_real_kind(15, 307)`. Any implicit conversion to default `real` (single precision) degrades accuracy for runs longer than ~1 hour. Watch for literal constants without `_wp` suffix and mixed-precision arithmetic.

#### MPI Correctness

- **MPI summary hangs on inconsistent timer sets**: If ranks have different timer names or context structures, collective operations (MPI_Reduce, MPI_Allgather) will deadlock or produce garbage. The hash-based preflight check is mandatory before any collective — it must compare canonical timer descriptors across all ranks and fall back to local-only summary on mismatch.
- **Array growth divergence across MPI ranks**: If ranks create timers in different orders or different counts, segment array indices diverge. MPI collectives that assume matching indices will reduce the wrong timers against each other, producing plausible but wrong cross-rank statistics.

#### Code Quality Risks

- **Docs drift**: `CLAUDE.md`, README, `docs/semantics.md`, and any user-facing help text must match the actual implementation. Discrepancies are real bugs.
- **Test skepticism**: Ask whether tests actually exercise the behavior they claim to test. Mock clock tests that never advance time, or mismatch tests that don't verify the stack state after repair, provide false confidence.
- **Silent fallbacks**: Any code path that substitutes a default value for missing data should be flagged. Silent fallbacks can mask real errors and produce plausible-looking but wrong output. In particular: missing `ierr` argument should warn, not silently succeed.

## Development Workflow

Current `main` is in Phase 6. The shared types/clock foundation, core timer runtime, local summary/report formatting, procedural convenience wrappers, MPI-reduced structured summaries, and limited OpenMP master-thread guards are implemented.

During Phase 6, keep the library, examples, install package, smoke tests, and pFUnit suite buildable. Keep the diff phase-bounded: preserve procedural-wrapper parity with the OOP core, keep MPI summary behavior correct and explicit, preserve the limited master-thread-only OpenMP guard model, and keep current-state docs/examples honest. Do not pull fuller post-Phase-6 design work or broader OpenMP support forward.

Detailed repository operations and PR/review handling live in `docs/maintainer.md`. Use that file for GitHub workflow details; keep this file focused on coding/build/test behavior and the short mandatory PR summary below.

**Phase 1 exception:** the types/clock foundation was compile-first work, not an early pFUnit phase. Starting in Phase 2, test-driven development is mandatory: write tests first, confirm they fail, then implement. All behavioral tests use the injectable mock clock for deterministic results — tests never sleep or depend on wall-clock timing.

### Source-of-Truth Order

When sources disagree:

1. current code under `src/`
2. current behavioral tests
3. `docs/semantics.md` — intended runtime contract on `main`
4. `README.md` — user-facing current-state behavior
5. `docs/design.md` — forward-looking design intent

### Working Rules

Start every task with the smallest useful working set:

1. the task or issue description
2. touched source files
3. touched tests

Read additional docs only when the task requires them:

- `docs/semantics.md` — when runtime behavior or contract is changing or unclear
- `README.md` — when user-facing behavior, examples, or docs may need updates
- `docs/design.md` — for architectural or future-facing questions
- `docs/maintainer.md` — for workflow routing; then load only the phase-specific doc you need:
  - `docs/workflows/pr-open.md` — PR opening and review labels
  - `docs/workflows/review-monitoring.md` — monitoring and fallback review
  - `docs/workflows/findings-disposition.md` — responding to findings and merge criteria

Context budget:

- Read each file once per phase unless it changed or ambiguity remains.
- After the initial discovery pass, switch to implementation mode.
- Prefer diff-based validation late in the task over broad repo sweeps.
- Batch progress updates by phase, not by file or micro-step.

### Test Categories

- **Unit tests** (`tests/test_*.pf`): Isolated module tests — init/finalize, single start/stop, timer creation, ID lookup, time accumulation, call counts, reset behavior, edge cases, error contract verification. All use mock clock.
- **OpenMP guard tests** (`tests/test_openmp_guards.pf`): Master-thread-only guard semantics under `FTIMER_USE_OPENMP=ON`. These verify serial behavior outside parallel regions, worker-thread no-op behavior, summary stability, and procedural parity.
- **Integration tests** (`tests/test_summary.pf`, `tests/test_self_time.pf`, `tests/test_callbacks.pf`, `tests/test_file_output.pf`): Cross-module tests — summary building, self-time computation, callback firing, file I/O.
- **MPI tests** (`tests/mpi/test_mpi_*.pf`): Cross-rank correctness — MPI min/max/avg/imbalance, timer consistency checks. Run with 2+ ranks.

### Test Infrastructure

- **Current default**: smoke-test baseline (`FTIMER_BUILD_SMOKE_TESTS=ON`, `FTIMER_BUILD_TESTS=OFF`)
- **Build-contract smoke coverage**: the smoke baseline now also includes script-driven regression checks for the configure-time MPI/OpenMP gates plus `make mpi` / `make openmp` wrapper semantics. These tests skip cleanly when the required external toolchain pieces are not present, and CI runs them in a dedicated build-contract job with `gfortran`, `mpifort`, and a non-GNU Fortran compiler installed.
- **Behavioral suite**: pFUnit, enabled explicitly with `-DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=...`
- **Mock clock**: Module-level `fake_time` variable with `mock_clock()` function. Inject via `timer%clock => mock_clock`. Advance deterministically: set `fake_time`, call start/stop, assert exact accumulated times.
- **Golden output tests**: `test_summary.pf` compares `print_summary()` output against expected text.
- **Error contract tests**: Prefer `ierr` return-value assertions for edge cases, and use narrow stderr-capture checks when the contract under test explicitly distinguishes `ierr`-present silence from omitted-`ierr` warnings.

### pFUnit Quirks (gfortran)

These are critical — violating them causes cryptic build failures:

- **Module name must match filename** (case-insensitive): `test_basic.pf` must contain `module test_basic`
- **No inline comments on `@assert` lines**: `@assertEqual(a, b) ! comment` will fail
- **No `&` line continuations in `@assert` macros**: The preprocessor cannot handle them
- **Extract complex expressions to temp variables before `@assert`**: Do not put function calls or chained operations directly in assert arguments
- **gfortran cannot chain `%` after function call results**: Use temp variables. `call foo()%bar` does not compile — instead: `tmp = foo(); call tmp%bar`

## Pull Request Review Workflow

This workflow is **mandatory** for every PR. Do not skip any step.

Short version:

- create or link the GitHub issue first
- open a PR from a feature branch
- always apply `codex-software-review`
- also apply `codex-methodology-review` when the diff touches: `src/ftimer_core.F90`, `src/ftimer_summary.F90`, `src/ftimer_mpi.F90`, or `docs/semantics.md`
- also apply `codex-red-team-review` when the diff touches: `src/ftimer_core.F90` (especially `start`, `stop`, or `repair_mismatch`) or `src/ftimer_mpi.F90`
- monitor for the actual Codex review output
- reply to every finding, resolve every review thread, and do not merge while merge-blocking findings remain

For deeper workflow details (monitoring, fallback review, findings disposition, merge criteria), use `docs/maintainer.md` for routing to: `docs/workflows/pr-open.md`, `docs/workflows/review-monitoring.md`, `docs/workflows/findings-disposition.md`.

The native Codex trigger comments are intentionally posted as single-line `@codex review ...` comments built from `.github/prompts/*.md`. The long-form prompt library lives in `.github/prompts/detailed/`: it contains detailed versions of the three PR-triggered review types plus eight additional review prompts for API/compatibility, build/portability, completion auditing, docs/contracts, MPI safety, performance/overhead, pragmatic design, and test quality.

### Review Standards

1. **Anchor findings in code**: Cite specific files, functions, and line numbers. Do not make vague claims.
2. **Prioritize correctness over style**: A real bug matters more than a missing docstring.
3. **Be skeptical of tests**: Ask whether the test actually exercises the behavior it claims to test.
4. **Verify docs match implementation**: If the PR changes behavior, check that CLAUDE.md, README, and any relevant comments are updated.
5. **Prefer fewer, more serious findings**: Two real concerns are worth more than twenty style nits.
6. **Begin your response with the review type heading** expected by the prompt so it is clear which review you are responding to.
7. **Match the detailed prompt library when used**: `.github/prompts/detailed/` also defines long-form review headings such as `## API / Compatibility Review`, `## Build / Portability Review`, `## Completion Audit Review`, `## Docs / Contract Review`, `## MPI Safety Review`, `## Performance / Overhead Review`, `## Pragmatic Design Review`, and `## Test Quality Review`.

## Configuration

- **`FTIMER_USE_MPI`** (CMake option, default OFF): Enables MPI support. When ON, `MPI_Wtime()` is used as the clock source and `mpi_summary()` can populate cross-rank fields. The supported path is an MPI wrapper compiler such as `mpifort`; configure now fails early if the active compiler cannot compile a minimal `use mpi` probe against the discovered MPI toolchain. When OFF, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` and leaves the summary local-only.
- **`FTIMER_USE_OPENMP`** (CMake option, default OFF): Enables the Phase 6 `!$omp master` guards around the guarded `ftimer_core` entry points. This is limited master-thread-only protection, not full thread safety. The documented/supported build path is GNU Fortran (`gfortran`).
- **`FTIMER_BUILD_SMOKE_TESTS`** (CMake option, default ON): Enables the current smoke-test baseline, including install/export consumer verification and the script-driven build-contract regression checks when their toolchain prerequisites are available.
- **`FTIMER_BUILD_TESTS`** (CMake option, default OFF): Enables the pFUnit-backed behavioral and MPI test suites.
- **`CMAKE_INSTALL_PREFIX`**: Where `make install` places the library and module files.
- **pFUnit**: Optional dependency for behavioral tests. Set `PFUNIT_DIR` explicitly when enabling `FTIMER_BUILD_TESTS`.

CMake is the only supported build system in the current implementation. FPM support is intentionally deferred.
