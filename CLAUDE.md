# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**fTimer** — A lightweight, correctness-first wall-clock timing library for modern Fortran. Inspired by Flash-X's MPINative Timers but designed as a standalone profiling substrate with strict nesting, context-sensitive accounting, hierarchical summaries, and extensibility hooks for external tools.

## Build & Run Commands

```bash
# Serial placeholder build
cmake -B build && cmake --build build

# MPI placeholder build
cmake -B build -DFTIMER_USE_MPI=ON && cmake --build build

# Run Phase 0 smoke tests
ctest --test-dir build --output-on-failure

# Enable pFUnit once real tests exist
cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit && cmake --build build

# Lint / format check
fprettify --diff src/*.F90 tests/*.pf

# Convenience Makefile (delegates to cmake)
make            # build (serial)
make mpi        # build (MPI)
make test       # build + run tests
make clean      # remove build/
make install    # install to CMAKE_INSTALL_PREFIX
```

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

## Development Workflow

Phase 0 is scaffold work. The library, examples, install package, and smoke tests must stay buildable, but they are not substitutes for the real implementation phases in `TODO.md`.

**Test-driven development is mandatory.** Write tests first, confirm they fail, then implement. All tests use the injectable mock clock for deterministic results — tests never sleep or depend on wall-clock timing.

### Test Categories

- **Unit tests** (`tests/test_*.pf`): Isolated module tests — init/finalize, single start/stop, timer creation, ID lookup, time accumulation, call counts, reset behavior, edge cases, error contract verification. All use mock clock.
- **Integration tests** (`tests/test_summary.pf`, `tests/test_self_time.pf`, `tests/test_callbacks.pf`, `tests/test_file_output.pf`): Cross-module tests — summary building, self-time computation, callback firing, file I/O.
- **MPI tests** (`tests/mpi/test_mpi_*.pf`): Cross-rank correctness — MPI min/max/avg/imbalance, timer consistency checks. Run with 2+ ranks.

### Test Infrastructure

- **Phase 0 default**: smoke-test-only baseline (`FTIMER_BUILD_SMOKE_TESTS=ON`, `FTIMER_BUILD_TESTS=OFF`)
- **Framework for later phases**: pFUnit, enabled explicitly with `-DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=...`
- **Mock clock**: Module-level `fake_time` variable with `mock_clock()` function. Inject via `timer%clock => mock_clock`. Advance deterministically: set `fake_time`, call start/stop, assert exact accumulated times.
- **Golden output tests**: `test_summary.pf` compares `print_summary()` output against expected text.
- **Error contract tests**: Every edge case tested via `ierr` return value, not stderr parsing.

### pFUnit Quirks (gfortran)

These are critical — violating them causes cryptic build failures:

- **Module name must match filename** (case-insensitive): `test_basic.pf` must contain `module test_basic`
- **No inline comments on `@assert` lines**: `@assertEqual(a, b) ! comment` will fail
- **No `&` line continuations in `@assert` macros**: The preprocessor cannot handle them
- **Extract complex expressions to temp variables before `@assert`**: Do not put function calls or chained operations directly in assert arguments
- **gfortran cannot chain `%` after function call results**: Use temp variables. `call foo()%bar` does not compile — instead: `tmp = foo(); call tmp%bar`

## Pull Request Review Workflow

This workflow is **mandatory** for every PR. Do not skip any step.

### Step 1: Open the PR and apply labels

When you open or materially update a pull request:

0. Create or link the GitHub issue for the phase/task before opening the PR.
1. Always add the label `codex-software-review`.
2. If changes touch `src/ftimer_core.F90`, `src/ftimer_summary.F90`, `src/ftimer_mpi.F90`, or `docs/semantics.md`, also add `codex-methodology-review`.
3. If changes touch `src/ftimer_core.F90` (especially `start`, `stop`, `repair_mismatch`) or `src/ftimer_mpi.F90`, also add `codex-red-team-review`.
4. Do not manually paste large review prompts into the PR unless explicitly asked.
5. Let GitHub workflows trigger Codex review comments from the saved prompt files in `.github/prompts/`.

### Step 2: Monitor for Codex reviews

After opening the PR and applying labels, **you must proactively monitor for Codex review completion**. Do not wait for the user to ask.

1. Inform the user that you are monitoring for Codex reviews.
2. Poll the PR comments every 60 seconds for new comments from `chatgpt-codex-connector` or containing Codex review content.
3. Codex reviews typically arrive within 2-5 minutes. Continue polling for up to 10 minutes.
4. Once all expected reviews have arrived (one per label applied), proceed to Step 3.
5. If reviews have not arrived after 10 minutes, inform the user and ask how to proceed.

### Step 3: Respond to each review finding

For **every finding** in every Codex review, post a reply comment on the PR responding in one of three categories:

- **Agree and fix**: Make the code change, push it, and note what you fixed in the reply.
- **Disagree with evidence**: Explain why the finding is incorrect, citing specific code, tests, or design decisions.
- **Defer with reason**: Acknowledge the concern but explain why it is out of scope for this PR.

Group your responses into a single comment per review. Every finding must be addressed — do not silently skip any.

### Merge-blocking criteria

Do not merge the PR if any finding classified as **bug**, **leakage**, or **silent wrong answer** remains unaddressed (neither fixed nor disagreed-with-evidence). Findings classified as **nit**, **design concern**, or **methodology concern** do not block merge unless escalated by the user.

### Step 4: Report to the user

After responding to all reviews, give the user a concise summary:
- How many findings per review type
- What you agreed and fixed
- What you disagreed with and why
- What you deferred
- Whether any merge-blocking findings remain

## Configuration

- **`FTIMER_USE_MPI`** (CMake option, default OFF): Enables MPI support. When ON, `MPI_Wtime()` is used as the clock source and `mpi_summary()` is available.
- **`FTIMER_BUILD_SMOKE_TESTS`** (CMake option, default ON): Enables the Phase 0 smoke-test baseline.
- **`FTIMER_BUILD_TESTS`** (CMake option, default OFF): Enables pFUnit-backed tests once those suites exist.
- **`CMAKE_INSTALL_PREFIX`**: Where `make install` places the library and module files.
- **pFUnit**: Optional until the real test tree exists. Set `PFUNIT_DIR` explicitly when enabling `FTIMER_BUILD_TESTS`.

## Repository Bootstrap

- Create the review labels manually in GitHub: `codex-software-review`, `codex-methodology-review`, `codex-red-team-review`.
- Add a repository secret named `CODEX_TRIGGER_PAT` for the review-trigger workflow.
- Configure a `main` ruleset that requires pull requests, passing CI/lint checks, blocks direct pushes and force pushes, and requires conversation resolution.
- CMake is the only supported build system in Phase 0. FPM support is intentionally deferred.
