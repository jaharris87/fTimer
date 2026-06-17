# fTimer v1.0.0 Release Notes Draft

Status: release-prep draft for issue #354. This file is the prepared release
note source for the eventual `v1.0.0` GitHub release. It does not create a tag,
publish a GitHub release, or add release assets.

## Audience And Scope

fTimer 1.0.0 is for Fortran projects that need disciplined wall-clock timing
with structured summaries, human reports, CSV exports, and an explicit
correctness contract. The release-supported workflows are:

- serial/local timing through `ftimer` or `ftimer_core`;
- strict pure-MPI timing and sparse pure-MPI union timing through the validated
  `mpi_f08` communicator contract;
- OpenMP compatibility timing where existing `ftimer` / `ftimer_core` calls
  bracket a parallel region from serial context;
- true OpenMP worker timing through the explicit `ftimer_openmp_t` object API;
- strict MPI+OpenMP rank/lane summaries, reports, and CSV output through
  `ftimer_openmp_t`; and
- sparse union MPI+OpenMP rank/lane participation summaries, reports, and CSV
  output through `ftimer_openmp_t`.

See the claim boundary in [`docs/release-evidence.md`](release-evidence.md)
and the execution checklist in [`docs/release.md`](release.md).

## Highlights

- Serial timing remains the smallest adoption path: initialize, start/stop named
  timers, retrieve `ftimer_summary_t`, and print or write reports.
- Pure-MPI timing uses `mpi_f08` `type(MPI_Comm)` handles captured at `init`.
  Strict MPI summaries require matching descriptor trees; sparse union MPI
  summaries represent rank-conditional participation explicitly.
- `FTIMER_USE_OPENMP=ON` keeps the existing APIs on the documented
  master-thread-only compatibility carve-out. Worker-thread calls through those
  existing APIs are silent no-ops and do not contribute timing data.
- `ftimer_openmp_t` is the supported opt-in worker-timing surface. It uses
  serial-context lifecycle/catalog calls, pre-registered timer ids, explicit
  timed level-1 OpenMP regions, and stopped-run local OpenMP summaries.
- MPI+OpenMP builds add strict and sparse union hybrid report families for
  rank/lane data. Strict hybrid output rejects descriptor or eligible-lane
  mismatches; sparse union hybrid output keeps missing rank/lane samples as
  participation metadata rather than zero-filled timing samples.
- The source examples named by the release are
  [`examples/basic_usage.F90`](../examples/basic_usage.F90),
  [`examples/mpi_example.F90`](../examples/mpi_example.F90),
  [`examples/openmp_example.F90`](../examples/openmp_example.F90),
  [`examples/openmp_worker_example.F90`](../examples/openmp_worker_example.F90),
  and [`examples/mpi_openmp_example.F90`](../examples/mpi_openmp_example.F90).

## Compatibility And Public Surface

- The stable source-level import surfaces are `ftimer`, `ftimer_core`,
  `ftimer_openmp`, and `ftimer_types`.
- For the 1.x release line, CMake package version compatibility uses
  `SameMajorVersion`: a `1.y.z` install may satisfy same-major requests at or
  older than the installed package version, rejects future-major requests, and
  rejects same-major requests newer than the installed package.
- Installed Fortran `.mod` files remain compiler-, wrapper-, runtime-, and
  feature-mode-specific artifacts. A serial install is not promised to satisfy
  an MPI, OpenMP, MPI+OpenMP, or different-compiler downstream build.
- CSV is the stable machine-readable export family. Local and strict MPI CSV
  share the `format_version=2` schema line; sparse MPI union, local OpenMP,
  strict MPI+OpenMP, and sparse MPI+OpenMP union use dedicated schemas that are
  not append-compatible with each other.
- Fixed-width text reports are human-facing output. Use structured summary
  objects or CSV for machine parsing.
- The callback hook remains a lightweight intra-run event hook, not a stable
  profiler-backend integration contract with semantic timer identity.

Detailed API and installed-package notes live in
[`docs/installed-api.md`](installed-api.md). CSV field details live in
[`docs/csv-schema.md`](csv-schema.md).

## Packaging And Artifacts

The v1.0.0 release artifact policy is source-only:

- publish the annotated or signed `v1.0.0` tag;
- publish GitHub release notes from this draft after final validation;
- rely on GitHub-generated source archives, which include the root
  [`LICENSE`](../LICENSE); and
- keep generated install-tree artifacts reproducible through the documented
  CMake install path.

Do not attach binary packages, generated install trees, compiler module
bundles, benchmark CSVs, generated reports, Spack recipes, or EasyBuild
easyconfigs to the GitHub release unless a separate release issue accepts that
artifact type and records its build, validation, and licensing basis.

The installed CMake package path installs documentation under
`share/doc/fTimer/`, including `installed-api.md` and `LICENSE`.

## Migration Notes

- Existing serial and pure-MPI users do not need source changes for v1.0.0.
- Existing OpenMP compatibility users should keep timing calls outside
  `!$omp parallel` blocks when they want one wall-clock interval for a parallel
  region.
- Applications that currently call `ftimer_start`/`ftimer_stop` inside an
  OpenMP parallel region expecting every worker to contribute should either
  move those calls outside the parallel region or migrate those hot paths to
  `ftimer_openmp_t`.
- Applications that need compile-out behavior should use an application-owned
  timing facade. fTimer does not install a drop-in no-op `ftimer` module.

## Known Limitations And Deferred Work

- MPICH MPI+OpenMP hybrid support is caveated for v1.0.0: OpenMPI
  MPI+OpenMP is routine CI-covered, while MPICH MPI+OpenMP remains focused
  local-evidence-backed support from the release ledger, not permanent PR CI
  coverage. Issue #353 owns that decision.
- Package-manager availability and package-recipe ownership remain post-v1.0
  questions tracked by issue #355. The Spack and EasyBuild material in
  [`docs/package-manager-readiness.md`](package-manager-readiness.md) is
  readiness guidance only, not maintained package-manager support.
- Fixed-team or no-explicit-region OpenMP worker ergonomics are deferred to
  issue #294.
- Ubuntu 24.04 MPICH pFUnit runner migration remains post-release maintenance
  tracked by issue #259.
- NVHPC serial smoke/install-consumer validation remains unclaimed and tracked
  by issue #256.
- fTimer remains wall-clock only. It does not synchronize accelerator/device
  queues, insert MPI barriers, provide hardware counters, emit traces, publish
  dashboards, support FPM packaging, or claim profiler-backend integration.

## Validation Summary

The release-prep validation record is
[`docs/release-validation-v1.0.0.md`](release-validation-v1.0.0.md). It records
local commands, toolchain versions, skips, artifact checks, and the required CI
jobs for the release-prep PR.

Before tagging, require the release-prep PR to pass every job in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml), including the
`CI` workflow jobs, `Codex Review Routing and Triggers`, and
`Codex Review Coverage`.

## Benchmark Evidence Handling

Benchmark CSVs are review evidence, not release assets and not pass/fail
thresholds. This release note intentionally makes no benchmark trend or
absolute-overhead claim. Any future release-note benchmark observation must
cite the corresponding CSV plus a sidecar/provenance record as described in
[`docs/release.md`](release.md).

## Important Release-Readiness Links

- Umbrella: #348
- This closeout issue: #354
- 1.x compatibility decision: #349
- v1.0 package-version implementation: #350 and PR #356
- public API and output-surface decision: #351
- v1.0 claim/evidence refresh: #352 and PR #357
- MPICH MPI+OpenMP evidence decision: #353
