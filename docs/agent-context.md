# Agent Context

This document is the shared baseline context for coding agents working in this repository.
`CLAUDE.md` and `AGENTS.md` should stay thin and point here rather than duplicating this content.

## Project Summary

**fTimer** is a lightweight, correctness-first wall-clock timing library for modern Fortran.

Core characteristics:

- strict stack-based nesting
- context-sensitive accounting
- hierarchical structured summaries
- configurable mismatch handling (`strict`, `warn`, `repair`)
- callback hooks for external profiling tools
- MPI cross-rank summary support
- limited OpenMP master-thread-only guards in the current implementation

## Current Implementation Scope

Current `main` implements the Phase 6 runtime contract:

- shared types and clock foundation
- core timer runtime
- local structured summaries and report formatting
- procedural wrappers over the OOP core
- MPI-reduced structured summaries
- limited OpenMP master-thread-only guards

Do not pull broader post-Phase-6 design work forward unless the task explicitly calls for it.

## Source-of-Truth Order

When sources disagree, use this order:

1. current code under `src/`
2. current behavioral tests
3. `docs/semantics.md` for the intended runtime contract on `main`
4. `README.md` for user-facing current-state behavior
5. `docs/design.md` for forward-looking design intent

`docs/design.md` is not the source of truth for behavior already implemented differently on `main`.

## Default Working Mode

Start every task with the smallest useful working set.

Default read set:

1. the task or issue description
2. this file
3. the touched source files
4. the touched tests

Only expand beyond that when the task requires it.

### Read Additional Docs Only When Needed

- Read `docs/semantics.md` when runtime behavior is changing, ambiguous, or under review.
- Read `README.md` when user-facing behavior, examples, installation, or public documentation may need updates.
- Read `docs/design.md` when the task is architectural, future-facing, or explicitly asks whether a change fits the intended design.
- Read `docs/maintainer.md` only for issue/PR/review/disposition workflow tasks.

## Context Budget Rules

Minimize repeated full-context passes.

- Read each file once per phase unless it changed or a specific ambiguity remains.
- Do not reread unchanged files without a concrete reason.
- After the initial discovery pass, switch to implementation mode.
- Prefer keeping a compact working summary of touched files over rereading them.
- Prefer diff-based validation late in the task instead of broad repo sweeps.
- Batch progress updates by phase, not by file or micro-step.

## Architecture Quick Reference

```text
ftimer.F90       procedural wrappers + default global instance
  -> ftimer_core.F90     ftimer_t runtime: init/start/stop/reset/finalize/lookup
     -> ftimer_types.F90 shared types, kinds, constants, enums, summary types, callback interface
     -> ftimer_clock.F90 injectable wall-clock
     -> ftimer_summary.F90 structured summary + text formatting
     -> ftimer_mpi.F90  MPI reduction / consistency preflight
```

Build order:

1. `ftimer_types`
2. `ftimer_clock`
3. `ftimer_core`
4. `ftimer_summary`
5. `ftimer_mpi`
6. `ftimer`

## Highest-Risk Correctness Areas

These deserve extra scrutiny in both implementation and review.

### Timing correctness

* `stop` must pop the call stack before looking up the parent context.
* Mismatch repair must use a single captured timestamp consistently across the repair sequence.
* Internal repair transitions must not fire user callbacks.
* Self time must equal inclusive time minus direct children only.

### Numerical precision

* Timing arithmetic must use `real(wp)` consistently.
* Avoid implicit narrowing to default `real`.
* Suffix floating-point literals with `_wp` where appropriate.

### MPI correctness

* Cross-rank reduction assumes canonical timer descriptors match across ranks.
* The consistency preflight must happen before collective reduction.
* Divergent timer creation or hierarchy across ranks must fall back safely to local-only summary behavior.

### OpenMP limitations

* Current OpenMP support is master-thread-only timing, not general thread safety.
* Worker-thread timer calls inside parallel regions are intentionally silent no-ops.
* The supported pattern is to place timing outside the `!$omp parallel` block when timing the region as a whole.

## Build and Test Commands

### Smoke build

```bash
cmake -B build-smoke
cmake --build build-smoke
ctest --test-dir build-smoke --output-on-failure
```

### Serial behavioral tests

```bash
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
ctest --test-dir build --output-on-failure
```

### MPI build and tests

```bash
FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
ctest --test-dir build-mpi --output-on-failure -L mpi
```

### OpenMP guarded build and tests

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

### Formatting check

```bash
find src -name '*.F90' -exec fprettify --diff {} +
find tests -name '*.pf' -exec fprettify --diff {} +
find tests -name '*.F90' -exec fprettify --diff {} +
find examples -name '*.F90' -exec fprettify --diff {} +
```

## Supported Toolchain Notes

* Serial smoke/library build: any Fortran compiler CMake can use successfully.
* Serial behavioral tests: GNU Fortran with matching pFUnit.
* MPI: an MPI wrapper compiler such as `mpifort`.
* OpenMP: GNU Fortran only for the documented path.

Use a separate build directory per compiler / mode combination.

## Testing Rules

* Starting in Phase 2, behavior changes should be test-driven where practical.
* Behavioral timing tests should use the injectable mock clock.
* Do not rely on sleep-based or jitter-sensitive timing tests.
* Keep procedural wrappers behaviorally aligned with the OOP core unless the task explicitly changes that contract.

## pFUnit / gfortran Quirks

These are common sources of wasted iteration:

* module name must match filename
* no inline comments on `@assert` lines
* no `&` continuations inside `@assert` macros
* extract complex expressions to temporaries before asserting
* do not chain `%` directly from a function-call result in gfortran; use a temporary

## Workflow Routing

This file is not the full workflow manual.

* For issue/PR/review/disposition workflow, use `docs/maintainer.md`.
* For runtime contract details, use `docs/semantics.md`.
* For future design intent, use `docs/design.md`.
* For user-facing current behavior, use `README.md`.

## Phase Boundaries and Session Discipline

Prefer one major objective per session:

* implementation
* review/disposition
* next-step planning

End each phase with a short handoff note containing:

* task or issue
* files touched
* behavior changed
* tests run
* open questions
* recommended next step

Use that handoff as the starting context for the next session instead of replaying the full prior thread.