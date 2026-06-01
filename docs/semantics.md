> **When to read this:** When runtime behavior or contract is changing or unclear. This is the primary current runtime contract document on `main`. Do not load this by default for routine coding tasks where the behavior is not in question.

# fTimer Semantics Reference

This document describes the current runtime contract on `main`.

Current `main` implements stack-based start/stop timing, context-sensitive accounting, strict/warn/repair mismatch handling, `lookup`, `reset`, procedural `ftimer_scope` and OOP `ftimer_oop_scope` scoped guards, the `ierr` vs stderr error contract, `get_summary()`, `print_summary()`, `write_summary()`, `write_summary_csv()`, `mpi_summary()`, `mpi_union_summary()` sparse descriptor-union summaries, `print_mpi_summary()`, `write_mpi_summary()`, `write_mpi_summary_csv()`, `print_mpi_union_summary()`, `write_mpi_union_summary()`, `write_mpi_union_summary_csv()`, self-time computation, callback suppression during repair, descriptor-hash MPI preflight, globally meaningful MPI min/avg/max summary fields on every participating rank, and limited master-thread-only OpenMP guards in `ftimer_core` when built with `FTIMER_USE_OPENMP=ON`. In non-MPI builds, `mpi_summary()` and `mpi_union_summary()` return `FTIMER_ERR_NOT_IMPLEMENTED` with empty MPI summary results; MPI report APIs, including sparse union reports and CSV export, return `FTIMER_ERR_NOT_IMPLEMENTED` without emitting report output.

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

### Public Status And Error Codes

These constants are public from `ftimer_types` and are the canonical status values returned through optional `ierr` arguments.

| Constant | Code | Meaning |
| --- | --- | --- |
| `FTIMER_SUCCESS` | `0` | Operation completed successfully. |
| `FTIMER_ERR_NOT_INIT` | `1` | The timer instance or default procedural instance has not been initialized for the requested operation. |
| `FTIMER_ERR_NOT_IMPLEMENTED` | `2` | The requested API is unavailable in this build, such as MPI summary/report APIs when `FTIMER_USE_MPI=OFF`. |
| `FTIMER_ERR_UNKNOWN` | `3` | Generic failure for an unsupported or unexpected condition that does not have a more specific public code. |
| `FTIMER_ERR_ACTIVE` | `4` | An active timer, a guard-owned activation still on the timer stack, or already-recorded timing data prevents the requested lifecycle, configuration, or report operation. |
| `FTIMER_ERR_MISMATCH` | `5` | Strict nesting, cached-id, or scoped-guard ownership checks detected a start/stop mismatch. |
| `FTIMER_ERR_MPI_INCON` | `6` | MPI participants have inconsistent timer descriptor trees for a strict MPI summary/report operation. |
| `FTIMER_ERR_IO` | `7` | File, unit, or CSV append validation failed. |
| `FTIMER_ERR_INVALID_NAME` | `8` | A timer name failed public name validation. |

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
- Metadata entries with an unallocated or blank key are skipped by formatted reports and CSV exports. An unallocated metadata value is emitted as blank; assigned metadata values are right-trimmed before text-report escaping or CSV quoting.
- Name-based `start`/`stop` remains the default supported timing path; the runtime uses internal mapped lookup for both resident timer names and per-segment parent-stack contexts, plus capacity-based growth, so that this ergonomic path avoids repeated resident-timer linear scans, steady-state context-list scans, and one-slot-at-a-time whole-array growth as the timer set grows
- Per-timer context selection remains fully context-sensitive accounting over the current parent stack for that timer; repeated reuse of one timer name under many distinct parent stacks now uses a per-segment parent-stack index in steady state rather than rescanning the full known-context list each time
- `lookup()` plus `start_id()`/`stop_id()` remains an optional hot-path optimization for tight loops that repeatedly time the same known regions, especially when long labels would otherwise be validated and hashed on every name-based call
- Cached IDs returned by `lookup()` are opaque handles for the current timer runtime state, not segment-array indexes. They remain valid across `reset()`, but successful `init()` and `finalize()` calls invalidate them. Calls made while finalized follow the normal `FTIMER_ERR_NOT_INIT` lifecycle contract; after a later successful `init()`, passing a stale cached ID to `start_id()` or `stop_id()` returns `FTIMER_ERR_UNKNOWN` and leaves timer state unchanged
- Formatted summary output does not emit unsafe raw summary-entry names or metadata header text literally
- Escaped formatted-summary forms are stable: leading blanks render as `\x20`, backslashes render as `\\`, tab/newline/carriage return render as `\t`/`\n`/`\r`, delete, terminal escape bytes, C0/C1 control bytes, UTF-8 encoded C1 controls, and other ASCII control characters render as `\xNN`, valid non-control UTF-8 text is preserved, blank/empty raw names render as `<blank>`, and blank metadata values remain blank

## Scoped Guard Contract

- Scoped guards are an optional safety layer for simple lexical blocks and early exits; explicit `start`/`stop` remains the primary OOP API and the right choice for non-lexical lifetimes, complex ownership, cached-id hot paths, or timing that spans procedure boundaries
- Procedural scoped timing uses `type(ftimer_guard_t)` from `ftimer` with `call ftimer_scope(guard, name, ierr)` and records on the saved default timer instance
- OOP scoped timing uses `type(ftimer_oop_guard_t)` from `ftimer_core` with `call ftimer_oop_scope(timer, guard, name, ierr)`, where `timer` is an associated `type(ftimer_t), pointer`
- The OOP guard stores a non-owning pointer to that timer. The timer target must outlive the guard, remain allocated/alive, and remain initialized until the guard is inactive. Declare the guard in a nested block or procedure scope that exits before the timer target can go out of scope, or call `guard%stop(ierr=...)` before leaving a shared scope or performing timer lifecycle operations
- Declaring an active OOP guard in the same scoping unit as an automatic timer object and relying on finalization order at scope exit is unsupported
- Procedural `ftimer_scope` and OOP `ftimer_oop_scope` start the named timer through the same validation, lookup, accounting, and callback path as normal name-based `start`
- If `ftimer_scope` or `ftimer_oop_scope` fails while initializing an inactive guard, the guard remains inactive. Finalization and `guard%stop(ierr)` are no-ops for inactive guards.
- Calling `ftimer_scope` or `ftimer_oop_scope` on an already-active guard returns `FTIMER_ERR_ACTIVE`, or warns when `ierr` is omitted, and leaves the existing active ownership unchanged.
- A guard owns exactly one activation token from its successful start. `guard%stop(ierr)` may stop only that exact activation while it is still the top of the stack.
- If the guard's activation has already been stopped, repaired away, invalidated by timer lifecycle, or replaced by another activation with the same timer name, `guard%stop(ierr)` returns `FTIMER_ERR_MISMATCH` or the relevant lifecycle error and leaves timer state unchanged.
- A guard-owned activation that is still active on the timer stack makes `reset()` and `finalize()` fail through the normal `FTIMER_ERR_ACTIVE` lifecycle contract; timer lifecycle operations do not force-stop or clear active guards
- fTimer does not keep a separate registry of live guard objects. If user code manually stops or repairs away a guard-owned activation first, the timer stack is no longer active; later lifecycle calls can proceed, and the still-active guard object becomes stale. A later `guard%stop(ierr)` or guard finalizer reports that stale ownership as a mismatch or lifecycle error.
- The guard finalizer attempts the same exact-activation stop without `ierr`. On mismatch or lifecycle errors, it warns to stderr and does not repair.
- Scoped guard finalization does not force-stop arbitrary matching timer names, synthesize elapsed time, invoke mismatch repair, or hide errors silently.
- `guard%stop(ierr)` is the supported way to observe finalizer-equivalent stop errors before scope exit.
- Guard assignment/copy is unsupported and does not copy or transfer active ownership. Assignment involving an active guard warns to stderr and leaves active ownership with the original guard. Use one scalar guard variable per lexical block.
- Guard arrays, saved/global guards, function-return guard constructors, cross-procedure lifetime patterns, deallocated timer targets, and block-local scoped guard finalization inside OpenMP parallel regions are unsupported.
- `ftimer_scope_id` is deferred; use explicit `lookup()` plus `start_id()`/`stop_id()` for cached-id hot paths.

## Reset Behavior

- Zeros times and counts, preserves timer definitions
- Restarts the local monitoring window used for `summary%total_time` and `% Total`
- Error if timers are active; `reset()` does not auto-stop or clean up active timers

## Clock Configuration Contract

- Configure custom clocks through `set_clock()` and restore the build-default wall clock through `clear_clock()`
- Direct mutation of raw runtime clock internals is not part of the supported API contract
- Clock configuration is allowed before `init()` or before a run records timing data
- When a clock is configured before `init()`, the next `init()` starts the local summary window in that clock's epoch
- When `set_clock()` or `clear_clock()` succeeds after `init()` but before any timing data exists, it immediately restarts the local summary window in the newly selected clock's epoch
- The first subsequent `start()` does not rebase the summary window; idle time between the successful clock change and the first start is included in `summary%total_time` and `% Total` denominators
- Empty local summaries, formatted reports, and CSV exports after a successful no-data clock change use the newly selected clock epoch and do not serialize mixed-epoch total times
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
- Local summaries expose context-cardinality diagnostics without changing timing behavior by default. `summary%total_contexts` is the total number of allocated parent-stack contexts across resident timers, `summary%max_contexts_per_timer` is the largest context count attached to any one timer name, and `summary%context_diagnostics(:)` names each resident timer with its allocated context count so callers can identify which timer name has high cardinality. `summary%entries(i)%timer_context_count` repeats that per-timer count on each visible entry.
- Context-cardinality diagnostics count allocated runtime contexts, not just visible summary rows. A context can be allocated but hidden from the entry table after `reset()` or when it has no visible time/calls and is not active. `summary%context_diagnostics(:)` still includes those resident timers so the high-cardinality timer remains identifiable, while `summary%num_entries` remains the visible row count.
- These diagnostics do not add mandatory predeclaration, hard caps, default warning thresholds, or changes to context-sensitive accounting. Text reports and CSV schemas are unchanged; callers that want alerting should inspect the structured summary fields and apply their own threshold.
- `call_count` remains the count of user-visible `start` calls for that exact timer context. It is stored and exported as `integer(int64)` so hot-loop instrumentation is not limited to the default integer range. Starting a context whose count is already at the signed-64-bit maximum fails with `FTIMER_ERR_UNKNOWN` or the normal omitted-`ierr` warning path instead of wrapping. Repair-mode internal continuations can therefore appear as active entries with `is_active = .true.` and `call_count = 0`; that is not a hidden user call.
- `node_id` is unique and stable only within one produced summary object
- `parent_id` refers to another entry's `node_id`; roots use `parent_id = 0`
- Current `main` does not promise that local summary node ids remain stable across separate runs or across independently produced summary objects
- `print_summary()` and `write_summary()` format the same local snapshot data. When any returned entry is active, formatted reports add active-state information and reserve the `Active timers` metadata key for the built-in snapshot status line. A formatted local report whose `Active timers` field is `yes` is an interim snapshot, not a final stopped-run report.
- `write_summary_csv()` exports the same local snapshot data in CSV format version `2`. It writes one header row, a `record_type=summary` row, zero or more `record_type=metadata` rows, and one `record_type=entry` row per summary entry. Entry rows include `node_id`, `parent_id`, `depth`, `name`, `inclusive_time`, `self_time`, `call_count`, `avg_time`, `pct_time`, and `is_active`. The local integer `call_count` field is emitted as decimal text without narrowing to default integer, and version `2` is the schema signal that local `call_count` can require signed 64-bit parsing.
- Local and strict MPI CSV `append=.true.` appends records to the target file and omits the header when the existing file is non-empty. Non-empty append targets must begin with the fTimer CSV format-version-2 header, existing data rows must be well-formed CSV logical records with the exact v2 header field count and recognized `summary_kind`/`record_type` combinations, and the target must end with a newline; mismatched headers, older-format records, malformed v2 record shape or quote placement, or unterminated final records are rejected with `FTIMER_ERR_IO` instead of silently mixing schemas. Sparse union CSV append uses its own exact header and `summary_kind=mpi_union` validation. Append validation is a schema-shape and CSV-syntax guard for existing files, not a semantic reparse of every numeric, logical, or timing payload field already present.
- CSV text fields emit trimmed raw timer names and metadata key/value text with standard CSV quoting. Unlike human-readable text reports, CSV exports do not apply the visible `\t`/`\n`/`\xNN` display escaping. They are not spreadsheet-formula-sanitized.
- A caller that requires a final local report should stop all timers first and verify `summary%has_active_timers == .false.`

## MPI Guarantees

- MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`
- `mpi_summary()` is collective over the communicator captured by `init`
- Omitting `comm` at `init` means `mpi_summary()` uses `MPI_COMM_WORLD`
- `init(comm=...)` stores a non-owning communicator handle; fTimer does not duplicate or free caller-provided communicators
- Callers that pass a subcommunicator must keep it valid until all fTimer MPI summaries, MPI reports, `finalize()`, or `init()` reinitialization that may use that communicator are complete
- All ranks in that communicator must enter `mpi_summary()` with fully stopped timers
- Unlike local summaries, MPI summaries are final stopped-run summaries only; active timers return `FTIMER_ERR_ACTIVE`
- The public MPI communicator interface path is `mpi_f08` with `type(MPI_Comm)` handles captured at `init`
- Legacy integer communicator handles and `mpif.h` are not supported interface paths
- Integer `init` options such as `mismatch_mode` and `ierr` must be passed by
  keyword; positional integer `init` arguments are rejected so legacy
  communicator handles cannot silently bind to non-communicator options
- `FTIMER_USE_MPI=ON` configure requires that the active `mpi_f08` path compile the `MPI_Type_match_size` and `MPI_ERRORS_RETURN` calls used for datatype validation
- MPI summary reductions select MPI datatypes with `MPI_Type_match_size` for the actual `real(wp)` and `integer(int64)` storage sizes before reducing those buffers. If that validation API is present but the active MPI implementation cannot provide matching datatypes at runtime, `mpi_summary()` temporarily requests MPI error returns for the datatype lookup, fails with `FTIMER_ERR_UNKNOWN`, and leaves the MPI result empty instead of reducing through a mismatched fixed datatype.
- Hash-based timer-descriptor preflight before the reduction phase
- The strict MPI preflight compares rank-local descriptor hashes against a rank-0 reference hash, then reduces a mismatch flag across the communicator. Successful summaries do not allgather every rank's hashes or exchange exact descriptor strings.
- Extra timers, missing timers, renamed timers, and hierarchy/context mismatches fail the MPI summary with `FTIMER_ERR_MPI_INCON`; they do not fall back to a local summary object through the MPI API
- Rank-conditional timer reductions are not supported by the strict `mpi_summary()` API. Sparse/union MPI summaries are available through the separate opt-in `mpi_union_summary()` / `ftimer_mpi_union_summary()` API and `ftimer_mpi_union_summary_t` result model. See [`docs/mpi-sparse-summary-decision.md`](mpi-sparse-summary-decision.md).
- When that descriptor preflight fails inside one communicator, the omitted-`ierr` diagnostic reports the disagreeing communicator-local ranks when possible
- MPI descriptor matching is based on the local summary tree shape and names, not on raw local `node_id` values
- The MPI descriptor preflight materializes deterministic length-prefixed path strings at summary time so names that differ only after the legacy 64-character threshold remain distinguishable. This is outside the start/stop hot path, but its memory and sort cost scales with summary entry count and encoded path length for very large timer trees.
- Mismatched communicator choices across would-be participants are unsupported; this API has no safe cross-communicator rendezvous to detect that misuse without risking the same MPI deadlock it is trying to avoid

### Unsupported communicator mismatch example

Suppose ranks 0-1 initialize a timer with one communicator split and later call `mpi_summary()`, while ranks 2-3 reach `mpi_summary()` through a different communicator choice. That is unsupported misuse.

This is not like descriptor inconsistency within one communicator, where every participant can still enter the same collective and the library can fail the MPI summary cleanly after a preflight mismatch. Once ranks have already diverged onto different communicators, `mpi_summary()` has no safe second rendezvous it can use to discover the mistake without risking the same deadlock it is trying to avoid. The practical failure mode is a hang, not `FTIMER_ERR_MPI_INCON`.

The supported pattern is simple: capture one communicator consistently at `init`, then have that same participant set enter `mpi_summary()` together.

### MPI lifecycle and communicator ownership

In `FTIMER_USE_MPI=ON` builds, the build-default clock calls `MPI_Wtime()`
and the MPI summary/report entry points use MPI collectives. The supported
runtime lifetime is therefore after `MPI_Init` and before `MPI_Finalize`.
Calling MPI-enabled fTimer before initialization or after finalization is
outside the current contract. There is not currently a separate
all-entry-point runtime guard for that misuse.

The communicator captured by `init(comm=...)` is a borrowed handle. fTimer does
not call `MPI_Comm_dup`, take ownership, or call `MPI_Comm_free` for that
communicator. Applications that split `MPI_COMM_WORLD` should keep each
subcommunicator alive until every fTimer operation that may consult it is done:
strict or sparse MPI summaries, MPI report writers, `finalize()`, or an
`init()` call that reinitializes the same timer object/default instance.

## MPI Summary Contract

`mpi_summary()` returns a distinct `ftimer_mpi_summary_t` instead of reusing the local `ftimer_summary_t` shape.

- `ftimer_mpi_summary_t` contains communicator-wide totals (`min_total_time`, `avg_total_time`, `max_total_time`, `min_total_time_rank`, `max_total_time_rank`, `total_time_imbalance`) plus per-entry communicator-wide statistics (`min_*`, `avg_*`, `max_*`) for inclusive time, self time, call count, and `% Total`. `min_call_count` and `max_call_count` are `integer(int64)` fields; `avg_call_count` remains `real(wp)`. MPI call-count averages avoid integer-sum overflow by reducing exact `integer(int64)` extrema first, then averaging nonnegative deltas from the exact minimum count. The final average is clamped to the representable `real(wp)` conversions of the exact min/max counts. Because `real(wp)` cannot represent every signed-64-bit integer exactly, a near-limit average may differ from the exact integer average by representable real rounding.
- MPI summary entries also expose `min_inclusive_time_rank` and `max_inclusive_time_rank` as communicator-local ranks for the inclusive-time extrema; ties resolve to the lowest rank that attains the extremum.
- Successful `mpi_summary()` calls populate the same global MPI result on every participating rank.
- `ftimer_mpi_summary_t` entries retain `name`, `depth`, `node_id`, and `parent_id`, so MPI summaries keep the explicit-tree data model instead of collapsing to flat rows.
- The MPI summary tree order is canonical across ranks. It does not depend on the local timer creation order on one chosen rank.
- `mpi_summary()` does not return local fallback data on errors. If the caller needs local data after an MPI-disabled or MPI-error path, it must call `get_summary()` separately.
- This datatype selection remains the portability guard for the current `mpi_f08` implementation and preserves the reduction-datatype work completed before the interface migration.

## Sparse/Union MPI Summary Contract

`mpi_union_summary()` is the explicit opt-in path reserved for rank-conditional timers. It is a separate API from strict `mpi_summary()`, not a mode argument, so existing strict calls cannot silently relax descriptor consistency. The procedural wrapper is `ftimer_mpi_union_summary()`.

- The sparse result type is `ftimer_mpi_union_summary_t`, with `ftimer_mpi_union_summary_entry_t` entries. It does not reuse or extend `ftimer_mpi_summary_t`, whose semantics remain strict identical-tree semantics.
- Top-level communicator total-time fields remain all-rank fields because every rank contributes a local summary window.
- Per-entry `participating_rank_count` records how many communicator ranks materialized that descriptor. Missing rank count is derived as `num_ranks - participating_rank_count` and is not stored redundantly.
- Descriptors are materialized from the local summary emitted on each rank. Lookup-only timer definitions do not count as present unless a future issue adds a first-class registration contract.
- A materialized present zero-call entry is participating and contributes zero calls plus its recorded time values to participating-rank statistics. An absent rank contributes only to the derived missing-rank count.
- Entry min/avg/max time, call-count, percent, and imbalance fields are defined over participating ranks only. Absent ranks are not zero-filled. Sparse `min_call_count` and `max_call_count` are `integer(int64)` fields; `avg_call_count` remains `real(wp)` and follows the same conservative very-large-count averaging rule as strict MPI summaries.
- No all-rank zero-filled or amortized entry fields are part of the initial result model. If such a view is added later, it must be explicitly named as all-rank or amortized.
- The sparse API keeps the same init-captured communicator model as strict MPI summaries. The public communicator path is `mpi_f08` `type(MPI_Comm)`.
- Sparse descriptor union construction exchanges per-rank descriptor counts, exact descriptor lengths, and a packed character payload. The character exchange scales with the sum of materialized encoded descriptor lengths across ranks, not with `num_ranks * max_descriptor_count * max_descriptor_length`.
- Remaining sparse-summary scale limits are still explicit: each rank materializes and sorts its local encoded path descriptors at summary time, the packed exchange still gathers total communicator descriptor lengths and packed descriptor characters on every participant before deduplicating the canonical union, MPI descriptor counts/displacements and packed character counts must fit the default integer count type used by the current `mpi_f08` collectives, and the final union result plus per-entry reduction work arrays scale with the canonical union entry count.
- The current implementation builds the descriptor union and structured sparse result. Sparse text and CSV reports are available through explicit union report entry points. Sparse CSV uses a separate participation-aware schema rather than overloading strict MPI CSV rows.

## MPI Reporting Contract

- `print_mpi_summary()` and `write_mpi_summary()` are the first-class strict text reporting paths for `ftimer_mpi_summary_t`
- `write_mpi_summary_csv()` is the first-class machine-readable strict reporting path for `ftimer_mpi_summary_t`
- They are collective over the communicator captured by `init`, just like `mpi_summary()`
- They build the same global MPI summary object that `mpi_summary()` returns, so non-identical descriptor trees still fail with `FTIMER_ERR_MPI_INCON`
- They emit one communicator-level report from rank 0; non-root participants take part in the collective build and return the same final status without duplicating output
- Root output failures are synchronized to all participants as `FTIMER_ERR_IO`
- The default MPI text report is an abbreviated view of `ftimer_mpi_summary_t`, not a serialization of every structured field. It prints communicator totals plus per-entry min/avg/max inclusive time, inclusive-time extrema ranks, inclusive imbalance, average self time, average call count, and `Avg %`; use `mpi_summary()` directly for min/max self time, self imbalance, min/max call count, min/max rank-local `% Total`, and explicit `node_id`/`parent_id` tree links.
- The strict MPI CSV export uses CSV format version `2` with `summary_kind=mpi`. It emits summary and metadata rows plus one entry row per MPI summary entry, including explicit tree links and all reduced fields from `ftimer_mpi_summary_t`.
- In the MPI text report, `Avg %` is `avg_pct_time`: the arithmetic mean of each rank's local `% Total` for that timer. It is not recomputed as `100*avg_inclusive_time/avg_total_time`, because rank-local denominator differences are part of the reported statistic.
- `print_mpi_union_summary()` and `write_mpi_union_summary()` are the explicit sparse/union text reporting paths for `ftimer_mpi_union_summary_t`; the procedural wrappers are `ftimer_print_mpi_union_summary()` and `ftimer_write_mpi_union_summary()`.
- `write_mpi_union_summary_csv()` is the explicit sparse/union CSV reporting path for `ftimer_mpi_union_summary_t`; the procedural wrapper is `ftimer_write_mpi_union_summary_csv()`.
- Sparse union reports are collective over the init communicator, build the same participation-aware object as `mpi_union_summary()`, and emit one rank-0 artifact. They do not weaken `print_mpi_summary()`, `write_mpi_summary()`, or `write_mpi_summary_csv()`.
- In non-MPI builds, sparse union report APIs return `FTIMER_ERR_NOT_IMPLEMENTED` before formatting or writing output. File-output calls do not create or replace report files on that path.
- Sparse union reports print `Participating` and `Missing` columns for each entry. `Missing` is derived as `summary%num_ranks - participating_rank_count`.
- Sparse union per-entry min/avg/max, imbalance, average self time, average call count, and `Avg %` are over participating ranks only. Missing ranks are not zero-filled, and the report labels this explicitly.
- A descriptor is present for sparse reporting when it is materialized by that rank's local summary. A present zero-elapsed timer with a real start/stop contributes to `Participating` and call-count statistics; lookup-only names still are not a sparse registration contract.
- Sparse union CSV uses `format_version=1` and `summary_kind=mpi_union` in a dedicated header that is not append-compatible with the local/strict MPI CSV format-version-2 header. Entry rows include `participating_rank_count`, explicit `missing_rank_count`, tree links, and participating-rank statistic columns such as `min_participating_inclusive_time`, `avg_participating_self_time`, and `max_participating_call_count`. Participating call-count extrema are emitted as signed-64-bit decimal text.
- Sparse union CSV does not emit all-rank zero-filled or amortized entry statistics. If such a view is added later, its columns must be explicitly named as all-rank or amortized.

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
- The CMake option is the source-level switch; global OpenMP compiler flags alone do not enable these guards when `FTIMER_USE_OPENMP=OFF`
- This is a narrow master-thread-only carve-out for bracketing a parallel region as a whole; it is not general hybrid MPI+OpenMP timing support
- The implemented model is master-thread-only timing; the current implementation does not make `fTimer` generally thread-safe
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
