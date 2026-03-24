# fTimer Semantics Reference

Phase 6 note: this document is still a forward-looking outline, not a complete runtime contract.

Current `main` now implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and the Phase 6 OpenMP guard behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `mpi_summary()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, root-side MPI min/max/avg/imbalance fields, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with a local-only summary.

Treat the sections below as implementation targets unless they describe the Phase 2/3 behaviors listed above.

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
