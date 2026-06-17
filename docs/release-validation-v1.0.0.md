# fTimer v1.0.0 Validation And Artifact Record

Status: release-prep record for issue #354. This record supports the
v1.0.0 release-notes draft in
[`docs/release-notes-v1.0.0.md`](release-notes-v1.0.0.md). It does not tag or
publish the release.

## Claim Boundary

Validation and release wording for v1.0.0 are bounded by
[`docs/release-evidence.md`](release-evidence.md). In particular:

- #349, #350, #351, #352, and #353 are the release-blocking prerequisite
  decisions or implementations for this closeout.
- #355, #294, #259, and #256 remain post-release or non-blocking follow-ups
  unless a maintainer later changes their scope.
- MPICH MPI+OpenMP hybrid support remains local-evidence-backed and caveated
  for v1.0.0, not permanent PR CI coverage.
- Package-manager material is readiness guidance only.
- Benchmark observations require CSV plus sidecar/provenance evidence before
  they can become release-note trend claims.

## Local Environment

Local validation for this PR was run on:

- OS: Darwin `mac149625` 25.5.0, arm64.
- CMake: 4.3.3.
- GNU Fortran: Homebrew GCC 15.3.0 at `/opt/homebrew/bin/gfortran`.
- MPI wrapper: `/opt/homebrew/bin/mpifort`, reporting GNU Fortran 15.3.0.
- MPI launcher: `/opt/homebrew/bin/mpiexec`, Open MPI 5.0.9.
- pFUnit: `/opt/homebrew/PFUNIT-4.16`, `PFUNIT_VERSION` 4.16.0,
  `PFUNIT_MPI_FOUND` true.
- LLVM Flang: `/opt/homebrew/bin/flang`, Homebrew flang 22.1.7.
  `flang-19` was not on `PATH` locally.

## Local Validation Commands

The release checklist in [`docs/release.md`](release.md) defines the command
set. This PR records exact local commands and CI coverage rather than
overclaiming unavailable local toolchains.

| Area | Command | Local status |
| --- | --- | --- |
| Smoke/install path | `cmake -B build-smoke` | Passed with default `/opt/homebrew/bin/flang` LLVMFlang 22.1.7. |
| Smoke/install path | `cmake --build build-smoke` | Passed. |
| Smoke/install path | `cmake -E chdir build-smoke ctest --output-on-failure` | Passed, 25/25 tests. This included `ftimer_release_docs_contract`, `ftimer_installed_package_consumer`, installed docs checks, examples, and contract checks. |
| Serial pFUnit | `FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/opt/homebrew/PFUNIT-4.16` | Passed with `/opt/homebrew/bin/gfortran` 15.3.0. |
| Serial pFUnit | `cmake --build build` | Passed. |
| Serial pFUnit | `cmake -E chdir build ctest --output-on-failure` | Passed, 26/26 tests, including `ftimer_serial_tests`. |
| MPI pFUnit | `FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/opt/homebrew/PFUNIT-4.16 -DMPIEXEC_EXECUTABLE=/opt/homebrew/bin/mpiexec` | Passed with `/opt/homebrew/bin/mpifort` and Open MPI 5.0.9. |
| MPI pFUnit | `cmake --build build-mpi` | Passed. |
| MPI pFUnit | `cmake -E chdir build-mpi ctest --output-on-failure -L mpi` | Did not complete locally: CTest-launched `ftimer_mpi_tests` and `ftimer_mpi_tests_4pe` failed before test execution with Open MPI reporting `All nodes which are allocated for this job are already filled.` The same CTest run passed `ftimer_mpi_example_smoke`. Direct generated pFUnit commands passed: `/opt/homebrew/bin/mpiexec -n 2 .../ftimer_mpi_tests --verbose` reported OK with 79 tests, and `/opt/homebrew/bin/mpiexec -n 4 .../ftimer_mpi_tests_4pe --verbose` reported OK with 22 tests. |
| MPI+OpenMP smoke | `FC=mpifort cmake -B build-mpi-openmp -DFTIMER_USE_MPI=ON -DFTIMER_USE_OPENMP=ON` | Passed with `/opt/homebrew/bin/mpifort` and Open MPI 5.0.9. |
| MPI+OpenMP smoke | `cmake --build build-mpi-openmp` | Passed. |
| MPI+OpenMP smoke | `cmake -E chdir build-mpi-openmp ctest --output-on-failure` | Passed, 35/35 tests, including MPI+OpenMP example and installed-consumer coverage. |
| OpenMP pFUnit | `FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/opt/homebrew/PFUNIT-4.16` | Passed with `/opt/homebrew/bin/gfortran` 15.3.0. |
| OpenMP pFUnit | `cmake --build build-openmp` | Passed. |
| OpenMP pFUnit | `cmake -E chdir build-openmp ctest --output-on-failure` | Passed, 31/31 tests, including OpenMP guard tests and worker examples. |
| Benchmark harness | `cmake -S . -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release` | Passed with default `/opt/homebrew/bin/flang` LLVMFlang 22.1.7. |
| Benchmark harness | `cmake --build build-bench --target ftimer_bench` | Passed. |
| Benchmark harness | `./build-bench/bench/ftimer_bench /tmp/ftimer_bench_results.csv` | Passed and wrote a 52-line CSV at `/tmp/ftimer_bench_results.csv`. Numeric rows are not used as release-note trend claims in this PR. |
| Diff hygiene | `git diff --check` | Passed after final doc updates. |

## Unavailable Local Validation

- The documented `flang-19` executable was not available on `PATH`; local
  smoke and benchmark configures used Homebrew `/opt/homebrew/bin/flang`
  22.1.7 where CMake selected it by default. The corresponding CI job for the
  documented LLVM Flang OpenMP path remains `build-openmp-flang`.
- MPICH local validation was not run from this worktree because the local
  `mpifort` / `mpiexec` pair is Open MPI 5.0.9 and `mpifort.mpich` was not on
  `PATH`. The release evidence for pure MPICH remains the CI
  `build-mpi-mpich` and `test-mpi-mpich` jobs; the MPICH MPI+OpenMP hybrid
  boundary remains the #353 local-evidence caveat.
- Direct Spack and EasyBuild execution was not run because package-manager
  availability remains a post-v1.0 ownership question tracked by #355, and
  neither `spack` nor `eb` was on `PATH` locally.
- NVHPC validation was not run and is not claimed; #256 remains the
  post-release investigation issue.

## Required CI Proof

Before the release-prep PR can be considered merge-ready, the following CI
proof must be green on the PR head:

- `build-serial`
- `build-serial-flang`
- `build-mpi`
- `build-mpi-mpich`
- `build-mpi-openmp`
- `test-serial`
- `test-mpi`
- `test-mpi-mpich`
- `build-openmp`
- `build-openmp-flang`
- `test-openmp`
- `build-contract-regressions`
- `build-bench`
- `build-openmp-bench`
- `build-mpi-openmp-bench`
- `lint`
- `Codex Review Routing and Triggers`
- `Codex Review Coverage`

## Artifact Closeout

- `CMakeLists.txt` declares `project(fTimer VERSION 1.0.0)`.
- `CMakeLists.txt` sets `FTIMER_PACKAGE_VERSION_COMPATIBILITY` to
  `SameMajorVersion` for the 1.x package line.
- The normal release artifact policy remains source archive plus release notes
  plus the root [`LICENSE`](../LICENSE). No binary package, generated install
  tree, compiler module bundle, benchmark CSV, generated report, Spack recipe,
  or EasyBuild easyconfig is part of the v1.0.0 GitHub release artifact set.
- The CMake install path installs documentation under `share/doc/fTimer/`,
  including `installed-api.md` and `LICENSE`. The installed-consumer smoke path
  and release evidence cover that artifact contract.

## Benchmark Closeout

The local benchmark command in this record is a release-readiness smoke and
review-evidence command. This PR does not commit generated benchmark CSV output
and the v1.0.0 release-notes draft makes no benchmark trend or absolute
overhead claim. Any later benchmark observation in release notes must include
the benchmark CSV and the sidecar/provenance fields required by
[`docs/release.md`](release.md).

## Post-Release Triage Expectations

After publication, label confirmed release regressions with `post-release`.
Use `release-blocker` only when an issue blocks the next release or patch.
Security-sensitive reports follow [`SECURITY.md`](../SECURITY.md), not public
issue triage. Keep release-note corrections factual and timestamped if they
materially change user guidance.
