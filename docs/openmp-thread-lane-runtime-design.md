> **When to read this:** When implementing or reviewing the opt-in OpenMP
> runtime model for true worker-thread timing under umbrella issue #237.

# OpenMP Thread-Lane Runtime Model

Issue #239 defines the runtime ownership and aggregation model that should sit
behind the opt-in API direction from #238. This document is a runtime design
contract only. Issue #268 adds the initial `ftimer_openmp` module and object
lifecycle/catalog surface, and #269 adds the first true worker timing runtime
with lane-local stacks. Issue #270 adds stopped-run local OpenMP summaries,
reports, and CSV output. MPI+OpenMP reductions and new behavior for the current
`ftimer_t` compatibility mode remain out of scope for this runtime model.

## Decision

The first true OpenMP timing implementation should use independent lane-owned
runtime state behind the current `ftimer_openmp_t` object:

- one serial lane for calls made outside an OpenMP parallel region;
- one lane per OpenMP thread in a level-1 parallel team;
- one explicit timed-region epoch for each worker-timed level-1 parallel
  region;
- one strict nesting stack per lane;
- per-lane timer/context statistics keyed by a shared immutable timer catalog;
- summary/reset/finalize merge points that scan all lanes outside parallel
  regions;
- no current `ftimer_t` or procedural default-instance participation.

The current `FTIMER_USE_OPENMP=ON` master-thread-only behavior remains the
compatibility mode for existing APIs. A build option alone must not route
current `ftimer_t` calls into this lane runtime.

## Runtime State Ownership

The true worker-timing `ftimer_openmp_t` runtime should separate shared,
mostly read-only metadata from hot per-lane state.

Object-level state:

- initialization flag and lifecycle state;
- optional clock pointer for test/validation injection and summary-window
  timestamps for future summaries;
- optional MPI communicator capture for later hybrid work;
- an append-only timer catalog mapping public timer ids to validated names;
- timed parallel-region epoch state, including whether a worker-timed region is
  open and the current epoch id;
- configuration for maximum lanes and bounded worker diagnostics;
- private reserve and warm-up policy for lane-local timers, contexts, and stack
  depth, unless future measurement work demonstrates that public tuning knobs
  are needed;
- bounded aggregate diagnostic counters for worker calls without `ierr`.

Lane-level state:

- lane identity and participation flag;
- lane-local `ftimer_call_stack_t`, using global timer ids and region epochs in
  stack entries;
- lane-local segment/context tables, keyed by the shared timer id;
- lane-local inclusive time, start time, running flag, and call count arrays;
- object-level bounded diagnostic counters, overflow count, and first status;
- no references to another lane's stack.

The shared catalog provides semantic identity. Lane state owns timing mutation.
This keeps `start_id` and `stop_id` from writing shared counters in the hot path
after timer ids are registered.

## Lane Identity

The first model should define lanes by OpenMP execution context, not by a hidden
global thread-local default:

- `lane_id = 0` is the serial lane used when the caller is not inside an OpenMP
  parallel region.
- `lane_id = 1 + omp_get_thread_num()` is used inside a level-1 OpenMP parallel
  region.
- The level-1 team master uses its team lane, not the serial lane. This avoids
  implicit inheritance from timers that bracket the parallel region outside the
  team.
- If a timer is started on the serial lane and stopped inside a parallel team,
  the stop observes the team lane stack and reports a mismatch without mutating
  the serial lane.
- If a worker lane starts a timer and another lane stops it, the stop lane
  reports a mismatch and the original lane remains active until the matching
  lane stops or the runtime reports active timers at a merge point.

`config%max_lanes` is a lane count that includes the serial lane. Valid lane
ids are `0 <= lane_id < config%max_lanes`. The default must therefore be at
least `1 + omp_get_max_threads()` at `init`, so an `N`-thread level-1 team has
capacity for lane ids `0..N`. Callers that use runtime thread-count changes
should pass an explicit capacity. A call from a team thread whose computed lane
id is outside the configured table must return an error and leave state
unchanged.

Worker timing intervals must be contained within one explicit timed level-1
parallel-region epoch and must be stopped by the same lane before that region
ends. The first implementation should provide a small serial-context region
guard or begin/end helper that opens a monotonically increasing epoch before
the `!$omp parallel` region and closes it after the region. Worker stack entries
record that epoch. A later parallel region reusing the same
`omp_get_thread_num()` value is not a valid way to complete an earlier worker
timer because the top stack entry's epoch will not match the currently open
epoch.

Opening a new timed region must fail if any lane already has an active stack.
Closing a timed region must scan the worker lanes for active stacks before
retiring the current epoch. If active stacks remain, the close returns an error
and leaves the timed-region token open so the caller can re-enter the same
OpenMP team shape, stop the forgotten lane activation, and retry the close.
Only a successful close retires the epoch. A later worker stop without an open
epoch, with a newer epoch than the stack entry, or through a stale or foreign
region token must not close the earlier activation.

## Valid Operations

Current lifecycle and catalog calls are valid only from serial context, with no
active timers on any lane:

- `init`
- `finalize`
- `reset`
- opening or closing a timed parallel-region epoch
- timer registration with `register_timer`
- timer id lookup with `lookup_timer`

Current timing calls are valid from serial context and from level-1 parallel
teams:

- `start_id`
- `stop_id`

Stopped-run local summary/report construction is now part of the current
`ftimer_openmp_t` public runtime surface. OpenMP object clock configuration and
name-based worker `start`/`stop` convenience calls remain future API work.

Worker timing calls inside a level-1 team are valid only while a timed
parallel-region epoch is open for that object. A worker timing call without an
open epoch returns an invalid-operation status and leaves state unchanged.

The first implementation should treat summary/report/reset/finalize/config
calls from inside an active parallel region as invalid. They must not attempt to
merge while worker lanes may still be mutating local state. A later issue may
add a narrower safe query API, but the first runtime model should keep merge
points outside threaded regions.

## Timer Registration

Hot-path synchronization depends on keeping shared timer-name registration out
of tight loops.

Recommended path:

1. Register timer names outside a parallel region with `register_timer`; use
   `lookup_timer` only to recover an existing id by name.
2. Warm or reserve lane-local context storage for the intended timing patterns
   when the implementation provides such a helper.
3. Open a timed parallel-region epoch in serial context.
4. Pass the returned ids into the parallel region.
5. Use `start_id` and `stop_id` on worker lanes.
6. Close the timed region after the parallel region ends.

For this path, `start_id` and `stop_id` need no global lock after `init` and
serial registration/warm-up. They read the catalog and update only the current
lane. Any lane-local context creation or array growth is cold first-touch work,
not the warmed steady-state hot path.

Name-based `start` and `stop` may remain convenience calls, but they are not the
recommended hot path. The first implementation should make catalog mutation
serial-only: inside a parallel region, name-based calls may perform read-only
lookup of already-registered names or may be rejected outright. Unknown names
inside a parallel region should return an error and leave state unchanged.
Dynamic worker registration can be reconsidered later only if a future
implementation issue shows that the extra catalog-locking path is worth the
API, allocation, and test burden.

Unknown-id `start_id` and `stop_id` calls should return an error. They must not
create unnamed catalog entries.

## Per-Lane Contexts

Context-sensitive accounting remains stack based, but the stack is lane-local.

On `start_id(timer_id)`:

1. Resolve `lane_id`.
2. Resolve the active region epoch. Serial-lane calls use a serial epoch;
   worker-lane calls require an open timed parallel-region epoch.
3. Verify initialized state and timer id.
4. Find the warmed lane-local context for
   `(timer_id, lane_stack_before_start)`, or create it as an explicitly cold
   first-touch path before recording the start timestamp.
5. Increment the lane-local call count.
6. Push `timer_id` and the resolved epoch onto that lane stack.
7. Record the lane-local start timestamp.

On `stop_id(timer_id)`:

1. Resolve `lane_id`.
2. Resolve the active region epoch. Serial-lane calls use a serial epoch;
   worker-lane calls require an open timed parallel-region epoch.
3. Verify initialized state and timer id.
4. Compare only the current lane's stack top, including both timer id and epoch.
5. If the top matches, capture one `now`, pop the lane stack, then look up the
   now-current parent context before accumulating elapsed time.
6. If the top does not match, return a strict mismatch error and leave that
   lane's state unchanged.

The existing ordering rule still matters: stop must pop the lane stack before
looking up the context to accumulate into. Doing that lookup against the running
stack would create the same context-attribution bug as in the serial runtime.

## Mismatch And Repair Policy

Current #269 worker timing is strict-only and per lane.

- A stop on an empty lane stack is `FTIMER_ERR_MISMATCH`.
- A stop for a different timer id than the current lane stack top is
  `FTIMER_ERR_MISMATCH`.
- A worker stop for a matching timer id from a different timed-region epoch is
  `FTIMER_ERR_MISMATCH`.
- Mismatch errors leave the current lane's stack and accumulated time
  unchanged, so callers can recover with matching stops where possible.

Future warn/repair modes are not part of the current `ftimer_openmp_t` contract.
If a later issue adds them, they may unwind/restart timers only on the current
lane, must capture one timestamp for every unwound timer on that lane, must not
fire callbacks, and must never inspect, pop, stop, or restart another lane's
stack.

Cross-thread and cross-region start/stop pairing is therefore a mismatch, not a
migration event. The lane that started the timer remains active. Region close,
summary, reset, and finalize must detect that active lane and fail or report
active-timer state according to the future summary contract.

## Merge Points

Timed-region close, summary construction, reset, finalize, current strict
hybrid MPI summary/reduction entry points, and future sparse/union hybrid
entry points are merge points. They should run only outside OpenMP parallel
regions.

At a merge point, the runtime should:

1. Capture one summary timestamp for the whole object.
2. Scan every configured lane.
3. Detect any lane with `call_stack%depth > 0`.
4. Materialize lane-local descriptors and statistics.
5. Merge or package those lane summaries according to #240.

#240 owns the public OpenMP summary result type, recorded in
[`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md). For
#239, the internal merge input must preserve enough information for #240 to
define correct semantics:

- lane id and participation;
- timer id and name;
- context path by timer ids;
- inclusive time, call count, running state, and start time;
- enough tree/link information to compute self time without crossing sibling
  or cousin boundaries.

Timed-region close must return an error without retiring the current epoch if
active worker lanes remain, so callers can stop the forgotten worker activation
and retry the close. `reset` and `finalize` must reject active lanes before
clearing state. They must not force-stop active worker timers or synthesize
elapsed time silently.

Future MPI+OpenMP collectives must run the same active-lane scan before entering
any MPI collective. If any lane is active, the call must return an error on all
participants through a pre-collective status exchange rather than allowing some
ranks to enter reductions with incomplete lane state.

## Diagnostics And `ierr`

The #238 threaded error policy becomes concrete at the lane level:

- With `ierr` present, a call returns the status for the calling lane and writes
  no stderr.
- With `ierr` omitted from a rejected worker/object API call inside a parallel
  region, the call stores bounded aggregate diagnostic state on the timer object
  and writes no stderr.
- Serial lifecycle or merge-point calls may emit one deterministic aggregate
  stderr diagnostic for queued worker diagnostics when their own `ierr` is
  omitted.
- The object records diagnostic overflow counts so repeated worker failures do
  not allocate unbounded memory.

The current diagnostic payload is intentionally aggregate-only: retained count,
overflow count, and first status. A later explicit diagnostic-detail issue may
add lane id, operation kind, and short messages if users need that visibility.

## Clock And Callback Policy

The timer object's clock pointer is shared read-only during timing. Clock
configuration is valid only outside parallel regions and only while no lane has
recorded timing data that would make rebasing ambiguous.

Custom clock functions used by the OpenMP runtime must be reentrant and safe to
call from multiple lanes. Deterministic tests should use a mock clock model that
defines whether all lanes observe one shared time value or lane-specific time
streams.

The first true OpenMP runtime must not fire today's `ftimer_hook_proc` callback
from worker timing calls. That callback lacks lane identity and reentrancy
semantics. A future callback contract can be designed separately if worker
callback events become a product goal.

## Nested Parallel Regions

Nested OpenMP teams are explicitly deferred in the first implementation.

If a timing call is made from `omp_get_level() > 1`, the runtime should return a
not-supported or invalid-operation status and leave state unchanged. It should
record a bounded diagnostic when `ierr` is omitted.

This deferral includes the master thread of a nested team. Treating nested-team
masters as ordinary lane 0 or as the outer team lane would silently merge
different execution contexts and produce plausible but wrong summaries.

## OpenMP Tasks

OpenMP task timing is explicitly unsupported in the first implementation.

The thread-lane model records execution on the lane that executes the call. A
task that starts on one OpenMP thread and stops on another is therefore a
cross-thread mismatch. Supporting tasks later requires a separate task-handle
model with explicit ownership, migration, and summary semantics.

Untied tasks, task dependency tracing, and task graph reporting are non-goals
for this runtime model.

## Hot-Path Synchronization Bounds

After initialization and pre-registration, `start_id` and `stop_id` should have
these synchronization properties:

- no global locks;
- no writes to shared catalog state;
- no writes to another lane's state;
- no writes to region epoch state;
- no MPI calls;
- no stderr writes;
- no callback calls;
- one clock read per start and one clock read per successful stop;
- lane-local context lookup and lane-local stack mutation only.

The warmed steady-state path assumes names are registered and the relevant
lane-local contexts have either been reserved or touched once before the
measured loop. The current #269 implementation uses lane-local linear context
lookup plus the clock call; issue #277 tracks the context-indexing and
context-scaling benchmark work needed to reduce or quantify that cost. Lane-local
array growth is allowed only as a cold first-touch or growth path and must be
documented separately from steady-state timing cost.
Until a reserve API exists, users who need warmed hot-loop measurements should
pre-register ids and run an untimed dummy timed region that touches the same
lane/timer/context combinations before entering the measured loop.

The first public config surface should stay lean: `max_lanes` plus bounded
diagnostic policy are enough for correctness. Expected timer counts, context
counts, and stack-depth reserves should remain private implementation details,
or become public only after future measurement work shows that users need
direct control.

Name-based calls inside parallel regions are explicitly slower unless the
implementation can prove a lock-free read-only catalog lookup with no concurrent
mutation. The supported high-performance path is pre-register plus id timing.

## False Sharing And Allocation Risk

Lane state should be allocated so hot fields written by different lanes do not
share cache lines unnecessarily.

Implementation guidance:

- prefer separately allocated lane-state objects or padded lane records over a
  dense array of hot scalar counters;
- keep aggregate totals out of the worker hot path;
- avoid a shared active-counter increment/decrement on every start/stop unless
  measurements show it is cheaper than scanning lane depths at merge points;
- allocate lane-local segment/context arrays from per-lane storage;
- preserve catalog ids so merge-time descriptor construction does not need to
  compare timer names from every lane in the hot path.

The runtime implementation should measure
both cold first-touch overhead and warmed steady-state `start_id`/`stop_id`
overhead after pre-registration and lane/context warm-up, following the #243
validation plan. The benchmark harness carries initial rows for the explicit
`ftimer_openmp` serial-lane id path, timed-region open/close, and warmed worker
id path so future runtime changes have a baseline.

## Interaction With Later Child Issues

- #240 defines the public OpenMP summary type in
  [`docs/openmp-hybrid-summary-design.md`](openmp-hybrid-summary-design.md),
  including self-time boundaries, wall-clock envelope fields, summed lane work,
  lane participation, and report/CSV shape.
- #241 defines MPI+OpenMP reductions in
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md)
  over the #240 result shape without changing current strict or sparse MPI
  APIs by accident.
- #243 records the validation plan in
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md)
  and starts current MPI+OpenMP compatibility smoke coverage. Later
  implementation issues supply deterministic mock-clock tests, targeted OpenMP
  worker tests, nested/task rejection tests, active-lane lifecycle and
  region-epoch tests, and overhead measurements.
- #242 records the user-facing timing modes and migration guide in
  [`docs/openmp-timing-modes.md`](openmp-timing-modes.md). Later
  implementation issues should add compile-checked worker-timing examples after
  this runtime model and the summary surface become real public APIs.

## Non-Goals

- Changing current `ftimer_t` behavior.
- Changing the current procedural default instance.
- Changing current OpenMP guard tests.
- Adding OpenMP summary/result public types in this issue.
- Adding MPI+OpenMP reductions in this issue.
- Supporting nested OpenMP teams or OpenMP task migration.
- Making callbacks from worker timing calls.
- Adding dynamic worker name registration or treating name-based `start` as the
  recommended hot path.

## Validation For This Design

This document began as a design-only runtime model. Issue #269 landed the first
implementation slice: current `ftimer_openmp_t` lifecycle/catalog calls,
timed-region tokens, and id-first serial-lane / level-1 worker timing are real
public behavior. That implementation is covered by smoke tests, installed
consumer checks, and benchmark rows. Issue #270 extends that coverage to local
OpenMP summaries/reports/CSV, and issue #271 adds strict MPI+OpenMP rank/lane
summaries/reports/CSV. Sparse/union hybrid participation reductions remain
deferred to later issues.
