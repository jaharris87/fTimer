# Release Checklist

This checklist keeps fTimer releases lightweight, auditable, and aligned with
the current product scope. It is written for human maintainers. Coding agents
may prepare evidence, PRs, and status updates, but a human maintainer owns the
final release decision, tag, and GitHub release.

## Release Scope

Before starting a release candidate:

- Confirm all release-blocking issues are closed or explicitly deferred with a
  maintainer decision.
- Confirm the release umbrella, if any, reflects the current state of child
  issues and ready PRs.
- Review open `release-blocker`, `release-audit`, `bug`, and `post-release`
  issues for items that should affect the release notes or block the tag.
- Review the compact claim-evidence ledger in
  [`docs/release-evidence.md`](release-evidence.md) and update any rows whose
  CI jobs, tests, examples, caveats, or support status changed since the last
  release.
- Keep the release claim within the documented support boundary: serial timing,
  pure-MPI timing, the narrow master-thread-only OpenMP carve-out, the
  `ftimer_openmp` lifecycle/configuration/timer-catalog and id-first
  serial-lane/level-1 worker timing surface with local OpenMP summaries,
  reports, CSV, strict MPI+OpenMP hybrid summaries/reports/CSV, sparse union
  MPI+OpenMP hybrid participation summaries/reports/CSV, and the CMake package
  path.
- Keep release notes and support claims aligned with the public operational
  support matrix in `README.md`. In particular, MPI+OpenMP has CI evidence for
  OpenMPI wrapper builds with GNU Fortran and OpenMP, plus focused local MPICH
  wrapper smoke/install-consumer evidence recorded in
  [`docs/release-evidence.md`](release-evidence.md). Other MPI/compiler/OpenMP
  runtime combinations remain plausible but unvalidated until a release issue
  adds matching evidence.
- Do not promote deferred non-goals into the release unless a linked issue has
  changed scope. Current non-goals include full profiler integration, FPM
  packaging, hardware counters, traces, accelerator timelines, automatic MPI
  barriers, and stable callback semantic identity.

## Version And Compatibility

- Update the project version in `CMakeLists.txt`.
- Confirm the pre-1.0 CMake package compatibility rule is still accurate in
  `README.md` and `docs/installed-api.md`.
- If a stable source-level symbol, installed module artifact, text report field,
  CSV schema field, or package compatibility boundary changes, update the
  relevant docs and smoke/contract checks in the same release-prep PR. Use the
  public-surface change map in [`docs/installed-api.md`](installed-api.md) to
  keep source, docs, examples, installed consumers, release evidence, and CI
  proof paths aligned without applying that checklist to private
  implementation-only edits.
- Treat installed Fortran `.mod` artifacts as compiler/toolchain/mode-specific
  outputs. Do not imply that one installed prefix can be reused across
  different compilers, MPI wrappers, or feature modes unless release validation
  explicitly proves that combination.
- Treat release notes as part of the compatibility contract: describe
  user-visible behavior changes, limitations, and migration notes directly.
- For the first release containing the true OpenMP and hybrid APIs, name
  `examples/openmp_example.F90`, `examples/openmp_worker_example.F90`, and
  `examples/mpi_openmp_example.F90`; state that serial, pure-MPI, and
  compatibility users need no source changes; include the validation matrix;
  and keep the remaining non-goals explicit.

## Validation Matrix

Run the strongest available local validation before opening a release-prep PR,
then require GitHub CI to pass before tagging.

| Area | Required before tag |
| --- | --- |
| Smoke/install path | Yes |
| Serial pFUnit path | Yes when pFUnit is available |
| MPI path | Yes when MPI and matching pFUnit are available |
| MPI+OpenMP compatibility and hybrid paths | Yes when validating the hybrid compatibility matrix; this proves current feature-flag coexistence, `examples/mpi_openmp_example.F90`, the installed `ftimer_openmp` worker API, and strict plus sparse union hybrid rank/lane summaries/reports/CSV |
| OpenMP carve-out and true worker example | Yes: GNU pFUnit guard coverage when OpenMP and matching pFUnit are available; LLVM Flang smoke/example coverage for `examples/openmp_example.F90` and `examples/openmp_worker_example.F90` when validating the OpenMP compiler matrix |
| Bench harness | Yes for hot-path, summary, report/CSV, MPI summary/report, or release-readiness performance evidence |
| Formatting | Yes for source/test/example changes |
| Diff hygiene | Yes |
| CI | Yes |

Use the commands from `AGENTS.md` and `README.md` for each build mode. Minimum
release-prep evidence should include the exact commands run, the local toolchain
used, and whether the corresponding required CI jobs passed. Include
`git diff --check` in every release-prep PR. Include the benchmark harness when
hot-path timing behavior, lookup/cached-id behavior, context growth or
parent-stack accounting, summary generation, report/CSV formatting, or MPI
summary/report behavior changed.

Benchmark CSVs are review evidence, not a CI pass/fail threshold. Start trend
review with the rows for flat name-based start/stop, cached-id start/stop,
lookup scaling across resident timer counts, context scaling across parent-stack
counts, timer/context first-touch allocation and growth, summary builds, local
text/CSV reports, sparse MPI-union formatting, and the strict MPI CSV row when
MPI is enabled. For OpenMP hot-path work, also review the feature-enabled
benchmark rows for `ftimer_openmp_t` serial-lane ids, timed-region open/close,
worker-lane ids, worker context scaling, OpenMP catalog register/lookup,
concurrent and split-object worker lanes, participating-lane first touch, and
local OpenMP summary merge. For MPI+OpenMP work, include the strict and sparse
union MPI+OpenMP CSV report rows. Treat absolute timings from GitHub-hosted
runners cautiously; runner load and placement are noisy. The serial
`build-bench` CI job uploads the validated CSV as a
`ftimer-bench-serial-<sha>` artifact for PR and release review. The OpenMP and
MPI+OpenMP benchmark CI jobs currently build `ftimer_bench` and run CSV smoke
checks, but durable CSV artifact upload for those feature-enabled benchmark
jobs is intentionally deferred; run the feature-enabled harness locally when
trend evidence beyond smoke coverage is needed.

### Benchmark Provenance And Feature-Mode Evidence

Benchmark result CSVs record numeric observations only: scenario label,
repetition count, total milliseconds, and per-operation nanoseconds. Treat the
provenance for a benchmark run as a sidecar record kept beside the CSV in PR or
release evidence, not as extra benchmark rows and not as release-note prose
alone. A sidecar avoids repeating identical metadata on every result row,
preserves the simple benchmark CSV shape used by smoke checks, and makes clear
that provenance describes one run of noisy wall-clock observations.

A useful benchmark sidecar should include enough context for a maintainer to
decide whether two CSVs are comparable:

- fTimer commit SHA and benchmark CSV artifact name or path;
- benchmark mode: serial, OpenMP, MPI, or MPI+OpenMP;
- `FTIMER_USE_MPI`, `FTIMER_USE_OPENMP`, `FTIMER_BUILD_BENCH`,
  `CMAKE_BUILD_TYPE`, Fortran compiler path/version, and relevant Fortran
  compile/link flags;
- MPI launcher, requested rank count, and oversubscription-relevant launcher
  flags when MPI is enabled;
- OpenMP runtime shape when OpenMP is enabled, including requested thread count
  or the environment variables that determine it;
- runner or host identity, operating system/kernel, architecture, and any
  available CPU allocation detail;
- clock context: benchmark measurement uses the real wall clock through
  `system_clock`; when MPI is enabled, also record that the fTimer backend
  clock under test for `ftimer_t` paths is `MPI_Wtime()`;
- run shape, including repeated-sample count, whether samples were sequential
  or concurrent, and any known local load caveat.

Release notes may summarize benchmark observations only after the corresponding
CSV and sidecar are available in the PR or release evidence. The release note
summary should cite trends or risk checks, not absolute overhead promises.

For feature-enabled benchmark evidence, keep CI artifact upload limited to the
serial benchmark CSV until a future issue adds sidecar-aware artifact handling
for additional modes. OpenMP and MPI+OpenMP benchmark CI jobs remain
smoke-oriented: they prove that the harness builds and that feature-mode CSV
rows are parseable, but their CSVs are not retained as durable CI artifacts.
When OpenMP, MPI, or MPI+OpenMP performance-risk work needs trend evidence,
run the feature-enabled benchmark harness locally and attach the CSV plus
sidecar to the PR or release evidence. Do not turn those observations into CI
thresholds or universal overhead claims.

Reference commands:

```bash
cmake -B build-smoke
cmake --build build-smoke
cmake -E chdir build-smoke ctest --output-on-failure

FC=gfortran cmake -B build \
  -DFTIMER_BUILD_TESTS=ON \
  -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
cmake -E chdir build ctest --output-on-failure

FC=/path/to/mpi-mpifort cmake -B build-mpi \
  -DFTIMER_USE_MPI=ON \
  -DFTIMER_BUILD_TESTS=ON \
  -DPFUNIT_DIR=/path/to/mpi-pfunit \
  -DMPIEXEC_EXECUTABLE=/path/to/mpi-mpiexec
cmake --build build-mpi
cmake -E chdir build-mpi ctest --output-on-failure -L mpi

FC=mpifort cmake -B build-mpi-openmp \
  -DFTIMER_USE_MPI=ON \
  -DFTIMER_USE_OPENMP=ON
cmake --build build-mpi-openmp
cmake -E chdir build-mpi-openmp ctest --output-on-failure
cmake -E chdir build-mpi-openmp ctest --output-on-failure \
  --no-tests=error -R '^(ftimer_mpi_openmp_example_smoke|ftimer_installed_package_consumer_mpi_openmp)$'

FC=gfortran cmake -B build-openmp \
  -DFTIMER_USE_OPENMP=ON \
  -DFTIMER_BUILD_TESTS=ON \
  -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
cmake -E chdir build-openmp ctest --output-on-failure

FC=flang-19 cmake -B build-openmp-flang \
  -DFTIMER_USE_OPENMP=ON \
  -DFTIMER_BUILD_TESTS=OFF
cmake --build build-openmp-flang
cmake -E chdir build-openmp-flang ctest --output-on-failure \
  -R '^(ftimer_openmp_example_smoke|ftimer_openmp_worker_example_smoke|ftimer_installed_package_consumer_openmp_flang)$'

Add `-DOpenMP_ROOT=/path/to/libomp` on LLVM Flang platforms where CMake does
not discover the OpenMP runtime automatically.

cmake -S . -B build-bench \
  -DFTIMER_BUILD_BENCH=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench
./build-bench/bench/ftimer_bench /tmp/ftimer_bench_results.csv

git diff --check
```

If a toolchain is unavailable locally, record the skip reason in the release-prep
PR and rely on the corresponding required CI job before tagging.

For a clean benchmark reconfigure, remove or use a separate `build-bench/`
directory first. With CMake 3.24 or newer, `cmake --fresh` may be added to the
benchmark configure command as a convenience for a clean reconfigure.

## Artifact Policy

A normal fTimer GitHub release publishes:

- the signed or annotated Git tag,
- the GitHub release notes,
- GitHub-generated source archives that include the source tree's `LICENSE`.

The released source must continue to produce these install-tree outputs through
the documented CMake install path:

- installable CMake package config/version files,
- compiler module artifacts needed by the supported installed package contract,
- installed documentation under `share/doc/fTimer/`, including
  `installed-api.md` and `LICENSE`.

Do not attach binary packages, generated install trees, compiler module bundles,
benchmark data, or generated reports to a GitHub release unless a release issue
explicitly adds that artifact type and records how it was built, validated, and
licensed.

CI benchmark CSV artifacts are short-lived PR/release review evidence. Do not
commit generated benchmark CSV output to the repository or promote it to a
GitHub release asset without an explicit release issue.

## License Expectations

- fTimer is distributed under BSD-3-Clause. The root `LICENSE` is the source of
  truth for the license text.
- New source, test, script, documentation, and workflow files contributed to the
  repository are expected to be compatible with BSD-3-Clause distribution.
- Third-party snippets, generated files, vendored code, or copied examples need
  a documented license basis before they can be included in a release.
- The install/package smoke path must continue to install the license artifact
  that downstream consumers receive.

## Release Notes

Release notes should be short and evidence-backed. Include:

- the version and tag,
- the intended audience and supported workflows,
- supported examples: serial basics, pure MPI, OpenMP compatibility,
  true OpenMP worker timing, and strict/sparse MPI+OpenMP hybrid timing,
- user-visible API, packaging, CSV, MPI, OpenMP, or behavior changes,
- compatibility and migration notes,
- known limitations and deferred work,
- validation summary and any toolchain skips,
- links to important issues and PRs.

Do not claim production readiness, broad compiler support, general hybrid
OpenMP timing, profiler-backend integration, or binary package availability
unless the release validation and docs support that exact claim.

## Tag And Publish

After the release-prep PR has merged and `main` is current:

1. Verify the local checkout is clean and current with `origin/main`.
2. Confirm required CI passed on the merge commit.
3. Create an annotated tag, for example `git tag -a v0.2.0 -m "fTimer 0.2.0"`.
4. Push the tag with `git push origin v0.2.0`.
5. Create the GitHub release from that tag using the prepared release notes.
6. Check the published release page, source archive links, and displayed license.

If a serious release mistake is found after publication, prefer a documented
patch release over silently rewriting a public tag.

## Post-Release Triage

After publishing:

- Watch new bug reports and support requests for release regressions.
- Route security-sensitive contact requests through `SECURITY.md`.
- Label confirmed release regressions with `post-release`; add
  `release-blocker` only when the issue blocks the next release or patch.
- Update the release umbrella or milestone with any deferred follow-up state.
- If a vulnerability is reported, follow `SECURITY.md` instead of public issue
  triage.
- Keep release-note corrections factual and timestamped when they materially
  change user guidance.
