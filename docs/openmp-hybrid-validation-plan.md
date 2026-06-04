> **When to read this:** When adding, reviewing, or extending OpenMP and
> MPI+OpenMP validation under umbrella issue #237.

# OpenMP And Hybrid Validation Plan

Issue #243 defines the validation strategy for the OpenMP/hybrid direction
recorded in #238, #239, #240, and #241. This document is a validation contract.
Issue #268 adds the initial `ftimer_openmp` public API surface and lifecycle
coverage, #269 adds the first true OpenMP thread-lane runtime, and #270 adds
stopped-run local OpenMP summary, report, and CSV coverage. Hybrid reductions
and changes to the current `FTIMER_USE_OPENMP=ON` master-thread-only
compatibility mode remain deferred to later #267 child issues.

## Decision

Validation should advance in two layers:

- current compatibility coverage for configurations that exist on `main`; and
- OpenMP/hybrid behavioral coverage that lands with the corresponding runtime,
  summary, reduction, documentation, and benchmark work.

The initial #243 change adds current build-only hybrid coverage:

- a `build-mpi-openmp` CI job that configures, builds, and smoke-tests fTimer
  with both `FTIMER_USE_MPI=ON` and `FTIMER_USE_OPENMP=ON`; and
- an installed-package consumer check that builds the producer with both MPI
  and OpenMP enabled, then verifies the exported package through the MPI
  installed-consumer path, including an MPI-initialized OpenMP region that
  preserves current worker no-op behavior.

That initial coverage proves the current MPI and OpenMP compatibility options
can coexist. It must not be read as evidence that the current `ftimer`/
`ftimer_core` APIs perform true worker-thread timing or that hybrid rank/lane
reductions are implemented.

## Current Compatibility Coverage

Current `main` should keep these validation gates:

- serial smoke and pFUnit jobs;
- pure-MPI OpenMPI and MPICH smoke, pFUnit, example, and installed-consumer
  coverage;
- GNU OpenMP master-thread-only smoke and pFUnit guard coverage;
- LLVM Flang OpenMP smoke and installed-consumer coverage when a discoverable
  `libomp` runtime is available;
- option-off/global-OpenMP regression coverage for #199;
- build-contract regression coverage for configure gates and Makefile wrapper
  behavior;
- MPI+OpenMP build-only smoke coverage for the current compatibility mode; and
- `ftimer_openmp` API/lifecycle, timed-region, thread-lane runtime,
  diagnostics, public-symbol, and installed-package consumer coverage for the
  current opt-in worker timing boundary.

The compatibility matrix is intentionally about today's APIs:

- `type(ftimer_t)`, procedural wrappers, `get_summary()`, `mpi_summary()`, and
  `mpi_union_summary()` keep their existing contracts.
- `FTIMER_USE_OPENMP=ON` continues to mean master-thread-only guards for
  current APIs, not true worker timing.
- The procedural default instance remains excluded from true worker timing.
- `FTIMER_USE_MPI=ON` plus `FTIMER_USE_OPENMP=ON` must build and install
  cleanly without changing pure-MPI result shapes.
- The MPI+OpenMP installed-consumer test should be registered only in top-level
  hybrid builds. The dedicated hybrid CI job should assert that the test is
  present and executed so non-hybrid smoke jobs do not accidentally claim
  unsupported hybrid toolchain coverage.

## Current Thread-Lane Runtime Test Matrix

#269 introduces the first true OpenMP runtime through the explicit
`ftimer_openmp_t` object. Deterministic tests now cover, and should continue to
cover:

- explicit opt-in construction through the current `ftimer_openmp` module and
  `ftimer_openmp_t` object with real worker timing enabled;
- one strict stack per OpenMP lane, initially one lane per level-1 team thread;
- serial-context timer registration before worker use;
- id-based `start_id`/`stop_id` inside a timed parallel-region epoch;
- worker-only timers, all-lane timers, and mixed serial/worker timers;
- nested timers with independent lane-local stacks;
- cross-thread stop attempts that fail lane-locally without mutating another
  lane's stack;
- active-lane lifecycle errors for reset, timed-region close, and finalize;
- bounded diagnostic storage and deterministic aggregate diagnostics;
- thread-private `ierr` behavior on worker paths; and
- compatibility tests proving current `FTIMER_USE_OPENMP=ON` worker no-op
  behavior remains unchanged for existing APIs.

Tests should use the injectable mock clock or a deterministic OpenMP-aware clock
model. They should not sleep or depend on wall-clock timing jitter.

## Summary And Report Matrix

Local OpenMP summaries, reports, and CSV output are current behavior. Tests
should cover:

- stopped-run-only summary construction and active-lane refusal;
- wall-clock `timed_region_envelope_time` distinct from summed lane work;
- lane participation, missing-lane counts, and `*_known` fields for ambiguous
  mixed-epoch aggregates;
- self time computed from lane-local direct children before cross-lane
  aggregation;
- aggregate-first summary rows without requiring lane detail rows;
- local OpenMP text report output that labels envelope time and summed work
  separately;
- local OpenMP CSV schema versioning and append-header rejection; and
- compatibility with current local, strict MPI, and sparse MPI CSV/report
  schemas.

Opt-in lane-detail exports are not part of the current local OpenMP public
surface. They should move into this matrix only after a dedicated detail result
or diagnostic CSV mode exists.

## Future MPI+OpenMP Reduction Matrix

When #241's reduction contract is implemented, tests should cover at least two
MPI ranks and at least two OpenMP lanes per rank for:

- participation-aware hybrid summaries with all-rank/all-lane participation;
- rank-conditional descriptors;
- lane-conditional descriptors inside participating ranks;
- different OpenMP team sizes across ranks under participation-aware policy;
- strict-semantics validation failures for descriptor, eligible-lane, missing
  rank, and missing-lane mismatches, even if strict remains internal or
  adopter-driven rather than first public API;
- all-rank active-lane preflight returning `FTIMER_ERR_ACTIVE` before descriptor
  or timing-data reductions;
- invalid worker-thread reduction calls failing locally without MPI calls;
- all-rank structured result validity after successful hybrid reductions;
- deterministic canonical descriptor ordering and `node_id`/`parent_id`
  assignment when local creation order differs across ranks; and
- hybrid report and CSV golden output, including append rejection against local,
  strict MPI, sparse MPI, and incompatible hybrid schemas.

MPI+OpenMP validation must not add automatic barriers around timed user
regions. Callers own synchronization when they want phase-aligned measurements.

## Installed-Consumer Coverage

Installed-package checks should verify the public package story at each stage:

- current serial installed consumers;
- current MPI installed consumers using `mpi_f08` and an MPI wrapper compiler;
- current OpenMP installed consumers using the master-thread-only package
  contract;
- current MPI+OpenMP installed consumers proving that exported MPI and OpenMP
  dependencies can coexist;
- current `ftimer_openmp` installed consumers for serial, MPI, OpenMP, and
  MPI+OpenMP package modes, proving that the lifecycle/catalog surface imports,
  links, validates keyword-only init shape, runs serial and timed worker
  `start_id`/`stop_id`, preserves bounded worker diagnostics, and exercises
  stopped-run local OpenMP summary/report/CSV entry points; and
- strict hybrid summary/report/CSV smoke coverage once `FTIMER_USE_MPI=ON` and
  `FTIMER_USE_OPENMP=ON` are enabled.

Future sparse/union hybrid installed consumers should compile their documented
source shapes, run the supported examples, and assert the exported CMake
package resolves only the dependencies required by the selected feature mode.

## Toolchain And Skip Policy

Unsupported toolchains should skip or fail explicitly, never silently pretend
to provide coverage.

- GNU Fortran remains the primary OpenMP pFUnit path.
- OpenMPI remains the primary hosted hybrid smoke path until MPICH+OpenMP
  coverage is separately proven.
- MPICH hybrid coverage may be added after the existing MPICH launcher probes
  demonstrate a real multi-rank `MPI_COMM_WORLD` for the selected runner.
- LLVM Flang OpenMP smoke coverage remains useful for the master-thread-only
  carve-out, but it is not a substitute for GNU pFUnit behavioral coverage.
- Cross-compiling or execution-restricted package builds may use
  `FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK=ON` only after independent validation of
  equivalent OpenMP master-thread and worker-lane runtime semantics.

Any skipped optional path should emit a clear CMake or CI message naming the
missing compiler, MPI wrapper, launcher, OpenMP runtime, or pFUnit dependency.

## Performance Validation

Performance validation belongs with implementation issues, not with this
build-only compatibility PR. For true worker timing, measurements should track:

- serial hot-path overhead relative to current `ftimer_t`;
- MPI-only hot-path and summary overhead relative to current pure-MPI paths;
- master-thread-only OpenMP overhead for current compatibility mode;
- warmed worker `start_id`/`stop_id` overhead in the opt-in runtime;
- timed-region open/close overhead;
- lane merge cost for local summaries;
- descriptor-union and rank-level materialization cost for hybrid summaries;
- optional rank/lane detail materialization cost; and
- memory growth for lane-local stacks, diagnostics, and summary artifacts.

Benchmarks should report configuration, compiler, MPI implementation, OpenMP
runtime, rank count, lane count, timer count, and nesting shape so later
comparisons are meaningful.

## Non-Goals

- Claiming true OpenMP worker timing from the initial #243 build-only coverage.
- Adding pFUnit tests for future sparse/union summary/reduction APIs that do
  not exist yet.
- Treating MPI+OpenMP build success as proof of sparse/union hybrid rank/lane
  reductions.
- Requiring every CI runner to support every MPI/OpenMP/compiler combination.
- Weakening current worker no-op compatibility tests.
- Adding automatic MPI barriers, OpenMP task timing, accelerator/device timing,
  hardware counters, traces, or profiler callback identity.

## Dependencies On Later Child Issues

- #269 provides runtime lane state, timed-region epochs, active-lane scans, and
  diagnostics for true worker timing tests.
- #240 provides local OpenMP summary/report/CSV behavior for summary golden
  tests.
- #241 provides the hybrid reduction contract that MPI+OpenMP pFUnit and CSV
  tests must enforce.
- #242 records user-facing timing modes and migration guidance. Current local
  OpenMP examples and installed consumers should stay compile-checked; later
  implementation issues add sparse/union hybrid examples and installed
  consumers once that API exists.

## Validation For This Plan

Issue #243 adds CI/package validation wiring for current feature flags and a
durable test plan for future APIs. Focused validation should include CMake
configure/build checks for the added hybrid smoke surface, docs contract checks,
and `git diff --check`.
