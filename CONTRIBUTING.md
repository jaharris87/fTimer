# Contributing To fTimer

Thanks for helping make fTimer more reliable. This project is currently focused
on a small, auditable wall-clock timing library for serial, pure-MPI,
OpenMP-compatibility, and explicit `ftimer_openmp_t` level-1 worker/hybrid
Fortran timing paths.

## Before Opening Work

- Use the bug report template for reproducible failures.
- Use the feature request template for bounded improvements.
- Use the strategic question template when the next step is a product, API, or
  scope decision rather than implementation.
- Do not file security-sensitive details in a public issue. Follow
  `SECURITY.md`.
- Check for existing issues before opening duplicates, especially for deferred
  topics such as FPM packaging, broader OpenMP support beyond the explicit
  level-1 worker runtime, hardware counters, traces, accelerator timelines, and
  profiler-backend integration.

## Development Setup

Use a separate build directory for each compiler and feature mode. Reconfiguring
one CMake tree across compilers is not a supported workflow.

The default local smoke path is:

```bash
cmake -B build-smoke
cmake --build build-smoke
cmake -E chdir build-smoke ctest --output-on-failure
```

Behavioral tests require pFUnit and a matching compiler/toolchain:

```bash
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
cmake --build build
cmake -E chdir build ctest --output-on-failure
```

MPI and OpenMP validation commands are listed in `AGENTS.md`, `README.md`, and
`docs/release.md`.

## Pull Requests

For normal changes:

- Link the relevant GitHub issue.
- Keep the diff scoped to that issue.
- Update docs when behavior, support boundaries, packaging, or workflow changes.
- Add or update tests when behavior changes.
- Run `git diff --check` before opening the PR.
- Record any unavailable local validation with a reason.

For intentional public-surface changes, first use the public-surface change map
in [`docs/installed-api.md`](docs/installed-api.md). This applies to stable or
unstable source imports, installed `.mod` artifacts, package-version behavior,
text report fields, CSV schemas, supported examples, installed consumers,
release evidence, or CI proof paths. It is not required for private
implementation-only edits.

Repository PR handling, review labels, fallback review, and findings disposition
are documented in `docs/maintainer.md` and `docs/workflows/`.

## Coding And Documentation Expectations

- Prefer correctness and explicit error handling over silent fallbacks.
- Preserve deterministic tests by using the injectable mock clock instead of
  sleeps or wall-clock timing assumptions.
- Keep public API and installed-package docs aligned with implementation.
- Keep release-scope docs honest about what current `main` supports and what is
  deferred.
- Use BSD-3-Clause-compatible contributions only. If you need to include copied
  or generated third-party material, document the license basis in the PR.

## Contributor Intake

Maintainers triage incoming issues roughly as:

- `bug`: reproducible defects or regressions.
- `enhancement` / `improvement-issue`: bounded improvements.
- `question` / `strategic-question`: decisions needed before implementation.
- `release-blocker`: must be resolved before the next release claim.
- `post-release`: regression or follow-up found after a release.

Small, well-scoped PRs with clear validation are easiest to review and merge.
