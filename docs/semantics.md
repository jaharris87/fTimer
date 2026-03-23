# fTimer Semantics Reference

Phase 2 note: this document is still a forward-looking outline, not a complete runtime contract.

Current `main` now implements the Phase 2 core timer behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, and the `ierr` vs stderr error contract. Summary construction/formatting, MPI summary guarantees, and OpenMP behavior below are still future work.

Treat the sections below as implementation targets unless they describe the Phase 2 core behaviors listed above.

## Timing Model

- Inclusive vs exclusive (self) time definitions
- Wall-clock only (no CPU time, no hardware counters)

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
