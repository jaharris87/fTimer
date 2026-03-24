# fTimer Semantics Reference

Phase 5 note: this document is still a forward-looking outline, not a complete runtime contract.

Current `main` now implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, and Phase 5 MPI structured summaries: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `mpi_summary()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, and root-side MPI min/max/avg/imbalance fields. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with a local-only summary. OpenMP behavior below is still future work.

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

- Hash-based preflight before any collective
- Integer comm handle compatibility (mpif.h and mpi_f08)
- Fallback to local-only on inconsistency

## OpenMP Limitations

- Master-thread-only (not thread-safe)
- Non-master calls are no-ops
- `suppress_in_parallel` option

## Callback Contract

- `on_event` fires on normal start/stop only
- Repair transitions do NOT fire callbacks
- `user_data` c_ptr for opaque state
