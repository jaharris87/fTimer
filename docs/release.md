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
- Keep the release claim within the documented support boundary: serial timing,
  pure-MPI timing, the narrow master-thread-only OpenMP carve-out, and the
  CMake package path.
- Do not promote deferred non-goals into the release unless a linked issue has
  changed scope. Current non-goals include broad hybrid OpenMP timing, full
  profiler integration, FPM packaging, hardware counters, traces, accelerator
  timelines, automatic MPI barriers, and stable callback semantic identity.

## Version And Compatibility

- Update the project version in `CMakeLists.txt`.
- Confirm the pre-1.0 CMake package compatibility rule is still accurate in
  `README.md` and `docs/installed-api.md`.
- If a stable source-level symbol, installed module artifact, CSV schema field,
  or package compatibility boundary changes, update the relevant docs and
  smoke/contract checks in the same release-prep PR.
- Treat release notes as part of the compatibility contract: describe
  user-visible behavior changes, limitations, and migration notes directly.

## Validation Matrix

Run the strongest available local validation before opening a release-prep PR,
then require GitHub CI to pass before tagging.

| Area | Required before tag |
| --- | --- |
| Smoke/install path | Yes |
| Serial pFUnit path | Yes when pFUnit is available |
| MPI path | Yes when MPI and matching pFUnit are available |
| OpenMP carve-out | Yes when OpenMP and matching pFUnit are available |
| Bench harness | Yes for hot-path or summary-performance changes |
| Formatting | Yes for source/test/example changes |
| Diff hygiene | Yes |
| CI | Yes |

Use the commands from `AGENTS.md` and `README.md` for each build mode. Minimum
release-prep evidence should include the exact commands run, the local toolchain
used, and whether the corresponding required CI jobs passed. Include
`git diff --check` in every release-prep PR. Include the benchmark harness when
hot-path timing behavior or summary-generation performance changed.

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

FC=mpifort cmake -B build-mpi \
  -DFTIMER_USE_MPI=ON \
  -DFTIMER_BUILD_TESTS=ON \
  -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-mpi
cmake -E chdir build-mpi ctest --output-on-failure -L mpi

FC=gfortran cmake -B build-openmp \
  -DFTIMER_USE_OPENMP=ON \
  -DFTIMER_BUILD_TESTS=ON \
  -DPFUNIT_DIR=/path/to/pfunit
cmake --build build-openmp
cmake -E chdir build-openmp ctest --output-on-failure

cmake -S . -B build-bench \
  -DFTIMER_BUILD_BENCH=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-bench --target ftimer_bench
./build-bench/bench/ftimer_bench

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
