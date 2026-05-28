> **When to read this:** When runtime behavior or contract is changing or unclear. This is the primary current runtime contract document on `main`. Do not load this by default for routine coding tasks where the behavior is not in question.

# fTimer Semantics Reference

This document describes the current runtime contract on `main`.

Current `main` implements the Phase 2 core timer behavior, Phase 3 local summary/reporting behavior, Phase 4 procedural wrappers, Phase 5 MPI structured summaries, and the Phase 6 OpenMP guard behavior: stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, the procedural `ftimer_scope` scoped guard, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `write_summary_csv()`, `mpi_summary()`, `print_mpi_summary()`, `write_mpi_summary()`, `write_mpi_summary_csv()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, globally meaningful MPI min/avg/max summary fields on every participating rank, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` returns `FTIMER_ERR_NOT_IMPLEMENTED` with an empty MPI summary result.

This contract is strongest for disciplined serial and pure-MPI wall-clock timing. The OpenMP path is a narrow master-thread-only carve-out for bracketing a parallel region as a whole, not a general hybrid-thread timing contract. Likewise, `on_event` is a lightweight intra-run hook, not a stable external-profiler integration API.

Current architecture, validation, and workflow notes belong in `docs/design.md`. Historical phase-roadmap notes belong in `docs/implementation-history.md`. When current-state sources disagree, use this repository-wide precedence order: current code under `src/`, then current behavioral tests, then `docs/semantics.md`, then `README.md`, then `docs/design.md`.

## Timing Model

- Inclusive vs exclusive (self) time definitions
- Wall-clock only (no CPU time, no hardware counters)
- Injected clocks are expected to be monotonic within a timing run

### Default serial `system_clock` assumptions

In non-MPI builds, the build-default clock used by `type(ftimer_t)` and the
procedural wrappers is Fortran `system_clock(count, rate)` converted to seconds
as `real(count, wp) / real(rate, wp)`.

- fTimer assumes `rate > 0` and that the returned count is nondecreasing over a
  timing run. If `rate` is unavailable, the current default clock stops with
  `error stop`.
- fTimer does not independently prove monotonicity, clamp backward movement, or
  synthesize corrected elapsed time. If the processor clock moves backward,
  resets, or otherwise returns a smaller count than an earlier call, the
  resulting negative interval remains visible in accumulated times and
  summaries. This matches the injected-clock contract: bad clock values are not
  hidden by the timing runtime.
- fTimer does not compensate for `system_clock` counter wrap. The useful
  uninterrupted run length therefore depends on the compiler/runtime
  `count_max` and `count_rate` for the integer kind used by fTimer's
  `system_clock` call. On common modern 64-bit implementations this horizon is
  expected to be very large, but less-common toolchains should be checked before
  relying on one timing run for very long jobs.
- The nominal resolution is one clock tick, `1 / count_rate` seconds. Arithmetic
  after the clock read uses `real(wp)`, so fTimer preserves double-precision
  timing arithmetic but cannot recover resolution or monotonicity that the
  underlying `system_clock` backend does not provide.
- The `start_date` and `end_date` strings in local summaries are wall-date
  labels from `date_and_time`; they are not the source of elapsed-time
  accounting and should not be interpreted as clock metadata.

Current local and MPI summary types do not expose clock rate, count range, or
monotonicity metadata, and formatted reports do not inject automatic clock
metadata. That is deliberate for current `main`: arbitrary injected clocks do
not have a common rate/wrap model, MPI builds use `MPI_Wtime()` as their default
clock, and adding partial metadata to summary schemas would be a user-visible API
change. Applications that need to record target-system clock characteristics can
add them as user metadata in reports after inspecting their toolchain. A future
explicit clock-info helper can be designed if adopter demand appears.

No runtime monotonicity or wrap sanity check is currently performed beyond the
`rate > 0` guard in the serial default clock. A small sample at initialization
cannot guarantee future monotonicity or wrap safety, while per-call checks would
add overhead and change the current contract that backward clock values are
surfaced rather than hidden.

### Wall-clock interpretation responsibilities

fTimer records the elapsed host wall-clock interval between the caller's
`start` and `stop` calls. It does not synchronize accelerator/device queues,
wait on asynchronous offload work, or insert MPI barriers around timer regions.

- For asynchronous accelerator or device work, a timer around a launch may
  measure only host enqueue/launch latency. If the intended quantity is device
  completion time, the caller must perform the appropriate device synchronization
  before `stop`.
- For MPI phase timing, rank-local start/stop windows are exactly that:
  rank-local wall-clock intervals. `mpi_summary()` reduces the recorded local
  intervals, but it does not imply that all ranks entered or exited the phase
  together. If the intended quantity is a synchronized global phase duration,
  the caller must place any required MPI synchronization outside the measured
  region or deliberately include it in the measured region.

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
- `ierr` absent: emit a diagnostic to stderr
- Validation and lifecycle errors follow a warn-and-return contract: they leave timer state unchanged unless the caller explicitly selected a repair-capable mismatch mode
- Error codes and their meanings

## Compile-Out / No-Op Instrumentation Pattern

The fTimer runtime itself is not conditionally compiled into a no-op mode. Its core semantics remain unconditional: when an application links fTimer and calls `ftimer_start`, `ftimer_stop`, scoped guards, summary APIs, callbacks, or MPI reporting APIs, the normal runtime contracts in this document apply.

Applications that need to leave timing calls in source while removing runtime overhead and fTimer dependencies in selected builds should use an application-owned facade module. The supported pattern is two facade implementations with the same application-facing interface:

- an enabled facade that delegates to fTimer and links `fTimer::ftimer`
- a disabled facade that does not `use ftimer`, does not link fTimer, and stores no timer state

Disabled facade entry points are intentionally silent no-ops. If an `ierr` argument is present, the disabled facade should set it to `0`, matching `FTIMER_SUCCESS`; if `ierr` is absent, it should not write to stderr. Disabled calls do not validate timer names, maintain a nesting stack, create segments or summaries, write timing artifacts, fire callbacks, or enter MPI collectives.

This disabled-facade behavior is an application integration contract, not an alternate fTimer runtime mode. To keep disabled builds dependency-free, applications should avoid exposing fTimer summary types or constants in unconditional source and should instead expose application-level report helpers, simple counters, or status values from the facade. fTimer intentionally does not provide an installed drop-in no-op module named `ftimer`, because that would make it too easy for a build to accidentally shadow the real library API.

## Timer Name / Summary Text Policy

- Public timer creation/lookup paths right-trim trailing blanks, reject empty names, reject names that begin with a blank, and reject ASCII control characters. They do not silently truncate names and do not impose the legacy `FTIMER_NAME_LEN` value as a runtime name cap.
- Timer names, runtime segment names, local summary entry names, MPI summary entry names, and metadata key/value fields use allocatable-length character storage. The exported `FTIMER_NAME_LEN = 64` constant is retained so code that imports it still compiles, but it is not the current storage or validation limit. Pre-1.0 code that treated those components as fixed writable buffers, such as internal writes directly into metadata `%value`, must allocate or assign through a temporary string first.
- Metadata entries with an unallocated or blank key are skipped by formatted reports and CSV exports. An unallocated metadata value is emitted as blank; assigned metadata values are emitted at their full trimmed length.
- Name-based `start`/`stop` remains the default supported timing path; the runtime uses internal mapped lookup for both resident timer names and per-segment parent-stack contexts, plus capacity-based growth, so that this ergonomic path avoids repeated resident-timer linear scans, steady-state context-list scans, and one-slot-at-a-time whole-array growth as the timer set grows
- Per-timer context selection remains fully context-sensitive accounting over the current parent stack for that timer; repeated reuse of one timer name under many distinct parent stacks now uses a per-segment parent-stack index in steady state rather than rescanning the full known-context list each time
- `lookup()` plus `start_id()`/`stop_id()` remains an optional hot-path optimization for tight loops that repeatedly time the same known regions, especially when long labels would otherwise be validated and hashed on every name-based call
- Formatted summary output does not emit unsafe raw summary-entry names literally
- Escaped formatted-summary forms are stable: leading blanks render as `\x20`, backslashes render as `\\`, tab/newline/carriage return render as `\t`/`\n`/`\r`, other ASCII control characters render as `\xNN`, and blank/empty raw names render as `<blank>`

## Scoped Guard Contract

- `ftimer_scope(guard, name, ierr)` is the only scoped guard constructor on current `main`
- The public guard type is `ftimer_guard_t`, imported from `ftimer`
- Scoped guards use the default procedural timer instance; there is no `type(ftimer_t)` scoped guard API on current `main`
- `ftimer_scope` starts the named timer through the same validation, lookup, accounting, and callback path as normal name-based `start`
- If `ftimer_scope` fails while initializing an inactive guard, the guard remains inactive. Finalization and `guard%stop(ierr)` are no-ops for inactive guards.
- Calling `ftimer_scope` on an already-active guard returns `FTIMER_ERR_ACTIVE`, or warns when `ierr` is omitted, and leaves the existing active ownership unchanged.
- A guard owns exactly one activation token from its successful start. `guard%stop(ierr)` may stop only that exact activation while it is still the top of the stack.
- If the guard's activation has already been stopped, repaired away, or replaced by another activation with the same timer name, `guard%stop(ierr)` returns `FTIMER_ERR_MISMATCH` and leaves timer state unchanged.
- The guard finalizer attempts the same exact-activation stop without `ierr`. On mismatch or lifecycle errors, it warns to stderr and does not repair.
- Scoped guard finalization does not force-stop arbitrary matching timer names, synthesize elapsed time, invoke mismatch repair, or hide errors silently.
- `guard%stop(ierr)` is the supported way to observe finalizer-equivalent stop errors before scope exit.
- Guard assignment/copy is unsupported and does not copy or transfer active ownership. Assignment involving an active guard warns to stderr and leaves active ownership with the original guard. Use one scalar guard variable per lexical block.
- Guard arrays, saved/global guards, function-return guard constructors, and cross-procedure lifetime patterns are unsupported.
- `ftimer_scope_id` is deferred; use explicit `lookup()` plus `start_id()`/`stop_id()` for cached-id hot paths.
- The scoped guard is a safety layer for simple lexical blocks and early exits. Use explicit `start`/`stop` for non-lexical lifetimes, complex ownership, or timing that spans procedure boundaries.

## Reset Behavior

- Zeros times and counts, preserves timer definitions
- Restarts the local monitoring window used for `summary%total_time` and `% Total`
- Error if timers are active; `reset()` does not auto-stop or clean up active timers

## Clock Configuration Contract

- Configure custom clocks through `set_clock()` and restore the build-default wall clock through `clear_clock()`
- Direct mutation of raw runtime clock internals is not part of the supported API contract
- Clock configuration is allowed before `init()` or before a run records timing data
- Once a run has recorded timing data, `set_clock()` and `clear_clock()` return `FTIMER_ERR_ACTIVE` (or warn to stderr when `ierr` is omitted) and leave state unchanged
- `reset()`, `init()`, and `finalize()` all provide clean lifecycle boundaries after which a different clock may be configured

## Lifecycle Errors With Active Timers

- `init`, `reset`, and `finalize` require a fully stopped timer set
- With `ierr` present, these lifecycle calls return `FTIMER_ERR_ACTIVE` and do not write to stderr
- With `ierr` absent, they warn to stderr and return immediately with the timer state unchanged
- They do not force-stop timers, synthesize elapsed time, zero accumulated data, restart the summary window, or perform hidden cleanup
- In `FTIMER_USE_OPENMP=ON` builds, these lifecycle bullets apply only to serial code and OpenMP master-thread calls; non-master calls are suppressed before validation, emit no warning, and leave any caller-provided `ierr` unchanged
- Repairing stop mismatches is a separate explicit opt-in through `mismatch_mode = FTIMER_MISMATCH_WARN` or `FTIMER_MISMATCH_REPAIR`

## Local Summary Contract

- `get_summary()` returns a local-only `ftimer_summary_t`
- `get_summary()`, `print_summary()`, and `write_summary()` are live snapshot APIs, not stopped-run-only final-report APIs
- If timers are active at the snapshot timestamp, local summaries include those active contexts with elapsed time computed through that timestamp; they do not synthesize hidden stops, fire callbacks, or mutate runtime state
- `summary%has_active_timers` is true when at least one returned entry was active at the snapshot timestamp
- `summary%entries` remain in preorder so current formatted-report traversal and existing depth-oriented consumers keep working
- Each entry retains `name` and `depth`, exposes explicit tree linkage through `node_id` and `parent_id`, and exposes `is_active` for that timer context at the snapshot timestamp
- `call_count` remains the count of user-visible `start` calls for that exact timer context. Repair-mode internal continuations can therefore appear as active entries with `is_active = .true.` and `call_count = 0`; that is not a hidden user call.
- `node_id` is unique and stable only within one produced summary object
- `parent_id` refers to another entry's `node_id`; roots use `parent_id = 0`
- Current `main` does not promise that local summary node ids remain stable across separate runs or across independently produced summary objects
- `print_summary()` and `write_summary()` format the same local snapshot data. When any returned entry is active, formatted reports add active-state information and reserve the `Active timers` metadata key for the built-in snapshot status line. A formatted local report whose `Active timers` field is `yes` is an interim snapshot, not a final stopped-run report.
- `write_summary_csv()` exports the same local snapshot data in CSV format version `1`. It writes one header row, a `record_type=summary` row, zero or more `record_type=metadata` rows, and one `record_type=entry` row per summary entry. Entry rows include `node_id`, `parent_id`, `depth`, `name`, `inclusive_time`, `self_time`, `call_count`, `avg_time`, `pct_time`, and `is_active`.
- CSV `append=.true.` appends records to the target file and omits the header when the existing file is non-empty. Non-empty append targets must begin with the fTimer CSV format-version-1 header and end with a newline; mismatched headers or unterminated final records are rejected with `FTIMER_ERR_IO` instead of silently mixing schemas.
- CSV text fields emit the same trimmed timer names and metadata key/value text used by fTimer reports, with standard CSV quoting. They are not spreadsheet-formula-sanitized.
- A caller that requires a final local report should stop all timers first and verify `summary%has_active_timers == .false.`

## MPI Guarantees

- `mpi_summary()` is collective over the communicator captured by `init`
- Omitting `comm` at `init` means `mpi_summary()` uses `MPI_COMM_WORLD`
- All ranks in that communicator must enter `mpi_summary()` with fully stopped timers
- Unlike local summaries, MPI summaries are final stopped-run summaries only; active timers return `FTIMER_ERR_ACTIVE`
- The current validated MPI interface path is `use mpi` with integer communicator handles captured at `init`
- `FTIMER_USE_MPI=ON` configure requires that the active `use mpi` path compile the `MPI_Type_match_size` and `MPI_ERRORS_RETURN` calls used for datatype validation
- MPI summary reductions select MPI datatypes with `MPI_Type_match_size` for the actual `real(wp)` and `integer(int64)` storage sizes before reducing those buffers. If that validation API is present but the active MPI implementation cannot provide matching datatypes at runtime, `mpi_summary()` temporarily requests MPI error returns for the datatype lookup, fails with `FTIMER_ERR_UNKNOWN`, and leaves the MPI result empty instead of reducing through a mismatched fixed datatype.
- Hash-based timer-descriptor preflight before the reduction phase
- The strict MPI preflight compares rank-local descriptor hashes against a rank-0 reference hash, then reduces a mismatch flag across the communicator. Successful summaries do not allgather every rank's hashes or exchange exact descriptor strings.
- Extra timers, missing timers, renamed timers, and hierarchy/context mismatches fail the MPI summary with `FTIMER_ERR_MPI_INCON`; they do not fall back to a local summary object through the MPI API
- Rank-conditional timer reductions are not supported by the current strict `mpi_summary()` API. Sparse/union MPI summaries are planned as a separate opt-in path; see [`docs/mpi-sparse-summary-decision.md`](mpi-sparse-summary-decision.md).
- When that descriptor preflight fails inside one communicator, the omitted-`ierr` diagnostic reports the disagreeing communicator-local ranks when possible
- MPI descriptor matching is based on the local summary tree shape and names, not on raw local `node_id` values
- The MPI descriptor preflight materializes deterministic length-prefixed path strings at summary time so names that differ only after the legacy 64-character threshold remain distinguishable. This is outside the start/stop hot path, but its memory and sort cost scales with summary entry count and encoded path length for very large timer trees.
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
- This datatype selection is a targeted portability guard for the current `use mpi` implementation. The broader `mpi_f08` interface migration remains separate follow-up work tracked in GitHub issue #136.

## MPI Reporting Contract

- `print_mpi_summary()` and `write_mpi_summary()` are the first-class text reporting paths for `ftimer_mpi_summary_t`
- `write_mpi_summary_csv()` is the first-class machine-readable reporting path for `ftimer_mpi_summary_t`
- They are collective over the communicator captured by `init`, just like `mpi_summary()`
- They build the same global MPI summary object that `mpi_summary()` returns
- They emit one communicator-level report from rank 0; non-root participants take part in the collective build and then return success without duplicating output
- The default MPI text report is an abbreviated view of `ftimer_mpi_summary_t`, not a serialization of every structured field. It prints communicator totals plus per-entry min/avg/max inclusive time, inclusive-time extrema ranks, inclusive imbalance, average self time, average call count, and `Avg %`; use `mpi_summary()` directly for min/max self time, self imbalance, min/max call count, min/max rank-local `% Total`, and explicit `node_id`/`parent_id` tree links.
- The MPI CSV export uses CSV format version `1` with `summary_kind=mpi`. It emits summary and metadata rows plus one entry row per MPI summary entry, including explicit tree links and all reduced fields from `ftimer_mpi_summary_t`.
- In the MPI text report, `Avg %` is `avg_pct_time`: the arithmetic mean of each rank's local `% Total` for that timer. It is not recomputed as `100*avg_inclusive_time/avg_total_time`, because rank-local denominator differences are part of the reported statistic.

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
- Future real hybrid MPI+OpenMP timing is deferred pending concrete adopter demand; see [`docs/openmp-hybrid-strategy-decision.md`](openmp-hybrid-strategy-decision.md)

### Consequences for timing data

The silent worker-thread no-op model has specific, observable consequences that users must understand to avoid misreading summary output:

- **Timer calls made exclusively on worker threads are silently dropped**: no summary entry is created, no call count is incremented, and no timing data is recorded for those calls. A timer name that is started and stopped only on worker threads will not appear in the summary at all.
- **Call counts reflect only master-thread invocations, not all-thread counts**: when all N threads in a parallel region call `start`/`stop` for the same timer, only the master thread's call is recorded; the summary shows `call_count = 1`, not `N`.
- **Timing inside a parallel region captures only the master-thread timing window**: worker-thread work duration is not separately captured or aggregated into the timer's inclusive or self time.
- **Supported pattern**: place `start`/`stop` calls outside the `!$omp parallel` block to time a parallel region as a whole. The master-thread timing window then spans the full wall-clock duration of the parallel work.
- **Misleading pattern**: placing `start`/`stop` inside a parallel region with the expectation that each thread contributes timing data is not supported under this contract. Only the master thread's calls take effect; worker-thread contributions are silently absent.
- **Scoped guard limitation**: block-local scoped guard finalization inside an OpenMP parallel region is unsupported. To time a parallel region, place explicit `start`/`stop` or a scoped guard outside the `!$omp parallel` block.

## Callback Contract

- Configure callbacks through `set_callback()` and `clear_callback()`, not by mutating runtime internals directly
- `set_callback()` may be called before or after `init()`, but callback configuration changes are rejected while timers are active
- `set_callback()` accepts optional opaque `user_data`; omitting it stores `c_null_ptr`
- `clear_callback()` and `finalize()` clear both the callback registration and its stored `user_data`
- `on_event` is an optional lightweight intra-run hook for normal start/stop events on one timer instance
- The current callback contract exposes numeric runtime identifiers only; it does not define a stable semantic mapping back to timer names or full context paths for external-profiler backends
- Repair transitions do NOT fire callbacks
- Scoped guards fire only the normal underlying start/stop events. They do not synthesize extra callback events during finalization.
- Mutating timer state from callbacks during scoped guard start/stop is unsupported.
- `user_data` remains opaque callback state, not a separate user-facing mutable runtime field
