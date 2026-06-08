> **When to read this:** When auditing the validation coverage that landed for
> the #267 OpenMP and MPI+OpenMP API sequence, or when adding follow-up
> validation without changing the current timing-mode contract.

# OpenMP And Hybrid Validation Plan

This document records the validation strategy that guided the OpenMP/hybrid
direction from #243 through the landed #267 API sequence. It should now be read
as current validation guidance plus implementation history, not as an unresolved
dependency list. Issue #243 established the initial hybrid build and
installed-consumer compatibility gates. Issues #268, #269, #270, #271, and #272
then landed the explicit `ftimer_openmp_t` public surface, true level-1
thread-lane runtime, stopped-run local OpenMP summary/report/CSV output, strict
MPI+OpenMP rank/lane summary/report/CSV output, and sparse union MPI+OpenMP
rank/lane participation summary/report/CSV output. Issue #242 moved the
durable user-facing timing-mode and migration guidance into
`docs/openmp-timing-modes.md`.

## Decision

Validation should stay organized in two layers:

- current compatibility coverage for configurations that exist on `main`; and
- OpenMP/hybrid behavioral coverage for the landed runtime, summary,
  reduction, documentation, and benchmark surfaces.

The historical #243 change added build-only hybrid coverage:

- a `build-mpi-openmp` CI job that configures, builds, and smoke-tests fTimer
  with both `FTIMER_USE_MPI=ON` and `FTIMER_USE_OPENMP=ON`; and
- an installed-package consumer check that builds the producer with both MPI
  and OpenMP enabled, then verifies the exported package through the MPI
  installed-consumer path, including an MPI-initialized OpenMP region that
  preserves current worker no-op behavior.

That initial coverage proved the MPI and OpenMP compatibility options could
coexist before true worker timing and hybrid reductions landed. Current strict
and sparse union hybrid smoke coverage now exercises `ftimer_openmp_t`
rank/lane reductions. None of this should be read as evidence that the
procedural `ftimer` or OOP `ftimer_core` APIs perform true worker-thread
timing.

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
- MPI+OpenMP smoke coverage for the current compatibility mode plus strict and
  sparse union `ftimer_openmp_t` rank/lane reductions; and
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

The first true OpenMP runtime is now available through the explicit
`ftimer_openmp_t` object. Deterministic tests cover, and should continue to
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

## MPI+OpenMP Reduction Matrix

Current strict hybrid tests cover at least two MPI ranks and multiple OpenMP
lanes per rank for:

- all-rank/all-eligible-lane participation;
- rank-level imbalance fields;
- strict descriptor mismatch failures, including descriptor names, execution
  domain, and eligible lane structure;
- missing eligible lane participation failures;
- all-rank active-lane and open-region preflight returning
  `FTIMER_ERR_ACTIVE` before descriptor or timing-data reductions;
- all-rank structured result validity after successful hybrid reductions; and
- hybrid report and CSV output, including append rejection against malformed or
  incompatible hybrid schemas.

Sparse/union MPI+OpenMP participation tests should cover:

- rank-conditional descriptors;
- lane-conditional descriptors inside participating ranks;
- different OpenMP team sizes across ranks under participation-aware policy;
- deterministic canonical descriptor ordering and `node_id`/`parent_id`
  assignment when local creation order differs across ranks; and
- participation-aware report and CSV output that is explicitly separate from
  the strict hybrid schema.

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
  `start_id`/`stop_id`, preserves bounded worker diagnostics, exercises
  stopped-run local OpenMP summary/report/CSV entry points, and compile-calls
  the strict hybrid summary API from installed MPI+OpenMP consumers; and
- strict and sparse union hybrid summary/report/CSV smoke coverage when
  `FTIMER_USE_MPI=ON` and `FTIMER_USE_OPENMP=ON` are enabled.

Sparse/union hybrid installed consumers should compile their documented source
shapes, run the supported examples, and assert the exported CMake package
resolves only the dependencies required by the selected feature mode.

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

Performance validation is now part of the current follow-up surface rather than
an implementation prerequisite. The benchmark harness already includes rows for
the explicit `ftimer_openmp_t` serial-lane id path, timed-region open/close,
warmed worker-lane id path, local OpenMP summary merge, strict MPI+OpenMP CSV
output, and sparse union MPI+OpenMP CSV output. Current CI includes serial,
OpenMP, and MPI+OpenMP benchmark CSV smoke jobs that build `ftimer_bench` and
verify parseable CSV output for the configured feature mode. Dedicated artifact
upload for OpenMP and MPI+OpenMP benchmark CSVs remains follow-up work under
#285, so release docs should distinguish feature-enabled CSV smoke coverage
from durable uploaded benchmark artifacts.

For true worker timing and hybrid reductions, measurements should track:

- serial hot-path overhead relative to current `ftimer_t`;
- MPI-only hot-path and summary overhead relative to current pure-MPI paths;
- master-thread-only OpenMP overhead for current compatibility mode;
- warmed worker `start_id`/`stop_id` overhead in the opt-in runtime;
- timed-region open/close overhead;
- lane merge cost for local summaries;
- descriptor-union and rank/lane materialization cost for strict and sparse
  hybrid summaries; and
- memory growth for lane-local stacks, diagnostics, and summary artifacts.

Benchmarks should report configuration, compiler, MPI implementation, OpenMP
runtime, rank count, lane count, timer count, and nesting shape so later
comparisons are meaningful.

## Non-Goals

- Claiming true OpenMP worker timing from the historical #243 build-only
  coverage alone.
- Treating MPI+OpenMP build success alone as proof of sparse/union hybrid
  rank/lane reductions.
- Requiring every CI runner to support every MPI/OpenMP/compiler combination.
- Weakening current worker no-op compatibility tests.
- Adding automatic MPI barriers, nested OpenMP team support, OpenMP task
  migration support, accelerator/device timing, hardware counters, worker
  callback streams, traces, or profiler callback identity.

## Landed Implementation History

- #243 established the first MPI+OpenMP build and installed-consumer
  compatibility coverage.
- #268 landed the initial `ftimer_openmp` lifecycle, configuration, and public
  API surface.
- #269 landed runtime lane state, timed-region epochs, active-lane scans, and
  diagnostics for true worker timing tests.
- #270 landed stopped-run local OpenMP summary/report/CSV behavior and its
  validation matrix.
- #271 landed strict MPI+OpenMP rank/lane summary/report/CSV behavior and the
  descriptor/eligible-lane checks that MPI+OpenMP tests enforce.
- #272 landed sparse union MPI+OpenMP rank/lane participation
  summary/report/CSV behavior, keeping it separate from the strict hybrid
  path.
- #242 records the user-facing timing modes and migration guidance now carried
  by `docs/openmp-timing-modes.md`.

The earlier #240 and #241 design records remain historical inputs for the
summary and hybrid-reduction contracts. They are no longer prerequisites for
this validation plan.

## Validation For This Plan

Focused validation for changes to this plan should include the release docs
contract, the OpenMP/hybrid examples contract, and `git diff --check`. Because
this file is historical guidance rather than a live user-facing contract,
changes here should update live docs only when current behavior, examples, or
release navigation are implicated.
