# AGENTS.md

This file provides context to Codex when reviewing code in this repository.

## Project Context

**fTimer** — A lightweight, correctness-first wall-clock timing library for modern Fortran. Stack-based nesting, context-sensitive accounting, hierarchical summaries, configurable mismatch handling, MPI cross-rank statistics, and callback hooks for external profiling tools.

## What Matters Most in This Repo

### Timing Correctness (highest priority)

- **Context mismatch in start/stop ordering**: `stop` must pop the call stack BEFORE looking up the context index. If the lookup happens before the pop, the context will be the "timer is running" stack instead of the "timer's parent" stack, silently zeroing times or attributing them to the wrong context.
- **Iterative repair timestamp consistency**: When repairing a nesting mismatch, all unwound timers and the target timer must use a single `now` timestamp captured once. Independent clock reads for each step create timing gaps or double-counting that is invisible in output but makes times not sum correctly.
- **Repair must NOT fire user callbacks**: Internal repair transitions (unwinding/restarting timers during mismatch repair) must not fire the `on_event` callback. If they do, external profiling tools (PAPI, likwid) will see phantom start/stop events that corrupt their measurements.
- **Self-time computation boundaries**: Exclusive/self time is `inclusive - sum(direct children)`. If child iteration boundaries are wrong (e.g., iterating past the next sibling into cousins), self_time can go negative or exceed inclusive_time. Both conditions indicate a bug.

### Numerical Precision

- **Double-precision truncation**: All timing arithmetic must use `real(wp)` where `wp = selected_real_kind(15, 307)`. Any implicit conversion to default `real` (single precision) degrades accuracy for runs longer than ~1 hour. Watch for literal constants without `_wp` suffix and mixed-precision arithmetic.

### MPI Correctness

- **MPI summary hangs on inconsistent timer sets**: If ranks have different timer names or context structures, collective operations (MPI_Reduce, MPI_Allgather) will deadlock or produce garbage. The hash-based preflight check is mandatory before any collective — it must compare canonical timer descriptors across all ranks and fall back to local-only summary on mismatch.
- **Array growth divergence across MPI ranks**: If ranks create timers in different orders or different counts, segment array indices diverge. MPI collectives that assume matching indices will reduce the wrong timers against each other, producing plausible but wrong cross-rank statistics.

### Code Quality Risks

- **Docs drift**: `CLAUDE.md`, README, `docs/semantics.md`, and any user-facing help text must match the actual implementation. Discrepancies are real bugs.
- **Test skepticism**: Ask whether tests actually exercise the behavior they claim to test. Mock clock tests that never advance time, or mismatch tests that don't verify the stack state after repair, provide false confidence.
- **Silent fallbacks**: Any code path that substitutes a default value for missing data should be flagged. Silent fallbacks can mask real errors and produce plausible-looking but wrong output. In particular: missing `ierr` argument should warn, not silently succeed.

## Architecture Quick Reference

```
ftimer.F90  (procedural wrappers + default global instance)
  └─► ftimer_core.F90  (ftimer_t class: init, start, stop, reset, finalize, lookup)
        ├─► ftimer_types.F90   (types, kinds, constants, enums, summary types, callback interface)
        ├─► ftimer_clock.F90   (injectable clock: MPI_Wtime vs system_clock)
        ├─► ftimer_summary.F90 (structured summary + text formatting)
        └─► ftimer_mpi.F90    (MPI reduce + hash preflight)
```

Key data flow: `start("name")` → lookup/create segment → find/create context (current call stack) → push onto call stack → record start_time. `stop("name")` → verify top-of-stack match → pop call stack → find context (now-current stack) → accumulate elapsed time.

The call stack state CHANGES between start and stop — this is the most common source of context attribution bugs.

## Review Standards

When reviewing PRs in this repo:

1. **Anchor findings in code**: Cite specific files, functions, and line numbers. Do not make vague claims.
2. **Prioritize correctness over style**: A real bug matters more than a missing docstring.
3. **Be skeptical of tests**: Ask whether the test actually exercises the behavior it claims to test.
4. **Verify docs match implementation**: If the PR changes behavior, check that CLAUDE.md, README, and any relevant comments are updated.
5. **Prefer fewer, more serious findings**: Two real concerns are worth more than twenty style nits.
6. **Begin your response with the review type heading** (`## Software Review`, `## Methodology Review`, or `## Red Team Review`) so it is clear which review you are responding to.
