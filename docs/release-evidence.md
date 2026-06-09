# Release Claim-Evidence Ledger

This ledger is the release-prep scratchpad for matching user-visible claims to
validation evidence. Use it before writing release notes: keep claims narrow,
name the evidence that backs them, and call out plausible but unvalidated
combinations directly.

Status vocabulary:

- **Release-validated**: covered by current documented local commands and CI
  jobs for the named toolchain or mode.
- **Evidence-backed**: covered by source, tests, examples, or docs, but not a
  broad compatibility claim.
- **Plausible but unvalidated**: may work, but is not part of the
  release-validated support boundary.
- **Non-goal**: intentionally outside the current release claim.

## Dry-Run Release-Note Claim Map

A current release note should be able to claim:

- disciplined serial wall-clock timing with structured summaries, reports, CSV,
  scoped guards, callbacks, mock-clock-friendly tests, and benchmark evidence;
- pure MPI summaries and reports through the `mpi_f08` communicator contract;
- OpenMP compatibility for existing `ftimer`/`ftimer_core` users through the
  master-thread-only carve-out;
- opt-in true OpenMP worker timing through `ftimer_openmp_t`;
- strict and sparse union MPI+OpenMP rank/lane summary, report, and CSV output
  for the currently validated hybrid path;
- stable CSV/export schemas within the documented schema lines;
- installed CMake package consumption for supported feature modes;
- a curated public symbol boundary; and
- benchmark harness evidence for release-readiness sweeps and performance-risk
  PRs.

The same release note should not claim broad compiler portability, MPICH
MPI+OpenMP validation, package-manager availability, profiler-backend
integration, hardware-counter support, FPM support, benchmark pass/fail
thresholds, traces, dashboards, device synchronization, or automatic MPI
barriers unless a later release issue adds matching evidence.

## Claim Ledger

| Release claim area | Current status | Evidence to cite | Caveats and compatibility boundary |
| --- | --- | --- | --- |
| Serial timing | Release-validated for GNU Fortran and LLVM Flang smoke/library builds; pFUnit behavioral coverage is GNU Fortran. | `build-serial`, `build-serial-flang`, and `test-serial` CI jobs; `tests/test_*.pf`; `tests/test_phase0_smoke.F90`; `examples/basic_usage.F90`; `README.md` "Supported toolchain matrix". | Other serial compilers may work, but are plausible and unvalidated until release evidence exists. Wall-clock timing does not synchronize accelerator/device queues. |
| Pure MPI | Release-validated for GNU Fortran wrapper builds with OpenMPI and MPICH. | `build-mpi`, `build-mpi-mpich`, `test-mpi`, and `test-mpi-mpich` CI jobs; `tests/mpi/test_mpi_*.pf`; `examples/mpi_example.F90`; configure-time `mpi_f08` probe in `CMakeLists.txt`; `docs/semantics.md` MPI contract. | Requires MPI lifetime discipline and the `mpi_f08` `type(MPI_Comm)` contract. Legacy integer communicators, `mpif.h`, divergent collectives, and automatic MPI barriers are outside the claim. |
| OpenMP compatibility | Release-validated for GNU Fortran OpenMP and LLVM Flang OpenMP smoke/example paths. | `build-openmp`, `build-openmp-flang`, and `test-openmp` CI jobs; `tests/test_openmp_guards.pf`; `tests/check_openmp_option_off_global_flags.cmake`; `examples/openmp_example.F90`; `docs/openmp-timing-modes.md`. | This is the master-thread-only carve-out for existing APIs. It is not general thread safety, thread-local timing, nested worker timing, or a hybrid timing model by itself. |
| `ftimer_openmp_t` | Release-validated as the opt-in serial-lane and level-1 worker timing API in OpenMP builds; serial-context lifecycle/catalog/timing is available in non-OpenMP packages. | `tests/test_openmp_api_smoke.F90`; `tests/test_openmp_summary_smoke.F90`; OpenMP diagnostic smoke tests; `tests/check_installed_openmp_hybrid_api_surface.cmake`; `examples/openmp_worker_example.F90`; `docs/installed-api.md`. | Worker timing requires `FTIMER_USE_OPENMP=ON`, an opened level-1 timed region, pre-registered ids for the hot path, and stopped-run summary/report calls. Global downstream OpenMP flags do not retrofit OpenMP support into a non-OpenMP fTimer package. |
| Strict/sparse hybrid output | Release-validated for OpenMPI wrapper MPI+OpenMP smoke/install-consumer coverage with GNU Fortran and OpenMP. MPICH MPI+OpenMP remains plausible but unvalidated. | `build-mpi-openmp` CI job; `tests/test_openmp_mpi_summary_smoke.F90`; `tests/test_openmp_mpi_summary_3rank_smoke.F90`; `tests/check_openmp_mpi_union_descriptor_contract.cmake`; `examples/mpi_openmp_example.F90`; `tests/install-consumer/mpi_openmp_main.F90`; `README.md` hybrid contract. | Strict hybrid output rejects descriptor, eligible-lane, and mixed-epoch unknown missing-lane precision mismatches. Sparse union hybrid output is a separate participation-aware API and schema with explicit unknown missing-sample flags; it is not append-compatible with strict hybrid CSV. |
| Stable CSV/export claims | Evidence-backed for the documented schema lines and append-validation behavior. | `tests/test_file_output.pf`; `tests/check_openmp_summary_smoke.cmake`; `tests/check_openmp_mpi_summary_smoke.cmake`; `tests/check_bench_csv_output.cmake`; CSV sections in `README.md`, `docs/semantics.md`, and `docs/troubleshooting.md`. | CSV is the first stable machine-readable export, not a trace/event/profiler format. Local/strict MPI, sparse MPI union, OpenMP, strict hybrid, and sparse hybrid schemas are dedicated and intentionally not append-compatible with one another. |
| Installed CMake package behavior | Release-validated for the supported serial, MPI, OpenMP, and MPI+OpenMP installed-consumer paths. | `ftimer_installed_package_consumer*` CTest entries; `tests/check_installed_package_consumer.cmake`; `tests/install-consumer/*.F90`; installed docs check for `docs/installed-api.md` and `LICENSE`; `docs/installed-api.md`. | Installed `.mod` artifacts are compiler-, wrapper-, and feature-mode-specific. FPM, binary packages, cross-compiler module reuse, and broad package-manager support are non-goals unless separately validated. |
| Public symbols | Evidence-backed by an allowlisted source-level API boundary. | `tests/public_symbol_allowlist.txt`; `tests/check_public_symbol_allowlist.cmake`; `docs/installed-api.md`; `src/ftimer.F90`, `src/ftimer_core.F90`, `src/ftimer_openmp.F90`, and `src/ftimer_types.F90`. | New module-level public names must be intentionally classified as stable, unstable public-by-necessity, or test-only. Installed implementation module artifacts are not stable import targets. |
| Benchmark evidence | Evidence-backed for trend review and release-readiness sweeps, not pass/fail thresholds. Durable comparisons require the benchmark CSV plus the provenance sidecar policy in `docs/release.md`. | `build-bench`, `build-openmp-bench`, and `build-mpi-openmp-bench` CI jobs; `bench/ftimer_bench.F90`; `bench_csv_smoke`; serial CI artifact `ftimer-bench-serial-<sha>`; benchmark commands in `README.md` and `docs/release.md`. | GitHub-hosted runner timings are noisy. Serial CSV artifacts are uploaded by CI; OpenMP and MPI+OpenMP benchmark CI jobs currently smoke-check parseable CSV but do not upload durable feature-enabled artifacts. Feature-enabled trend evidence is local CSV plus sidecar unless a future issue adds sidecar-aware CI artifact upload. |

## Release Prep Update Rules

- Add a row only for a release-significant claim that maintainers may repeat in
  release notes, README support text, or downstream compatibility guidance.
- Keep evidence concrete: prefer CI job names, CTest names, examples, and
  source-of-truth docs over broad phrases like "covered by tests".
- When a new combination looks likely but lacks CI or local release evidence,
  mark it **Plausible but unvalidated** instead of widening the support matrix.
- When evidence changes because a CI job or smoke test is renamed, update this
  ledger in the same PR as the rename.
- Do not turn benchmark evidence into a threshold or gate here. This file records
  what evidence exists; `docs/release.md` owns release execution policy.
