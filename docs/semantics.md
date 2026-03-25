> **When to read this**
>
> Read this file when runtime behavior is changing, ambiguous, under review, or needs exact contract-level interpretation.
>
> This is the canonical detailed runtime-contract reference for behavior on `main`.
>
> Do **not** load this by default for routine implementation tasks that are purely local refactors, build-system changes, or non-behavioral cleanup.

# fTimer Semantics Reference

This document defines the current runtime contract on `main`.

Current `main` implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and Phase 6 OpenMP guard behavior.

For the user-facing project overview, build entry points, and examples, see `README.md`.
For forward-looking design intent, see `docs/design.md`.

When these documents differ, current behavior on `main` is defined by:

1. the implementation under `src/`
2. the behavioral tests
3. this document

## Timing Model

- Wall-clock timing only
- No CPU-time accounting
- No hardware-counter accounting in the core library
- Injected clocks are expected to be monotonic within a timing run

## Nesting Rules

- Timers are stack-based.
- Overlapping sibling timers are not supported.
- The same timer name may appear under different parent stacks and is tracked independently by context.

## Start / Stop Semantics

### Start

A `start("name")` operation conceptually:

1. resolves or creates the timer segment for `"name"`
2. resolves or creates the current parent context
3. pushes the timer onto the active call stack
4. records the start timestamp

### Stop

A `stop("name")` operation conceptually:

1. verifies that the active stack top matches the timer being stopped
2. pops the timer from the active call stack
3. resolves the timer's parent context using the now-current stack
4. accumulates elapsed time and increments call count

The stack state changes between `start` and `stop`.
Correct context attribution therefore depends on using the post-pop parent stack during stop handling.

## Inclusive and Self Time

For each summary entry:

- `inclusive_time` is the total accumulated time spent in that timer context
- `self_time` is `inclusive_time - sum(direct children inclusive_time)`

Only direct children contribute to self-time subtraction.
Iterating past direct children into cousins or deeper descendants is a correctness bug.

## Mismatch Handling

Mismatch handling is configurable:

- `strict` — error, no repair
- `warn` — diagnostic plus iterative repair
- `repair` — silent iterative repair for compatibility-oriented behavior

### Repair Contract

Mismatch repair uses this logical model:

1. capture one timestamp
2. unwind active timers above the requested stop target
3. stop the target timer
4. restart unwound timers in reverse order

Important constraints:

- the repair sequence must use a single captured timestamp consistently
- internal repair transitions must not fire user callbacks

## Error Contract

All public routines use the same general contract for `ierr`.

- When `ierr` is present:
  - set the error code
  - do not emit stderr diagnostics for that condition
- When `ierr` is absent:
  - emit the appropriate warning/diagnostic to stderr
  - continue according to the routine's contract

## Reset Behavior

`reset`:

- zeros times and call counts
- preserves timer definitions
- restarts the local monitoring window used for `summary%total_time` and `% Total`
- errors if timers are still active

## Timer Name Policy

Public timer creation / lookup paths:

- right-trim trailing blanks
- reject empty names
- reject names longer than `FTIMER_NAME_LEN`
- reject names that begin with a blank
- reject ASCII control characters

## Formatted Summary Text Policy

Formatted summary output does not emit unsafe raw entry names literally.

Escaped forms are stable:

- leading blanks render as `\x20`
- backslashes render as `\\`
- tabs render as `\t`
- newlines render as `\n`
- carriage returns render as `\r`
- other ASCII control characters render as `\xNN`
- blank / empty raw names render as `<blank>`

## Summary Contract

### Local Summary

`get_summary()` returns a local structured summary.

`print_summary()` and `write_summary()` format local summary information only.

### Local Fields

Even after a successful MPI reduction call, the following fields remain local to the calling rank:

- `start_date`
- `end_date`
- `total_time`
- per-entry `inclusive_time`
- per-entry `self_time`
- per-entry `call_count`
- per-entry `avg_time`
- per-entry `pct_time`

## Callback Contract

`on_event` is for normal timer transitions only.

- normal `start` fires callback
- normal `stop` fires callback
- internal repair transitions do **not** fire callback

`user_data` remains an opaque `c_ptr` for external state.

## MPI Contract

### Availability

`mpi_summary()` is available only when built with `FTIMER_USE_MPI=ON`.

When MPI support is not enabled:

- `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED`
- the summary remains local-only

### Communicator Contract

`mpi_summary()` is collective over the communicator captured by `init`.

- omitting `comm` at `init` means `MPI_COMM_WORLD` is used
- all participating ranks in that communicator must enter `mpi_summary()` with fully stopped timers

### Consistency Preflight

Before reduction, the implementation must verify that ranks agree on canonical timer descriptors.

Descriptor mismatches such as:

- extra timers
- missing timers
- renamed timers
- hierarchy mismatches
- context mismatches

must not proceed into a misleading reduction.
They must instead fall back to a local-only result with `FTIMER_ERR_MPI_INCON`.

### Reduced MPI Fields

The only cross-rank reduced entry fields are:

- `min_time`
- `max_time`
- `avg_across_ranks`
- `imbalance`

These reduced MPI fields are valid only when the summary shape indicates they are valid on that rank.

### MPI Summary Shape

`summary%mpi_summary_state` makes the result shape explicit:

- `FTIMER_MPI_SUMMARY_LOCAL_ONLY`
  - plain local summary
  - also used when MPI is disabled or fallback is required
- `FTIMER_MPI_SUMMARY_ROOT_LOCAL_PLUS_REDUCED`
  - successful root result
  - local fields remain root-local
  - reduced MPI entry fields are populated
- `FTIMER_MPI_SUMMARY_NONROOT_LOCAL_AFTER_REDUCE`
  - successful non-root result
  - local fields remain local to that non-root rank
  - reduced MPI entry fields are not populated there

`summary%has_mpi_data` means reduced MPI entry fields are valid on that rank.
It does **not** mean the entire summary became a globally reduced copy.

### Unsupported MPI Misuse

Mismatched communicator choices across would-be participants are unsupported.
This API does not attempt unsafe cross-communicator rendezvous to detect that misuse.

## OpenMP Contract

### Availability

OpenMP guard behavior exists only when the library is built with `FTIMER_USE_OPENMP=ON`.

### Current Model

The current model is limited master-thread-only timing.

This phase does **not** make `fTimer` generally thread-safe and does **not** provide thread-local timer instances.

### Guard Behavior Inside Parallel Regions

Inside OpenMP parallel regions:

- guarded core timer operations run only on the master thread
- non-master calls become silent no-ops
- suppressed non-master calls do not mutate shared timer state
- suppressed non-master calls emit no stderr warning
- suppressed non-master calls leave any caller-provided `ierr` unchanged
- worker-thread-only timer calls produce no summary entry

### Consequences For Timing Data

The silent worker-thread no-op model has important observable consequences:

- timer calls made only on worker threads are dropped from the summary
- call counts reflect only master-thread invocations
- timing inside a parallel region captures only the master-thread timing window
- worker-thread duration is not separately aggregated into inclusive or self time

### Supported Pattern

To time a parallel region as a whole, place `start` / `stop` outside the `!$omp parallel` block.

### Unsupported / Misleading Pattern

Placing `start` / `stop` inside a parallel region with the expectation that all threads contribute timing data is not supported.
Only the master thread contributes under the current contract.

## Procedural / OOP Surface Consistency

The procedural wrappers are intended to be thin forwarding calls over the OOP core.

Unless a task explicitly changes the public contract, procedural and OOP behavior should remain aligned for:

- timer lifecycle behavior
- timing accumulation
- error handling
- summary generation
- MPI summary behavior
- OpenMP guard behavior

## Current Build-Surface Notes

- CMake is the supported build system on current `main`
- smoke tests are the default baseline
- behavioral tests are opt-in
- FPM support is intentionally deferred