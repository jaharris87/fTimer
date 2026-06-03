> **When to read this:** When designing or implementing OpenMP or hybrid
> MPI+OpenMP summary objects, self-time semantics, reports, or CSV exports for
> the explicit opt-in OpenMP timing API under umbrella issue #237.

# OpenMP And Hybrid Summary Model

Issue #240 defines the summary and self-time contract that should sit between
the opt-in API direction from #238 and the thread-lane runtime model from #239.
This is a design contract only. It does not add public Fortran symbols, change
current report output, implement summary generation, or add MPI+OpenMP
reductions. Issue #268 adds the initial `ftimer_openmp` module and object
lifecycle/catalog surface, and #269 adds the first thread-lane runtime; the
summary/result APIs below remain future work.

## Decision

True OpenMP worker-thread timing should use new summary/result types and new
report/CSV entry points behind the current `ftimer_openmp_t` API.

Recommended future type family:

- `ftimer_openmp_summary_t` for local OpenMP aggregate summaries;
- `ftimer_openmp_summary_entry_t` for logical timer/context aggregate rows;
- optional `ftimer_openmp_lane_entry_t` detail records for explicit diagnostic
  or detail exports, not for the default aggregate summary path;
- `ftimer_mpi_openmp_summary_t` and related entry types for hybrid
  MPI+OpenMP reductions defined by #241 in
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md).

Recommended future entry points:

- `timer%get_openmp_summary(summary, ierr=ierr)` for local aggregate summaries;
- `timer%print_openmp_summary(...)`, `timer%write_openmp_summary(...)`, and
  `timer%write_openmp_summary_csv(...)` for local aggregate reports;
- `timer%mpi_openmp_summary(summary, ierr=ierr)` plus explicit hybrid text and
  CSV writers for MPI+OpenMP summaries.

Those names are proposed source shapes for later implementation issues, not
symbols available on current `main`.

Current `get_summary()`, `mpi_summary()`, `mpi_union_summary()`,
`ftimer_summary_t`, `ftimer_mpi_summary_t`, `ftimer_mpi_union_summary_t`, and
the local/strict/sparse CSV schemas remain unchanged. A build configured with
`FTIMER_USE_OPENMP=ON` must continue to expose the current master-thread-only
compatibility model through the existing APIs unless the caller opts into the
future OpenMP-specific API.

## Compatibility Contract

Existing consumers keep their current meaning:

- `get_summary()` returns the current local serial tree snapshot for
  `type(ftimer_t)`.
- `mpi_summary()` remains the strict identical-tree rank reduction over
  `ftimer_mpi_summary_t`.
- `mpi_union_summary()` remains the sparse rank-participation path over
  `ftimer_mpi_union_summary_t`.
- `print_summary()`, `write_summary()`, `write_summary_csv()`, strict MPI
  report writers, and sparse MPI union report writers keep their current text
  and CSV schemas.
- The procedural default instance must not participate in true worker-thread
  timing and therefore does not need an OpenMP summary object.

The future OpenMP summary family is an additive opt-in surface. It should not
extend `ftimer_summary_t` with lane fields because that would make current
serial snapshots appear to be thread-aware and would force downstream code to
handle fields that cannot be populated meaningfully for the existing runtime.
It should not extend `ftimer_mpi_summary_t` or `ftimer_mpi_union_summary_t`
because their rank-only fields are already semantically full.

## Participant Identity

The local OpenMP participant key is the `lane_id` defined by #239:

- `lane_id = 0` for serial-context calls outside OpenMP parallel regions;
- `lane_id = 1 + omp_get_thread_num()` inside a level-1 OpenMP team;
- no nested-team path, task id, device id, or OS thread id in the first model.

`lane_id` is stable only within one initialized `ftimer_openmp_t` object and its
configured lane capacity. It is not a portable identity for a physical thread
across runs.

Timed-region epoch ids are runtime diagnostics, not the primary participant
key. Summary objects may expose region or epoch metadata so active or failed
region-close diagnostics can point to the affected epoch, but aggregate timing
statistics are keyed by logical timer descriptor plus lane id. A later nested
team or task model must add an explicit participant descriptor rather than
reinterpreting the level-1 lane id.

For hybrid summaries, the participant key is
`(communicator-local rank, lane_id)` with the communicator captured at
`timer%init(config=config, comm=comm, ierr=ierr)`. The first hybrid result
should also preserve rank-level participation counts separately from lane-level
participation counts so "rank absent" and "lane absent on a participating rank"
remain distinguishable.

## Logical Tree And Lane Detail

The OpenMP summary should be aggregate-first:

1. A canonical logical tree of timer/context descriptors. Each descriptor keeps
   `name`, `depth`, `node_id`, and `parent_id` for report traversal and for
   matching the current structured-summary style.
2. Aggregate lane statistics attached to each descriptor. These rows expose
   participation, min/avg/max, sum, imbalance, and call-count fields without
   requiring every default summary object to materialize every lane row.

The canonical tree is the union of descriptors materialized by participating
lanes. It is not creation order from one chosen lane. Descriptor matching should
use the same path-oriented idea as MPI summaries: timer names plus their parent
context path, not raw runtime array indices and not summary-local node ids from
one lane.

Per-lane records are still useful for validation and diagnostics, but they
should be opt-in detail output in the first implementation. The default
structured summary and default CSV should stay aggregate-first so routine users
do not pay `O(descriptor_count * lane_count)` materialization and storage cost
unless they request lane detail. The detail path may be a separate result type,
an explicit `detail=.true.` option, or a diagnostic export chosen by the
implementation issue, but it must not weaken the aggregate participation
contract.

## Wall-Clock Envelope And Summed Work

The future summary must name wall-clock quantities separately from summed lane
work.

Recommended top-level local OpenMP fields:

- `summary_window_time`: elapsed wall-clock time from init/reset to the summary
  snapshot, matching the current local summary-window idea;
- `timed_region_envelope_time`: summed wall-clock duration of explicit timed
  OpenMP region epochs in the summary window;
- `sum_lane_root_inclusive_time`: total inclusive time summed over lane-local
  root descriptors only, so nested child descriptors do not double-count the
  top-level work total;
- `sum_lane_self_time`: total lane-local self time summed across all materialized
  descriptors;
- `configured_lane_capacity` and `observed_participating_lane_count`.

`timed_region_envelope_time` is wall-clock elapsed time. It is not divided by
or multiplied by the number of lanes. `sum_lane_root_inclusive_time` is the
work-like total for materialized root descriptors and can legitimately exceed
the wall-clock envelope when multiple lanes run at the same time. It must not
sum every descriptor's inclusive time, because doing that would double-count
nested parent/child intervals on one lane before any parallelism is involved.
`sum_lane_self_time` is the summed exclusive work represented by all
materialized descriptor rows; it is useful for checking self-time accounting,
but it may omit uninstrumented gaps between timers.

Top-level lane counts are diagnostics only. `configured_lane_capacity` is the
runtime storage limit from #239. `observed_participating_lane_count` is the
distinct lane ids that materialized at least one descriptor in the summary
window. Neither field defines global missing-lane semantics. Missing lanes are
defined per descriptor entry from that entry's eligible participant set.

Recommended per-entry aggregate fields:

- eligible, participating, and missing lane counts;
- summed lane inclusive time and summed lane self time;
- min/avg/max lane inclusive time over participating lanes;
- min/avg/max lane self time over participating lanes;
- min/avg/max lane call count, with integer extrema and a real-valued average;
- lane inclusive and self imbalance over participating lanes.

Per-entry aggregate fields must be named as lane aggregates. Do not call summed
lane work simply `inclusive_time`, and do not call a lane average simply
`avg_time` without a lane qualifier.

The first model should not expose a per-entry wall-clock interval union unless
a later implementation deliberately stores enough interval information to
compute it. The current summary model is an aggregate table, not a trace. A
plausible-looking interval union computed from only totals would be worse than
not exposing the field.

## Self-Time Semantics

Self time is computed per lane.

For one lane and one descriptor:

```text
lane self time = lane inclusive time - sum(lane direct-child inclusive times)
```

The direct children are the children that were actually materialized on that
same lane under that same parent context. Missing children on another lane do
not participate in the subtraction for this lane.

Aggregate OpenMP self-time fields are then derived from the lane-local self
values:

- `sum_lane_self_time = sum(lane self time over participating lanes)`;
- `avg_lane_self_time = average(lane self time over participating lanes)`;
- `min_lane_self_time` and `max_lane_self_time` over participating lanes;
- `lane_self_imbalance = max_lane_self_time / avg_lane_self_time`, following
  the current MPI imbalance convention when the average is nonzero.

Do not compute aggregate self time as:

```text
aggregate inclusive - sum(aggregate child inclusive)
```

That subtraction is meaningful for one strict stack. Across lanes it can become
misleading because parent and child participation can differ by lane and
because overlapping worker intervals are work totals, not one serial interval.

## Sparse And Missing Lane Participation

A lane participates in a descriptor when that descriptor is materialized in the
lane-local summary input. A registered timer name, reserved lane storage, or
pre-warmed capacity is not participation by itself.

Missing participation is derived from an eligible participant set, not from
configured capacity. `configured_lane_capacity` is a runtime capacity
diagnostic. It must not be used as the denominator for per-entry missing lanes.

Consequences:

- Missing lane count is derived as
  `eligible_lane_count - participating_lane_count` for local OpenMP summaries,
  or from the explicit rank/lane participation model for hybrid summaries.
- For a serial-context descriptor, the initial eligible set is lane 0 only. For
  a worker-region descriptor, the initial eligible set is the actual level-1
  team lanes captured for the timed-region epoch or epochs that contribute to
  that descriptor. Over-provisioned `config%max_lanes` capacity and the serial
  lane are not counted missing for worker-only descriptors merely because they
  exist.
- If one summary row combines multiple timed-region epochs with different team
  sizes, `eligible_lane_count` is the count of distinct lane ids that were
  eligible in at least one contributing epoch. If that union would hide an
  important epoch-level difference, the default aggregate row should avoid
  claiming a precise missing-lane interpretation and the implementation should
  expose epoch detail through the optional lane/detail diagnostics rather than
  overloading the aggregate row. Future result and CSV schemas should pair such
  aggregate missing-count fields with explicit known-state fields, for example
  `missing_lane_count_known`, so an ambiguous aggregate cannot be mistaken for
  a real zero missing count.
- Missing lanes are not zero-filled for per-entry min, max, average, call
  count, percent, or imbalance fields.
- A materialized zero-call or zero-time entry participates if the runtime emits
  it as a real lane-local descriptor. It contributes zero values where
  appropriate.
- If users later need an all-lane amortized view, that view must be explicitly
  named as all-lane or amortized and derived from the participation-aware data.

This mirrors the sparse MPI design: absence and real zero work are different
states, and the summary object must not hide that difference.

## Active Timer Representation

OpenMP summary construction is a merge point and should run outside OpenMP
parallel regions. It must not read lane state while worker lanes may still be
mutating it.

The first OpenMP summary implementation should be stopped-run-only. If any lane
has an active stack, `get_openmp_summary()` and OpenMP report/CSV writers should
return `FTIMER_ERR_ACTIVE`, leave the normal summary/report artifact empty, and
preserve bounded active-lane diagnostics on the timer object. Those diagnostics
should include lane id, descriptor identity, and timed-region epoch when
available.

This is intentionally stricter than the current local `get_summary()` live
snapshot contract for `type(ftimer_t)`. True worker timing has multiple mutable
lane stacks, and making active worker summaries a first-release feature would
add report semantics, CSV semantics, and elapsed-time edge cases before there is
a demonstrated user need. A later issue may add an explicit live diagnostic
snapshot path, but that path should be named and tested separately from final
OpenMP summaries.

`reset`, `finalize`, and timed-region lifecycle calls must not force-stop active
lane timers or synthesize completed work.

Hybrid MPI+OpenMP summaries should be stopped-run summaries only in the first
implementation. Before entering MPI reductions, every rank must detect whether
any lane is active and exchange that status so all participants return
`FTIMER_ERR_ACTIVE` rather than entering collectives with incomplete lane data.

## Hybrid MPI+OpenMP Shape

#241 owns the MPI reduction design in
[`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md),
and later implementation should reduce over the #240 result shape instead of
reusing current rank-only summaries.

The first hybrid result should preserve these levels:

- communicator summary fields over ranks;
- rank-level OpenMP envelope and lane-work fields;
- logical timer descriptor rows;
- participant statistics over rank/lane samples;
- explicit rank participation and lane participation counts.

Hybrid summaries should distinguish:

- rank wall-clock envelope extrema and averages;
- rank summed-lane-work extrema and averages;
- per-entry participating rank count;
- per-entry participating rank/lane sample count;
- missing ranks versus missing lanes within participating ranks.

Because hybrid OpenMP has no existing callers, #241 chooses one
participation-aware result that can represent rank and lane absence explicitly.
Strict identical-participant behavior is documented for tests and future
adopter-driven use, but should not become required first public policy unless
future implementation validation or a concrete adopter justifies the added API,
CSV, and test burden. Whatever implementation follows that design must not
weaken current `mpi_summary()` or `mpi_union_summary()` by accident.

## Text Reports

Default local OpenMP text reports should be explicit rather than pretending to
be the current serial table.

Recommended sections:

- a header with summary window time, timed-region envelope time, configured
  lane capacity, observed participating lanes, and summed lane root work;
- a descriptor aggregate table with participating/missing lanes, summed lane
  inclusive/self time, min/avg/max lane inclusive time, average lane self time,
  and call-count aggregate fields;
- an optional lane-detail section or detail mode that prints lane rows for each
  descriptor.

The default report may omit some structured fields for readability, just as the
current MPI text report is abbreviated, but it must not omit participation or
label summed lane work as wall time.

Hybrid text reports should be communicator-root artifacts like current MPI
reports. They should show rank-level envelope fields separately from lane-work
fields and should label participant counts at the rank and lane levels.

## CSV Expectations

OpenMP and hybrid CSV exports should use dedicated schemas, not the current
local/strict version-2 header and not the sparse MPI union header.

Recommended default local OpenMP CSV record types:

- `record_type=summary` for top-level window, envelope, configured-capacity, and
  observed-participation fields;
- `record_type=metadata` for caller metadata;
- `record_type=entry` for descriptor aggregate rows.

An explicit detail CSV mode or separate diagnostic export may add
`record_type=lane_entry` rows for per-lane descriptor data. The default CSV
should not require lane-entry rows.

Recommended hybrid CSV record types:

- `record_type=summary` for communicator-level fields;
- `record_type=rank` for rank-level envelope and summed-lane fields;
- `record_type=entry` for descriptor aggregate rows;
- `record_type=rank_lane_entry` for participant detail rows when exported.

CSV columns should include `summary_kind=openmp` or
`summary_kind=mpi_openmp` and an independent format version. Appending to an
existing CSV should require the exact header for the chosen OpenMP or hybrid
schema, following the current CSV append-safety principle.

OpenMP CSV field names should make semantics visible:

- use `timed_region_envelope_time`, not `total_time`, for region-envelope data;
- use `sum_lane_root_inclusive_time`, not `inclusive_time`, for top-level
  summed worker work;
- use `eligible_lane_count`, `participating_lane_count`, and
  `missing_lane_count` on entry rows;
- include companion `*_known` columns for any missing-count field that can be
  ambiguous in a mixed-epoch aggregate;
- use `avg_participating_lane_*` or similar labels for averages over
  participating lanes only.

## Validation Expectations For Implementation

The implementation issues that add these summaries should include deterministic
tests for:

- uneven lane participation where missing lanes are not zero-filled;
- over-provisioned lane capacity that must not inflate missing-lane counts;
- worker-only timers, all-lane timers, and serial-lane timers;
- per-lane context differences under the same timer name;
- nested timers where top-level summed root work and per-entry inclusive sums
  are not confused, and where aggregate self time would be wrong if computed
  after cross-lane aggregation;
- active worker timers, failed timed-region close diagnostics, and
  stopped-run-only OpenMP summary/report errors;
- report and CSV golden output for local OpenMP summaries;
- hybrid MPI+OpenMP reductions with differing rank/lane participation;
- compatibility tests proving existing `get_summary()`, `mpi_summary()`,
  `mpi_union_summary()`, and `FTIMER_USE_OPENMP=ON` master-thread-only behavior
  are unchanged.

Tests should use the injectable clock or an OpenMP-aware deterministic clock
model wherever possible. The implementation issue that first adds this summary
surface should measure the merge-time cost of descriptor unioning and
lane-detail materialization separately from hot-path `start_id`/`stop_id`
overhead, following the validation plan introduced by #243.

## Rejected Alternatives

- **Extend `ftimer_summary_t` with lane fields.** Existing serial consumers
  would inherit a shape that the current runtime cannot populate meaningfully.
- **Fold lanes into the current rank-only MPI summaries.** Rank fields and
  rank-local percent semantics are already defined. Adding lanes there would
  hide a second participant dimension.
- **Zero-fill missing lanes by default.** That makes absence look like real
  zero work and masks uneven participation bugs.
- **Derive missing lanes from configured capacity.** Capacity is a storage and
  validation limit, not the participant universe for one descriptor or epoch.
- **Compute aggregate self time from aggregate inclusive rows.** That is only
  safe for one strict stack. It becomes misleading when parent and child
  participation differ by lane.
- **Require lane-detail rows in every default summary and CSV.** Per-lane detail
  is valuable for diagnostics and validation, but unconditional detail output
  would add storage, report, and test burden before routine users need it.
- **Make text reports the primary contract.** The durable contract should be
  structured data and CSV. Text reports can stay human-facing and abbreviated.
- **Add trace or timeline output in this issue.** Interval traces may be useful
  later, especially for per-entry envelope unions, but #240 is a summary-table
  design.

## Dependencies On Later Child Issues

- #239 provides the lane-owned runtime state, timed-region epoch model,
  lane-local stacks, merge points, and diagnostic storage that this summary
  design consumes.
- #241 defines MPI+OpenMP reductions in
  [`docs/openmp-hybrid-mpi-reduction-design.md`](openmp-hybrid-mpi-reduction-design.md)
  over the OpenMP summary shape, including participation-aware union behavior,
  strict validation, descriptor identity, active-lane preflight, and
  report/CSV expectations.
- #243 records the validation plan in
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md)
  and starts current MPI+OpenMP compatibility smoke coverage. Later
  implementation issues must add deterministic validation, active-lane tests,
  report/CSV golden output, and overhead measurements.
- #242 records the user-facing timing modes and migration guide in
  [`docs/openmp-timing-modes.md`](openmp-timing-modes.md). Later
  implementation issues should add compile-checked OpenMP summary examples
  after runtime and summary APIs exist.

## Non-Goals

- Implementing OpenMP summary public types in #240.
- Changing current local, strict MPI, or sparse MPI result types.
- Changing current CSV schemas or text reports.
- Changing current `FTIMER_USE_OPENMP=ON` master-thread-only behavior.
- Adding MPI+OpenMP reductions before #241.
- Supporting nested OpenMP teams, OpenMP task migration, accelerator/device
  timing, hardware counters, callback identity, or trace/timeline output.

## Validation For This Design

This issue records the data-model contract without changing runtime behavior.
Validation for this design-only step is Markdown review and diff checking. No
Fortran build or pFUnit run is required unless a later change adds code,
examples, CMake, or tests.
