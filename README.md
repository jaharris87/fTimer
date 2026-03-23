# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

**Under construction.** Phase 0 provides a buildable placeholder library, examples, packaging, and smoke-test scaffolding. Behavioral implementation is tracked in [TODO.md](TODO.md).

## Overview

fTimer provides stack-based hierarchical timing with:

- Context-sensitive accounting (same timer name tracked independently under different parents)
- Configurable mismatch handling (strict / warn / repair)
- Structured summary data (`get_summary()`) and formatted text reports (`print_summary()`)
- Exclusive/self time alongside inclusive time
- Optional MPI cross-rank statistics (min/max/avg/imbalance)
- Callback hooks for external profiling tools (PAPI, likwid, etc.)
- Injectable clock for deterministic testing

## Build

```bash
# Serial placeholder build
cmake -B build && cmake --build build

# Run Phase 0 smoke test
ctest --test-dir build --output-on-failure

# MPI placeholder build
cmake -B build -DFTIMER_USE_MPI=ON && cmake --build build

# Enable pFUnit tests later, once they exist
cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit && cmake --build build

# Or use the Makefile wrapper
make        # serial build
make mpi    # MPI build
make test   # build + test
```

Requires: gfortran (or compatible Fortran compiler) and CMake >= 3.16.

Phase 0 defaults:

- CMake is the only supported build path right now.
- Smoke tests are enabled by default and are intentionally minimal.
- pFUnit-backed behavioral tests are not part of the default build yet.
- FPM support is deferred until the public API stabilizes.

## Workflow Bootstrap

Codex review automation expects the following repository setup:

- Labels: `codex-software-review`, `codex-methodology-review`, `codex-red-team-review`
- Secret: `CODEX_TRIGGER_PAT` containing a fine-grained PAT with `pull-requests:write`
- PR-based flow on `main`, with CI and lint required before merge

Recommended GitHub ruleset for `main`:

- require pull requests before merge
- require `CI / build-serial`, `CI / build-mpi`, and `CI / lint`
- block direct pushes and force pushes
- require conversation resolution before merge

The review-trigger workflow posts `@codex review` comments when those labels are applied to a PR. The label bootstrap is documented in-repo; there is no `scripts/create-labels.sh` script in this project.

Phase workflow for development:

- create or link the relevant GitHub issue first
- work on a feature branch
- open a PR to `main`
- apply the Codex review labels required by the diff

## Deferred Items

These are intentionally postponed beyond Phase 0:

- pFUnit behavioral test suite
- FPM manifest/support
- secondary repo hygiene such as Dependabot, `.editorconfig`, and broader governance files

## License

BSD-3-Clause. See [LICENSE](LICENSE).
