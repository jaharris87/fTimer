# fTimer Semantics Reference

This document describes the current runtime contract on `main`.

Current `main` implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and the Phase 6 OpenMP guard behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `mpi_summary()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, root-side MPI min/max/avg/imbalance fields, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with a local-only summary.

Forward-looking target design notes belong in `docs/design.md`. When the two documents differ, `README.md` and the implementation under `src/` define the current user-facing contract.

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

## OpenMP Limitations

- OpenMP guard behavior is enabled only when the library is built with `FTIMER_USE_OPENMP=ON`
- The implemented model is master-thread-only timing; this phase does not make `fTimer` generally thread-safe
- Inside OpenMP parallel regions, the guarded `ftimer_core` timer operations run only on the master thread
- Non-master calls to those guarded core timer operations become no-ops instead of mutating shared timer state
- Suppressed non-master calls are skipped before normal validation, emit no stderr warning, and leave any caller-provided `ierr` unchanged
- The OpenMP guards do not broaden support for concurrent access to other APIs; summary/report generation and other shared access remain unsupported in threaded regions
- Thread-local timer instances, fuller concurrent timing support, and any `suppress_in_parallel` control remain deferred

## Callback Contract

- `on_event` fires on normal start/stop only
- Repair transitions do NOT fire callbacks
- `user_data` c_ptr for opaque state
