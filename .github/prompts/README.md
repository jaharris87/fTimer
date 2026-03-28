# Native Review Prompts

This directory contains the condensed one-line prompts used by the native
label-triggered Codex PR workflow.

- Each file in this directory must remain a single line with no embedded newline.
- The trigger workflow reads these prompt files from the PR base revision, not
  from PR-controlled content.
- `.github/codex-review-roles.json` is the authoritative machine-readable
  catalog for label names, prompt files, prompt versions, and automatic-routing
  rules.
- The long-form fallback library lives in `.github/prompts/detailed/README.md`.

## Native Prompt Contract

The condensed native prompts should still inject distinct repo-specific checks.

### `software-review.md`

Must bias toward correctness in the changed implementation and changed tests:

- behavior regressions
- procedural wrapper versus OOP parity drift
- install/export or end-to-end consumer breakage
- user-visible summary/output regressions
- docs/tests drift when runtime behavior changes

### `methodology-review.md`

Must inject the timing invariants that are easy to miss but expensive to get wrong:

- `stop` pops the call stack before context lookup
- mismatch repair uses a single timestamp
- repair does not fire user callbacks
- self-time subtracts only direct children
- timing arithmetic stays in `real(wp)`
- MPI/OpenMP semantics stay honest

### `red-team-review.md`

Must look for ways the code can appear correct while silently lying:

- silent context misattribution
- repair logic that double-counts or leaks callbacks
- misleading but plausible summaries
- worker-thread no-op confusion
- MPI mismatch/fallback failures
- weak evidence that would let a wrong implementation pass review

### `test-quality-review.md`

Must focus on whether the tests would actually catch the likely broken implementation:

- broken start/stop ordering
- repair timestamp drift
- callback suppression regressions
- self-time sibling/cousin boundary bugs
- error-contract mistakes
- MPI mismatch handling gaps
- worker-thread no-op gaps

## Calibration Examples

These are representative examples of how the native roles should stay distinct.

### Core runtime PR

Example diff shape:

- `src/ftimer_core.F90`
- `tests/test_basic.pf`

Expected separation:

- software: correctness regressions, wrapper parity, missing user-facing validation
- methodology: stack/context/timestamp/callback/self-time invariants
- red-team: silent wrong-answer cases and misleading-but-plausible summaries
- test-quality: whether the mock-clock tests would fail for the broken implementation

### Workflow/docs PR

Example diff shape:

- `.github/workflows/codex-review.yml`
- `docs/workflows/review-monitoring.md`

Expected separation:

- software: behavior bugs in the workflow itself
- docs-contract: process/docs drift
- red-team only if the workflow could silently report coverage or safety it does not really provide

### Build/package PR

Example diff shape:

- `CMakeLists.txt`
- `tests/install-consumer/`

Expected separation:

- build-portability: compiler/config/package correctness
- software: end-to-end behavior regressions for consumers
- api-compat when public install/export surfaces change
