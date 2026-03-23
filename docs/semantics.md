# fTimer Semantics Reference

<!-- This document will be filled during implementation (Phase 7).
     It should cover all behavioral contracts that users and reviewers
     need to understand. Outline below; details TBD. -->

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
