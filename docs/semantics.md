> **When to read this:** When runtime behavior or contract is changing or unclear. This is the primary current runtime contract document on `main`. Do not load this by default for routine coding tasks where the behavior is not in question.

# fTimer Semantics Reference

This document describes the current runtime contract on `main`.

Current `main` implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and the Phase 6 OpenMP guard behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `mpi_summary()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, root-side MPI min/max/avg/imbalance fields, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with a local-only summary.

Current architecture, validation, and workflow notes belong in `docs/design.md`. Historical phase-roadmap notes belong in `docs/implementation-history.md`. When current-state sources disagree, use this repository-wide precedence order: current code under `src/`, then current behavioral tests, then `docs/semantics.md`, then `README.md`, then `docs/design.md`.

## Timing Model

- Inclusive vs exclusive (self) time definitions
- Wall-clock only (no CPU time, no hardware counters)
- Injected clocks are expected to be monotonic within a timing run

## Nesting Rules

- Strict stack-based nesting (no overlapping timers)
- Context-sensitive accounting: same timer name under different parents

## Mismatch Handling

- Strict mode (default): error, no repair
- Warn mode: diagnostic + iterative repair
- Repair mode: silent iterative repair (Flash-X compatibility)
- Repair algorithm: single timestamp, unwind, stop target, restart unwound in reverse

## Error Contract

- `ierr` present: set code, no stderr
- `ierr` absent: warn to stderr, continue
- Error codes and their meanings

## Timer Name / Summary Text Policy

- Public timer creation/lookup paths right-trim trailing blanks, reject empty names, reject names longer than `FTIMER_NAME_LEN`, reject names that begin with a blank, and reject ASCII control characters
- Formatted summary output does not emit unsafe raw summary-entry names literally
- Escaped formatted-summary forms are stable: leading blanks render as `\x20`, backslashes render as `\\`, tab/newline/carriage return render as `\t`/`\n`/`\r`, other ASCII control characters render as `\xNN`, and blank/empty raw names render as `<blank>`

## Reset Behavior

- Zeros times and counts, preserves timer definitions
- Restarts the local monitoring window used for `summary%total_time` and `% Total`
- Error if timers are active

## MPI Guarantees

- `mpi_summary()` is collective over the communicator captured by `init`
- Omitting `comm` at `init` means `mpi_summary()` uses `MPI_COMM_WORLD`
- All ranks in that communicator must enter `mpi_summary()` with fully stopped timers
- Integer comm handle compatibility (`mpif.h` and `mpi_f08`)
- Hash-based timer-descriptor preflight before the reduction phase
- Extra timers, missing timers, renamed timers, and hierarchy/context mismatches fall back to the local-only summary with `FTIMER_ERR_MPI_INCON`
- Min/max/avg/imbalance fields are valid only on communicator root when `has_mpi_data=.true.`
- Mismatched communicator choices across would-be participants are unsupported; this API has no safe cross-communicator rendezvous to detect that misuse without risking the same MPI deadlock it is trying to avoid

### Unsupported communicator mismatch example

Suppose ranks 0-1 initialize a timer with one communicator split and later call `mpi_summary()`, while ranks 2-3 reach `mpi_summary()` through a different communicator choice. That is unsupported misuse.

This is not like descriptor inconsistency within one communicator, where every participant can still enter the same collective and the library can fall back locally after a preflight mismatch. Once ranks have already diverged onto different communicators, `mpi_summary()` has no safe second rendezvous it can use to discover the mistake without risking the same deadlock it is trying to avoid. The practical failure mode is a hang, not `FTIMER_ERR_MPI_INCON`.

The supported pattern is simple: capture one communicator consistently at `init`, then have that same participant set enter `mpi_summary()` together.

## MPI Summary Contract

`mpi_summary()` does not return a fully reduced cross-rank copy of every summary field.

- `start_date`, `end_date`, `total_time`, and each entry's `inclusive_time`, `self_time`, `call_count`, `avg_time`, and `pct_time` always describe the calling rank's local summary data, even after a successful `mpi_summary()`.
- `min_time`, `max_time`, `avg_across_ranks`, and `imbalance` are the only cross-rank reduced entry fields.
- Those reduced MPI entry fields are valid only when `summary%has_mpi_data` is `.true.`.
- `summary%has_mpi_data` means only that the reduced MPI entry fields are valid on this rank. It does not mean every field in the summary is globally meaningful, and it does not mean non-root ranks receive reduced entry fields.
- `summary%mpi_summary_state` makes the result shape explicit:
- `FTIMER_MPI_SUMMARY_LOCAL_ONLY`: plain local summary. This is what `get_summary()` returns, and it is also what `mpi_summary()` leaves behind when MPI support is disabled, timers are still active, descriptor hashes disagree across ranks, or another MPI-side failure forces fallback.
- `FTIMER_MPI_SUMMARY_ROOT_LOCAL_PLUS_REDUCED`: successful `mpi_summary()` result on rank 0. Local summary fields remain root-local; reduced MPI entry fields are populated and `has_mpi_data` is `.true.`.
- `FTIMER_MPI_SUMMARY_NONROOT_LOCAL_AFTER_REDUCE`: successful `mpi_summary()` result on non-root ranks. Local summary fields still describe that non-root rank only; reduced MPI entry fields remain unset and `has_mpi_data` is `.false.`.

## Name Validation Error Contract

Name validation failures return `FTIMER_ERR_INVALID_NAME` (code 8).

**Deliberate warn-and-skip contract for `ierr`-absent callers** (issue #49, PR #43):

When a caller omits `ierr` and passes an invalid timer name, the runtime:
1. emits a diagnostic to stderr
2. returns immediately without modifying any timer state

The call is a no-op: no segment is created, no stack depth change occurs.
Parent timers are not affected. Summary output will simply omit the rejected child;
it does not produce a plausible-but-wrong child entry.

**OpenMP carve-out**: this warn-and-skip contract applies in serial code and from the
OpenMP master thread only. When built with `FTIMER_USE_OPENMP=ON`, calls from non-master
threads are suppressed before validation reaches `normalize_name` or `report_status` — they
produce no stderr diagnostic, return 0 (for `lookup`), and leave any caller-provided `ierr`
unchanged. This is a consequence of the master-thread-only guard model documented in
"OpenMP Limitations" below.

This is the deliberate policy rather than a stronger failure (e.g. `error stop`),
chosen for consistency with the library's error contract and because callers that
omit `ierr` have opted into the permissive path. Callers that require hard
enforcement should pass `ierr` and check it.

## OpenMP Limitations

- OpenMP guard behavior is enabled only when the library is built with `FTIMER_USE_OPENMP=ON`
- The implemented model is master-thread-only timing; this phase does not make `fTimer` generally thread-safe
- Inside OpenMP parallel regions, the guarded `ftimer_core` timer operations run only on the master thread
- Non-master calls to those guarded core timer operations become no-ops instead of mutating shared timer state
- Suppressed non-master calls are skipped before normal validation, emit no stderr warning, and leave any caller-provided `ierr` unchanged
- The OpenMP guards do not broaden support for concurrent access to other APIs; summary/report generation and other shared access remain unsupported in threaded regions
- Thread-local timer instances, fuller concurrent timing support, and any `suppress_in_parallel` control remain deferred

### Consequences for timing data

The silent worker-thread no-op model has specific, observable consequences that users must understand to avoid misreading summary output:

- **Timer calls made exclusively on worker threads are silently dropped**: no summary entry is created, no call count is incremented, and no timing data is recorded for those calls. A timer name that is started and stopped only on worker threads will not appear in the summary at all.
- **Call counts reflect only master-thread invocations, not all-thread counts**: when all N threads in a parallel region call `start`/`stop` for the same timer, only the master thread's call is recorded; the summary shows `call_count = 1`, not `N`.
- **Timing inside a parallel region captures only the master-thread timing window**: worker-thread work duration is not separately captured or aggregated into the timer's inclusive or self time.
- **Supported pattern**: place `start`/`stop` calls outside the `!$omp parallel` block to time a parallel region as a whole. The master-thread timing window then spans the full wall-clock duration of the parallel work.
- **Misleading pattern**: placing `start`/`stop` inside a parallel region with the expectation that each thread contributes timing data is not supported under this contract. Only the master thread's calls take effect; worker-thread contributions are silently absent.

## Callback Contract

- `on_event` fires on normal start/stop only
- Repair transitions do NOT fire callbacks
- `user_data` c_ptr for opaque state
