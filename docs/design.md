> **When to read this:** For current-state architecture, repository layout, validation, and maintainer workflow context. This document describes what ships on current `main`, not a future target state.

# fTimer Architecture Reference

This document is the current-state architecture reference for `fTimer`.

Use it to understand how the repository is organized today, how the major modules fit together, what validation paths are real, and how the documented maintainer workflow ties into the codebase. For the exact runtime contract, prefer [`docs/semantics.md`](semantics.md). For the user-facing quick-start and build/install guidance, prefer [`README.md`](../README.md). For the historical phase roadmap that led to the current implementation, use [`docs/implementation-history.md`](implementation-history.md).

When current-state sources disagree, use this repository-wide precedence order: current code under `src/`, then current behavioral tests, then `docs/semantics.md`, then `README.md`, then `docs/design.md`.

## Current Scope

Current `main` ships a small, correctness-first wall-clock timing library for modern Fortran. The strongest supported stories today are disciplined serial timing and pure-MPI timing; the OpenMP path is a deliberately narrow carve-out for bracketing a parallel region as a whole.

Implemented capabilities include:

- stack-based start/stop timing with context-sensitive accounting
- configurable mismatch handling (`strict`, `warn`, `repair`) with `strict` as the default
- structured local summaries plus formatted local report output
- procedural wrappers over an OOP core
- MPI-reduced summary fields on communicator root after a descriptor-hash preflight
- limited OpenMP master-thread-only timer guards
- installable CMake package exports, smoke tests, pFUnit behavioral tests, and a benchmark harness

fTimer does not currently provide built-in hardware counter backends, JSON/CSV export utilities, a serious profiler-backend callback contract, or general thread-safe timing across OpenMP worker threads.

## Repository Map

The repository layout that matters for day-to-day work is:

```text
fTimer/
├── src/
│   ├── ftimer_types.F90
│   ├── ftimer_clock.F90
│   ├── ftimer_core.F90
│   ├── ftimer_summary.F90
│   ├── ftimer_mpi.F90
│   ├── ftimer_core_summary_bindings.F90
│   └── ftimer.F90
├── tests/
│   ├── test_*.pf
│   ├── mpi/
│   └── check_*_contracts.cmake
├── examples/
│   ├── basic_usage.F90
│   ├── nested_timers.F90
│   ├── mpi_example.F90
│   └── openmp_example.F90
├── bench/
│   └── ftimer_bench.F90
├── docs/
│   ├── semantics.md
│   ├── design.md
│   ├── implementation-history.md
│   └── workflows/
└── .github/
    ├── workflows/
    └── prompts/
```

Two supporting points matter here:

- `docs/design.md` is now the current architecture reference.
- `docs/implementation-history.md` holds the historical phase roadmap so this document can stay focused on the current repository.

## Module Architecture

The shipped module layering is:

```text
ftimer.F90
  └─ procedural wrappers over the default global instance

ftimer_core.F90
  └─ ftimer_t state and timer lifecycle entry points
     └─ summary/report bindings implemented in ftimer_core_summary_bindings.F90

ftimer_summary.F90
  └─ local structured summary building and text formatting

ftimer_mpi.F90
  └─ MPI descriptor preflight and reduced summary fields

ftimer_clock.F90
  └─ default wall clock, MPI wall clock wrapper, date-string helper

ftimer_types.F90
  └─ kinds, constants, summary/container types, and callback interfaces
```

The CMake source order reflects the real dependency order:

1. `ftimer_types.F90`
2. `ftimer_clock.F90`
3. `ftimer_core.F90`
4. `ftimer_summary.F90`
5. `ftimer_mpi.F90`
6. `ftimer_core_summary_bindings.F90`
7. `ftimer.F90`

### Module Roles

`ftimer_types.F90` is the shared foundation. It defines kind parameters, error codes, mismatch-mode constants, MPI summary-state constants, summary types, call-stack/context helpers, and the abstract interfaces for clocks and lightweight callback hooks.

`ftimer_clock.F90` centralizes time acquisition. Serial builds use `system_clock`; MPI-enabled builds can use the MPI wall clock path. Tests rely on the injectable clock interface so behavior is deterministic without sleeps.

`ftimer_core.F90` owns the mutable timer state in `ftimer_t`: timer definitions, active stack state, mismatch policy, communicator capture, lightweight callback registration, and the guarded timer entry points.

`ftimer_core_summary_bindings.F90` is the submodule-backed binding layer that connects `ftimer_t` to local summary generation, formatted reporting, and file-output entry points without collapsing all summary logic into the core module body.

`ftimer_summary.F90` turns timer state into structured local summaries and formatted report text. This is where entry ordering, explicit summary-tree linkage (`node_id`/`parent_id`), depth attribution, percentages, and self-time computation are assembled for local reporting.

`ftimer_mpi.F90` adds cross-rank behavior on top of local summaries. It verifies that all ranks agree on the timer descriptor set before any collective reduction, using the local summary tree shape plus names rather than raw local node ids, then populates reduced MPI fields only where that contract allows.

`ftimer.F90` exposes the procedural API by forwarding to the default saved `ftimer_t` instance. Shared types and constants still come from `ftimer_types`; they are not re-exported from `ftimer`.

## Runtime Design Highlights

The current implementation is organized around a few design choices that show up across the code, tests, and docs:

- Strict stack-based nesting is the baseline model. Timer overlap is not supported.
- Context-sensitive accounting means the same timer name under different parent stacks is tracked independently.
- Timing data is structured data first and formatted text second.
- Local summary entries keep preorder compatibility for formatting, but they also carry explicit parent-linked tree data within each produced summary object.
- The clock is injectable, which keeps tests deterministic and benchmarking controlled.
- Callback hooks are lightweight intra-run hooks for normal start/stop events only; internal mismatch repair transitions must stay invisible to callback consumers, and current `main` does not define a stronger profiler-backend identity contract.
- MPI summary reduction is descriptor-validated before collectives, and reduced cross-rank fields are valid only in the documented result shape.
- OpenMP support is intentionally narrow: guarded timer operations run only on the master thread when `FTIMER_USE_OPENMP=ON`, so this path should not be read as general hybrid-thread timing support.

Those runtime semantics are specified in detail in [`docs/semantics.md`](semantics.md); this document focuses on how the repository realizes them.

## Public API Shape

The public surface on current `main` is split between:

- the procedural API in `use ftimer`
- the OOP API through `type(ftimer_t)` from `use ftimer_core`
- shared types and constants from `use ftimer_types`

The currently exported procedural entry points are:

- `ftimer_init`
- `ftimer_finalize`
- `ftimer_start`
- `ftimer_stop`
- `ftimer_start_id`
- `ftimer_stop_id`
- `ftimer_lookup`
- `ftimer_reset`
- `ftimer_get_summary`
- `ftimer_mpi_summary`
- `ftimer_print_summary`
- `ftimer_write_summary`
- `ftimer_print_mpi_summary`
- `ftimer_write_mpi_summary`
- `ftimer_default_instance`

Important current-state API notes:

- `ierr` is now the last optional argument in the `init` signatures. Keywords are recommended for readability.
- `get_summary()` is the local structured summary path.
- `ftimer_summary_t` entries now retain `name`/`depth` and also expose `node_id`/`parent_id` links that are stable only within one produced summary object.
- `print_summary()` and `write_summary()` format local report text.
- `mpi_summary()` returns a distinct `ftimer_mpi_summary_t` whose fields are globally meaningful on every participating rank.
- `print_mpi_summary()` and `write_mpi_summary()` are the first-class communicator-level MPI reporting paths.
- `on_event` remains a lightweight intra-run hook; the current public surface does not promise stable semantic timer identity for external-profiler integrations.
- `ftimer_types` owns `ftimer_summary_t`, `ftimer_mpi_summary_t`, `ftimer_metadata_t`, and mismatch constants.

## Build, Test, and CI Reality

The repository supports three distinct validation layers, and the architecture doc should reflect all three accurately.

### Local Build Modes

Supported local build paths today are:

- serial smoke/library build validated with GNU Fortran and LLVM Flang
- serial pFUnit tests with `gfortran` plus a matching pFUnit install
- MPI builds through an MPI wrapper compiler such as `mpifort`
- OpenMP builds with `gfortran`
- benchmark harness builds with `FTIMER_BUILD_BENCH=ON`

The top-level CMake options that shape those paths are:

- `FTIMER_USE_MPI`
- `FTIMER_USE_OPENMP`
- `FTIMER_BUILD_SMOKE_TESTS`
- `FTIMER_BUILD_TESTS`
- `FTIMER_BUILD_EXAMPLES`
- `FTIMER_BUILD_BENCH`

The MPI and OpenMP enablement paths are guarded at configure time:

- `FTIMER_USE_MPI=ON` requires a compiler/toolchain pair that can compile a minimal `use mpi` probe against the discovered MPI installation.
- `FTIMER_USE_OPENMP=ON` is currently supported only with GNU Fortran and requires `OpenMP::OpenMP_Fortran` to resolve successfully.

### Test Categories

The current test inventory is:

- smoke tests in `tests/test_phase0_smoke.F90`, runtime execution of `basic_usage`, installed-package consumer build-and-run checks, and build-contract regression checks under `tests/check_*_contracts.cmake`
- serial pFUnit tests for core behavior, summaries, callbacks, reset behavior, call-stack behavior, and procedural parity
- MPI pFUnit tests under `tests/mpi/`
- OpenMP guard tests enabled when `FTIMER_USE_OPENMP=ON`, covering the master-thread-only carve-out rather than general threaded timing support

The default repository baseline is still the smoke/build-contract path. The full behavioral suite is enabled explicitly with `FTIMER_BUILD_TESTS=ON`.

### GitHub Actions CI

`.github/workflows/ci.yml` currently runs these jobs:

- `build-serial`
- `build-serial-flang`
- `build-mpi`
- `test-serial`
- `test-mpi`
- `build-openmp`
- `test-openmp`
- `build-contract-regressions`
- `build-bench`
- `lint`

That means pFUnit-backed serial, MPI, and OpenMP test jobs are part of current CI now; they are not deferred future work. The contract-regression job also verifies the configure-time MPI/OpenMP gates and the documented Makefile wrapper behavior.

## Maintainer Workflow

Repository workflow guidance lives in [`docs/maintainer.md`](maintainer.md) and the phase-specific docs under [`docs/workflows/`](workflows/). The standard flow for scoped work on current `main` is:

1. Create or link the GitHub issue first.
2. Create a feature branch from updated local `main`.
3. Implement and validate the change.
4. Open a pull request to `main`.
5. Let the review router apply automatic labels, then verify the result and add any extra labels the diff still needs.
6. Monitor review output and address every finding.
7. Do not merge while merge-blocking findings remain unresolved.

The required label policy is current and specific:

- the Codex review router always applies `codex-software-review`
- the router may also auto-apply methodology, red-team, docs-contract, test-quality, build-portability, API-compat, and MPI-safety labels when the diff matches the rules in `.github/codex-review-roles.json`
- maintainers may still add optional deeper-review labels such as performance-overhead, pragmatic-design, adoptability, or completion-audit when the diff warrants them

The repository also carries a detailed prompt library under `.github/prompts/detailed/` for fallback reviews and selective deeper review roles. The machine-readable review-routing catalog lives in `.github/codex-review-roles.json`.

## Documentation Boundaries

The docs set is intentionally split by purpose:

- [`README.md`](../README.md): user-facing setup, usage, limitations, and examples
- [`docs/semantics.md`](semantics.md): current runtime contract and behavior
- [`docs/design.md`](design.md): current repository architecture, validation reality, and workflow context
- [`docs/implementation-history.md`](implementation-history.md): historical phase roadmap and landing history
- [`docs/maintainer.md`](maintainer.md) and [`docs/workflows/`](workflows/): issue/PR/review operating procedures

Keeping those boundaries sharp matters. When current behavior changes, update the document that owns that contract instead of leaving design notes or historical plans to imply current behavior indirectly.

## Deferred Work

Future-facing ideas should stay clearly separated from the current architecture reference. Examples that remain intentionally deferred today include:

- built-in hardware counter or power-measurement backends
- richer export formats such as CSV or JSON
- broader OpenMP support beyond the documented master-thread-only guard model
- stable semantic callback identity or a stronger external-profiler integration contract
- hash-based timer lookup or other hot-path performance redesigns, if profiling ever justifies them

If deferred work needs a maintained roadmap, record it in [`docs/implementation-history.md`](implementation-history.md) or in the relevant issue or PR discussion rather than mixing it into the current-state architecture narrative above.
