> **When to read this:** When runtime behavior or contract is changing or unclear. This is the primary current runtime contract document on `main`. Do not load this by default for routine coding tasks where the behavior is not in question.

# fTimer Semantics Reference

This document describes the current runtime contract on `main`.

Current `main` implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and the Phase 6 OpenMP guard behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `mpi_summary()`, `print_mpi_summary()`, `write_mpi_summary()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, globally meaningful MPI min/avg/max summary fields on every participating rank, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with an empty MPI summary result.

This contract is strongest for disciplined serial and pure-MPI wall-clock timing. The OpenMP path is a narrow master-thread-only carve-out for bracketing a parallel region as a whole, not a general hybrid-thread timing contract. Likewise, `on_event` is a lightweight intra-run hook, not a stable external-profiler integration API.

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

## Local Summary Contract

- `get_summary()` returns a local-only `ftimer_summary_t`
- `summary%entries` remain in preorder so current formatted-report traversal and existing depth-oriented consumers keep working
- Each entry retains `name` and `depth`, and now also exposes explicit tree linkage through `node_id` and `parent_id`
- `node_id` is unique and stable only within one produced summary object
- `parent_id` refers to another entry's `node_id`; roots use `parent_id = 0`
- Current `main` does not promise that local summary node ids remain stable across separate runs or across independently produced summary objects

## MPI Guarantees

- `mpi_summary()` is collective over the communicator captured by `init`
- Omitting `comm` at `init` means `mpi_summary()` uses `MPI_COMM_WORLD`
- All ranks in that communicator must enter `mpi_summary()` with fully stopped timers
- The current validated MPI interface path is `use mpi` with integer communicator handles captured at `init`
- Hash-based timer-descriptor preflight before the reduction phase
- Extra timers, missing timers, renamed timers, and hierarchy/context mismatches fail the MPI summary with `FTIMER_ERR_MPI_INCON`; they do not fall back to a local summary object through the MPI API
- When that descriptor preflight fails inside one communicator, the omitted-`ierr` diagnostic reports the disagreeing communicator-local ranks when possible
- MPI descriptor matching is based on the local summary tree shape and names, not on raw local `node_id` values
- Mismatched communicator choices across would-be participants are unsupported; this API has no safe cross-communicator rendezvous to detect that misuse without risking the same MPI deadlock it is trying to avoid

### Unsupported communicator mismatch example

Suppose ranks 0-1 initialize a timer with one communicator split and later call `mpi_summary()`, while ranks 2-3 reach `mpi_summary()` through a different communicator choice. That is unsupported misuse.

This is not like descriptor inconsistency within one communicator, where every participant can still enter the same collective and the library can fail the MPI summary cleanly after a preflight mismatch. Once ranks have already diverged onto different communicators, `mpi_summary()` has no safe second rendezvous it can use to discover the mistake without risking the same deadlock it is trying to avoid. The practical failure mode is a hang, not `FTIMER_ERR_MPI_INCON`.

The supported pattern is simple: capture one communicator consistently at `init`, then have that same participant set enter `mpi_summary()` together.

## MPI Summary Contract

`mpi_summary()` returns a distinct `ftimer_mpi_summary_t` instead of reusing the local `ftimer_summary_t` shape.

- `ftimer_mpi_summary_t` contains communicator-wide totals (`min_total_time`, `avg_total_time`, `max_total_time`, `min_total_time_rank`, `max_total_time_rank`, `total_time_imbalance`) plus per-entry communicator-wide statistics (`min_*`, `avg_*`, `max_*`) for inclusive time, self time, call count, and `% Total`.
- MPI summary entries also expose `min_inclusive_time_rank` and `max_inclusive_time_rank` as communicator-local ranks for the inclusive-time extrema; ties resolve to the lowest rank that attains the extremum.
- Successful `mpi_summary()` calls populate the same global MPI result on every participating rank.
- `ftimer_mpi_summary_t` entries retain `name`, `depth`, `node_id`, and `parent_id`, so MPI summaries keep the explicit-tree data model instead of collapsing to flat rows.
- The MPI summary tree order is canonical across ranks. It does not depend on the local timer creation order on one chosen rank.
- `mpi_summary()` does not return local fallback data on errors. If the caller needs local data after an MPI-disabled or MPI-error path, it must call `get_summary()` separately.

## MPI Reporting Contract

- `print_mpi_summary()` and `write_mpi_summary()` are the first-class reporting paths for `ftimer_mpi_summary_t`
- They are collective over the communicator captured by `init`, just like `mpi_summary()`
- They build the same global MPI summary object that `mpi_summary()` returns
- They emit one communicator-level report from rank 0; non-root participants take part in the collective build and then return success without duplicating output

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
"OpenMP Carve-Out And Limitations" below.

This is the deliberate policy rather than a stronger failure (e.g. `error stop`),
chosen for consistency with the library's error contract and because callers that
omit `ierr` have opted into the permissive path. Callers that require hard
enforcement should pass `ierr` and check it.

## OpenMP Carve-Out And Limitations

- OpenMP guard behavior is enabled only when the library is built with `FTIMER_USE_OPENMP=ON`
- This is a narrow master-thread-only carve-out for bracketing a parallel region as a whole; it is not general hybrid MPI+OpenMP timing support
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

- `on_event` is an optional lightweight intra-run hook for normal start/stop events on one timer instance
- The current callback contract exposes numeric runtime identifiers only; it does not define a stable semantic mapping back to timer names or full context paths for external-profiler backends
- Repair transitions do NOT fire callbacks
- `user_data` c_ptr for opaque state
