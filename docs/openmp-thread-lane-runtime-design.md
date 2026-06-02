> **When to read this:** When implementing or reviewing the opt-in OpenMP
> runtime model for true worker-thread timing under umbrella issue #237.

# OpenMP Thread-Lane Runtime Model

Issue #239 defines the runtime ownership and aggregation model that should sit
behind the opt-in API direction from #238. This document is a runtime design
contract only. It does not add public Fortran symbols, per-thread stacks,
OpenMP summaries, MPI+OpenMP reductions, or new behavior to the current
`ftimer_t` compatibility mode.

## Decision

The first true OpenMP timing implementation should use independent lane-owned
runtime state behind the future `ftimer_openmp_t` object:

- one serial lane for calls made outside an OpenMP parallel region;
- one lane per OpenMP thread in a level-1 parallel team;
- one strict nesting stack per lane;
- per-lane timer/context statistics keyed by a shared immutable timer catalog;
- summary/reset/finalize merge points that scan all lanes outside parallel
  regions;
- no current `ftimer_t` or procedural default-instance participation.

The current `FTIMER_USE_OPENMP=ON` master-thread-only behavior remains the
compatibility mode for existing APIs. A build option alone must not route
current `ftimer_t` calls into this lane runtime.

## Runtime State Ownership

The future `ftimer_openmp_t` should separate shared, mostly read-only metadata
from hot per-lane state.

Object-level state:

- initialization flag, mismatch mode, and lifecycle state;
- clock pointer and summary-window timestamps;
- optional MPI communicator capture for later hybrid work;
- an append-only timer catalog mapping public timer ids to validated names;
- configuration such as maximum lanes, expected timer count, expected stack
  depth, dynamic-registration policy, and diagnostic capacity;
- bounded aggregate diagnostic counters for worker calls without `ierr`.

Lane-level state:

- lane identity and participation flag;
- lane-local `ftimer_call_stack_t`, using global timer ids in stack entries;
- lane-local segment/context tables, keyed by the shared timer id;
- lane-local inclusive time, start time, running flag, and call count arrays;
- lane-local diagnostic buffer and overflow count;
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

`config%max_lanes` should bound the allocated lane table. The default can be
derived from `omp_get_max_threads()` at `init`, but callers that use runtime
thread-count changes should pass an explicit capacity. A call from a team
thread whose computed lane id exceeds the configured capacity must return an
error and leave state unchanged.

## Valid Operations

Lifecycle and configuration calls are valid only from serial context, with no
active timers on any lane:

- `init`
- `finalize`
- `reset`
- clock configuration
- timer registration intended to avoid hot-path name lookups
- summary/report construction

Timing calls are valid from serial context and from level-1 parallel teams:

- `start_id`
- `stop_id`
- `start`
- `stop`
- `lookup`, if the implementation chooses to allow dynamic registration inside
  a parallel region

The first implementation should treat summary/report/reset/finalize/config
calls from inside an active parallel region as invalid. They must not attempt to
merge while worker lanes may still be mutating local state. A later issue may
add a narrower safe query API, but the first runtime model should keep merge
points outside threaded regions.

## Timer Registration

Hot-path synchronization depends on keeping shared timer-name registration out
of tight loops.

Recommended path:

1. Register timer names outside a parallel region with `lookup` or a future
   explicit registration helper.
2. Pass the returned ids into the parallel region.
3. Use `start_id` and `stop_id` on worker lanes.

For this path, `start_id` and `stop_id` need no global lock after `init` and
registration. They read the catalog, update only the current lane, and grow only
lane-local storage if the caller exceeded configured reserves.

Name-based `start` and `stop` may remain convenience calls, but they are not the
recommended hot path. If dynamic name creation is allowed inside a parallel
region, the shared catalog lookup/create operation must be protected by one
short critical section because catalog growth can reallocate name and id tables.
That critical section is acceptable for first-touch registration, not for
per-iteration timing in a hot loop.

Unknown-id `start_id` and `stop_id` calls should return an error. They must not
create unnamed catalog entries.

## Per-Lane Contexts

Context-sensitive accounting remains stack based, but the stack is lane-local.

On `start_id(timer_id)`:

1. Resolve `lane_id`.
2. Verify initialized state and timer id.
3. Find or create the lane-local context for `(timer_id, lane_stack_before_start)`.
4. Increment the lane-local call count.
5. Push `timer_id` and an activation token onto that lane stack.
6. Record the lane-local start timestamp.

On `stop_id(timer_id)`:

1. Resolve `lane_id`.
2. Verify initialized state and timer id.
3. Compare only the current lane's stack top.
4. If the top matches, capture one `now`, pop the lane stack, then look up the
   now-current parent context before accumulating elapsed time.
5. If the top does not match, apply the configured mismatch mode only within
   that lane.

The existing ordering rule still matters: stop must pop the lane stack before
looking up the context to accumulate into. Doing that lookup against the running
stack would create the same context-attribution bug as in the serial runtime.

## Mismatch And Repair Policy

Strict nesting is per lane.

- A stop on an empty lane stack is `FTIMER_ERR_MISMATCH`.
- A stop for a different timer id than the current lane stack top is
  `FTIMER_ERR_MISMATCH` in strict mode.
- Warn and repair modes may unwind/restart timers only on the current lane.
- Repair must capture one timestamp and use it for every unwound timer on that
  lane.
- Repair must not fire callbacks.
- Repair must never inspect, pop, stop, or restart another lane's stack.

Cross-thread start/stop pairing is therefore a mismatch, not a migration event.
The lane that started the timer remains active. Summary/reset/finalize must
detect that active lane and fail or report active-timer state according to the
future summary contract.

## Merge Points

Summary construction, reset, finalize, and future hybrid MPI summary/reduction
entry points are merge points. They should run only outside OpenMP parallel
regions.

At a merge point, the runtime should:

1. Capture one summary timestamp for the whole object.
2. Scan every configured lane.
3. Detect any lane with `call_stack%depth > 0`.
4. Materialize lane-local descriptors and statistics.
5. Merge or package those lane summaries according to #240.

#240 owns the public OpenMP summary result type. For #239, the internal merge
input must preserve enough information for #240 to define correct semantics:

- lane id and participation;
- timer id and name;
- context path by timer ids;
- inclusive time, call count, running state, and start time;
- enough tree/link information to compute self time without crossing sibling
  or cousin boundaries.

`reset` and `finalize` must reject active lanes before clearing state. They must
not force-stop active worker timers or synthesize elapsed time silently.

Future MPI+OpenMP collectives must run the same active-lane scan before entering
any MPI collective. If any lane is active, the call must return an error on all
participants through a pre-collective status exchange rather than allowing some
ranks to enter reductions with incomplete lane state.

## Diagnostics And `ierr`

The #238 threaded error policy becomes concrete at the lane level:

- With `ierr` present, a call returns the status for the calling lane and writes
  no stderr.
- With `ierr` omitted from a worker timing call, the worker call stores a
  bounded lane-local diagnostic record and writes no stderr.
- Serial lifecycle or merge-point calls may emit one deterministic aggregate
  stderr diagnostic for queued worker diagnostics when their own `ierr` is
  omitted.
- Each lane records diagnostic overflow counts so repeated worker failures do
  not allocate unbounded memory.

Diagnostics should record at least lane id, status code, operation kind, and a
short message. They should not store arbitrarily long user timer names on every
failure; use catalog ids where possible.

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
- no MPI calls;
- no stderr writes;
- no callback calls;
- one clock read per start and one clock read per successful stop;
- lane-local context lookup and lane-local stack mutation only.

The remaining costs are lane-local hash/context lookup, possible lane-local
array growth, and the clock call. To keep those costs bounded in hot loops, the
config object should offer reservations for expected timers, contexts, and stack
depth. If a lane exceeds those reservations, lane-local allocation is allowed
but should be documented as a first-touch or growth cost, not the steady-state
hot path.

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

#243 should measure the steady-state `start_id`/`stop_id` overhead after
pre-registration and after lane/context reserves are warmed.

## Interaction With Later Child Issues

- #240 defines the public OpenMP summary type, self-time boundaries, wall-clock
  envelope fields, summed lane work, lane participation, and report/CSV shape.
- #241 defines MPI+OpenMP reductions over the #240 result shape without
  changing current strict or sparse MPI APIs by accident.
- #243 supplies deterministic mock-clock tests, targeted OpenMP worker tests,
  nested/task rejection tests, active-lane lifecycle tests, and overhead
  measurements.
- #242 updates examples and user-facing docs after #239 and #240 provide enough
  runtime and summary behavior for compile-checked examples.

## Non-Goals

- Changing current `ftimer_t` behavior.
- Changing the current procedural default instance.
- Changing current OpenMP guard tests.
- Adding OpenMP summary/result public types in this issue.
- Adding MPI+OpenMP reductions in this issue.
- Supporting nested OpenMP teams or OpenMP task migration.
- Making callbacks from worker timing calls.
- Treating catalog locks in name-based `start` as the recommended hot path.

## Validation For This Design

This document defines the runtime model without adding public symbols or
changing runtime behavior. Validation for this design-only step is Markdown and
diff checking. The first implementation PR for this model must add compiling
OpenMP tests and overhead measurements before claiming runtime support.
