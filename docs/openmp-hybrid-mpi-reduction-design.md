> **When to read this:** When designing or implementing MPI+OpenMP summary
> reductions, hybrid report output, or validation for the explicit opt-in
> OpenMP timing API under umbrella issue #237.

# MPI+OpenMP Hybrid Reduction Model

Issue #241 defines the MPI reduction contract that should sit on top of the
opt-in API direction from #238, the thread-lane runtime model from #239, and
the OpenMP summary model from #240. It remains the design reference for current
strict and sparse union hybrid reductions.

Implementation status: #271 implements the strict MPI+OpenMP hybrid reduction
slice on `ftimer_openmp_t`. The shipped strict surface is
`mpi_openmp_summary`, `print_mpi_openmp_summary`,
`write_mpi_openmp_summary`, and `write_mpi_openmp_summary_csv`, with
`ftimer_mpi_openmp_summary_t` and related rank/entry types exported from
`ftimer_openmp`. The strict path requires identical descriptor and eligible-lane
participation across ranks and fails with `FTIMER_ERR_MPI_INCON` rather than
relaxing to sparse/union behavior. Sparse/union hybrid participation reductions
land in #272 as separate `mpi_openmp_union_summary`,
`print_mpi_openmp_union_summary`, `write_mpi_openmp_union_summary`, and
`write_mpi_openmp_union_summary_csv` entry points with
`ftimer_mpi_openmp_union_summary_t` and related rank/entry types.

## Decision

True MPI+OpenMP timing uses a new hybrid summary/result family behind
summary methods on `ftimer_openmp_t`:

- `timer%mpi_openmp_summary(summary, ierr=ierr)` as the strict structured
  summary entry point;
- `ftimer_mpi_openmp_summary_t` and related rank/entry types as the strict
  result family;
- `timer%mpi_openmp_union_summary(summary, ierr=ierr)` and
  `ftimer_mpi_openmp_union_summary_t` as the sparse union result family;
- explicit hybrid text and CSV writers over that result shape;
- strict-identical participant semantics for the current implementation;
- sparse/union hybrid participation as a separate additive policy and API, not
  a relaxation of the strict path.

The existing `mpi_summary()`, `mpi_union_summary()`, `ftimer_mpi_summary_t`,
`ftimer_mpi_union_summary_t`, strict MPI reports, sparse MPI reports, and
sparse MPI CSV schema remain unchanged. Hybrid MPI+OpenMP summaries must be
additive and opt-in.

## Current Compatibility Contract

Current `main` remains the source of truth for the implemented strict API.

- Serial timing through `use ftimer`, `type(ftimer_t)`, and `get_summary()`
  keeps its current local summary contract.
- Pure-MPI strict reductions keep the current `mpi_summary()` identical-tree
  descriptor preflight and `ftimer_mpi_summary_t` result type.
- Pure-MPI sparse reductions keep the current `mpi_union_summary()` descriptor
  union and `ftimer_mpi_union_summary_t` result type.
- Current MPI report and CSV entry points keep their current schemas.
- `FTIMER_USE_OPENMP=ON` keeps the current master-thread-only compatibility
  mode for `type(ftimer_t)` and procedural calls. Hybrid reductions are
  available only through the explicit `ftimer_openmp_t` object.
- The procedural default instance must not participate in true worker-thread
  timing or hybrid worker reductions.

## Recommended API Boundary

Hybrid summaries are entered through the current OpenMP-specific object, which
owns lane state:

```fortran
use ftimer_openmp, only: FTIMER_OPENMP_MODE_THREAD_LANES, &
                         ftimer_mpi_openmp_summary_t, &
                         ftimer_mpi_openmp_union_summary_t, &
                         ftimer_openmp_config_t, ftimer_openmp_t
use mpi_f08, only: MPI_Comm

type(ftimer_openmp_config_t) :: config
type(ftimer_openmp_t) :: timer
type(ftimer_mpi_openmp_summary_t) :: summary
type(ftimer_mpi_openmp_union_summary_t) :: union_summary
type(MPI_Comm) :: comm
integer :: ierr

config%mode = FTIMER_OPENMP_MODE_THREAD_LANES
call timer%init(config=config, comm=comm, ierr=ierr)

! Worker timing runs through explicit timed OpenMP region epochs.

call timer%mpi_openmp_summary(summary, ierr=ierr)
call timer%mpi_openmp_union_summary(union_summary, ierr=ierr)
call timer%finalize(ierr=ierr)
```

Sparse/union participation is additive and must not add positional mode
arguments to current `ftimer_t%init`, `ftimer_init`, `mpi_summary()`,
`mpi_union_summary()`, or the strict hybrid API signatures.

No `ftimer_mpi_openmp_summary()` procedural wrapper should be added to the
current `ftimer` default instance. If later ergonomics need procedural helpers,
future helper entry points should live in the current `ftimer_openmp` module and
take an explicit `type(ftimer_openmp_t)` object argument.

## Reduction Inputs And Preconditions

Hybrid reductions consume stopped local OpenMP summary state, not the current
rank-only local summary tree.

Some preconditions are not collectively recoverable. All intended participants
must call the hybrid MPI entry point from serial context, with an initialized
object, the same valid init-captured communicator, and the MPI runtime inside
the supported `MPI_Init` to `MPI_Finalize` lifetime. Calling from inside an
OpenMP parallel region, calling with an invalid communicator, or letting only a
subset of ranks enter the collective is outside the supported contract and may
hang like any divergent MPI collective. Implementations should reject a local
worker-thread call without entering MPI, but cannot make inconsistent
caller-side collective entry safe.

An uninitialized object has no captured caller-owned subcommunicator, so an
implementation can only diagnose mixed initialized/uninitialized entry
collectively when all callers are using the default `MPI_COMM_WORLD` rendezvous.
For explicit `comm=` usage, all ranks in that communicator must initialize the
same `ftimer_openmp_t` object before entering the strict hybrid summary family.

After those caller-side preconditions hold, every participant must complete a
pre-collective status phase before any descriptor hash, descriptor union, or
timing-data reduction:

1. Verify no timed OpenMP region epoch is still open.
2. Scan every configured lane for active stacks.
3. Exchange the local status over the init-captured communicator so all ranks
   return the same collective outcome.

If any rank has an active lane stack, every participant returns
`FTIMER_ERR_ACTIVE`, leaves the hybrid result empty, and does not enter
descriptor or timing-data reductions. If `ierr` is omitted, diagnostics should
be deterministic and aggregate, for example naming communicator-local ranks
with active lanes when that can be reported within the bounded diagnostic
policy. Worker timing calls themselves must not write unordered stderr output.

The preflight should inherit the current MPI safety principle: failures are
discovered collectively before a subset of ranks can continue into a later
collective with incompatible payloads.

## Participant Identity

The hybrid participant key is:

```text
(communicator-local rank, lane_id)
```

where `lane_id` is the #239 OpenMP lane id:

- `0` for serial-context timing outside OpenMP parallel regions;
- `1 + omp_get_thread_num()` inside a timed level-1 OpenMP team.

Rank identity is communicator-local and only meaningful inside the communicator
captured by `timer%init`. In MPI+OpenMP builds, `init(config=config,
ierr=ierr)` captures `MPI_COMM_WORLD` by default; `comm=` captures an explicit
caller-owned communicator. Lane identity is runtime-local and stable only
inside one initialized `ftimer_openmp_t` object. It is not an OS-thread
identity and is not stable across runs.

The first hybrid model does not include nested-team paths, OpenMP task ids,
device ids, accelerator queues, or hardware counter streams. A later nested
team or task model must extend the participant descriptor explicitly instead
of reinterpreting the level-1 lane id.

## Descriptor Identity

Hybrid descriptor identity should be staged so aggregate summaries and detail
rows do not accidentally reduce unrelated data together.

Aggregate descriptor identity should include:

- a descriptor schema version;
- the logical timer/context path, encoded from timer names plus parent path
  using the same length-prefixed path idea as current MPI descriptors;
- an execution domain such as `serial_lane` or `openmp_level1_team`.

The aggregate descriptor identity should not include raw local timer ids,
runtime array indices, summary-local `node_id` values, communicator ranks, or
lane ids. Those values are not stable semantic descriptors.

Rank/lane detail identity, when explicitly requested, should add the
communicator-local rank and lane id to the aggregate descriptor. That keeps the
default aggregate rows compact while giving validation and diagnostics a
precise participant row when they need one.

Strict validation should hash the canonical aggregate descriptor list plus
enough eligibility metadata to prove that every rank is reducing the same
rank/lane participant universe. Participation-aware union mode should exchange
the aggregate descriptor union plus per-rank eligibility and participation
counts. In both modes, serial-lane descriptors and worker-team descriptors must
remain distinguishable even if they use the same timer name.

Hybrid result ordering must be deterministic across all ranks. Canonical entry
order should come from sorted aggregate descriptor strings, not from local
creation order. `node_id` values are assigned from that canonical order and are
stable only within the produced result object. `parent_id` values are assigned
by canonical parent-descriptor lookup. If a non-root parent descriptor is
missing, summary construction should fail before exposing a structured result.

Future nested-team support should add a team-path component to the descriptor
schema before any reduction attempts to merge nested-team data.

## Participation Modes

The #271 surface is strict-identical. It is deliberately separate from current
pure-MPI `mpi_summary()` / `mpi_union_summary()` behavior and from the sparse
union hybrid participation surface added by #272.

### Strict Validation Semantics

Strict validation is the current public hybrid policy. It requires:

- identical aggregate descriptor lists on every rank after canonical sorting;
- identical execution-domain metadata for every descriptor;
- identical eligible lane id sets for every worker-team descriptor;
- no missing ranks for any descriptor;
- no missing eligible lanes within any participating rank.

Different OpenMP thread counts across ranks therefore fail strict validation
for worker-team descriptors. Rank-conditional timer paths, worker-only timers
on a subset of ranks, and lanes that skip a strict descriptor also fail. The
status is `FTIMER_ERR_MPI_INCON`, the result remains empty, and the
omitted-`ierr` diagnostic identifies disagreeing communicator-local ranks where
practical.

### Participation-Aware Union Policy

Participation-aware union is #272 behavior, not behavior in the strict hybrid
API.

It behaves like a rank/lane generalization of the current sparse MPI union
contract:

- The call is collective over the init-captured communicator.
- All ranks contribute communicator-level and rank-level summary-window fields.
- The canonical entry set is the union of aggregate descriptors materialized by
  any rank.
- A rank participates in an entry when at least one of its eligible lanes
  materializes that descriptor.
- A lane participates in an entry when that descriptor is materialized in that
  rank/lane local summary input.
- Missing ranks are derived from `num_ranks - participating_rank_count`.
- Missing lanes are derived only within participating ranks from that entry's
  eligible lane set, not from configured lane capacity. The default aggregate
  should report `missing_lane_count` only when the timed-region epochs
  contributing to that descriptor have a stable eligible-lane universe on that
  rank. If multiple epochs with different eligible sets are aggregated, expose
  eligible and participating counts and leave detailed missing-lane
  interpretation to epoch-aware or rank/lane detail output.
- Entry min/avg/max, call-count, percent, and imbalance fields are over
  participating rank/lane samples unless a field name explicitly says
  otherwise.
- Absent ranks and absent lanes are not zero-filled.
- A materialized present zero-time or zero-call descriptor participates and
  contributes real zero values.

Ranks may use different OpenMP team sizes in this policy. Different thread
counts become visible through eligible-lane and participating-lane counts, and
through missing-lane counts where the eligible-lane universe is unambiguous,
instead of causing a reduction failure.

This policy can represent rank-conditional work, uneven OpenMP
participation, and different per-rank thread counts. It must be exposed through
a separate additive API or policy and must not make `mpi_openmp_summary()`
silently relax strictness.

## Rank-Level Aggregation And Detail Staging

The first hybrid result should be aggregate-first with rank-level detail, not
full rank/lane descriptor rows by default.

Recommended retained levels:

1. Communicator-level fields over all ranks.
2. Rank-level OpenMP summary fields, one row per communicator rank.
3. Logical descriptor aggregate rows with rank/lane participation statistics.
4. Optional rank/lane descriptor detail rows only through an explicit detail or
   diagnostic path.

This staging preserves enough rank information to interpret hybrid imbalance
without making every routine result allocate `O(num_ranks * lane_count *
descriptor_count)` detail rows. Full rank/lane rows remain important for tests,
debugging, and adoption diagnostics, but they should be opt-in until future
measurement work demonstrates that always materializing them is worth the
memory and report burden.

## Result Type Expectations

`ftimer_mpi_openmp_summary_t` starts with a small durable payload. A successful
`mpi_openmp_summary()` call populates the same globally meaningful structured
result on every participating rank. Text and CSV file emission are
communicator-root artifacts, but the in-memory summary is not root-only data.

Recommended communicator-level fields:

- `num_ranks` and `num_entries`;
- min/avg/max rank `summary_window_time`;
- min/avg/max rank `timed_region_envelope_time`;
- min/avg/max rank `sum_lane_root_inclusive_time`;
- min/avg/max rank `sum_lane_self_time`;
- imbalance fields and extrema-rank attribution for those rank-level metrics.

It should also retain rank-level rows with:

- communicator-local rank;
- configured lane capacity;
- observed participating lane count;
- rank `summary_window_time`;
- rank `timed_region_envelope_time`;
- rank `sum_lane_root_inclusive_time`;
- rank `sum_lane_self_time`.

Entry rows should retain explicit tree links and participation semantics:

- `name`, `depth`, `node_id`, and `parent_id`;
- execution domain;
- `participating_rank_count` and derived missing-rank semantics;
- eligible and participating rank/lane sample counts;
- missing rank/lane sample counts paired with explicit known-state fields, for
  example `missing_rank_lane_sample_count_known`. The numeric missing count is
  valid only when the companion known field is true. When the eligible
  participant universe is ambiguous, the known field is false and readers must
  not interpret the numeric count as a real zero;
- summed participating-lane inclusive and self time;
- min/avg/max participating-lane inclusive and self time;
- min/max participating-lane call-count extrema as `integer(int64)`;
- participating-lane average call count as `real(wp)`;
- min/avg/max participating-lane percent-of-rank-summary-window fields plus
  imbalance fields.

Field names should make participant semantics visible. For example, use names
like `sum_participating_lane_inclusive_time` and
`avg_participating_lane_call_count`, not unqualified `inclusive_time` or
`avg_time`.

Full rank/lane descriptor detail rows remain outside the default strict result
shape. The aggregate fields above are the stable strict summary contract.

## Text Reports

Hybrid text reports should be communicator-root artifacts like current MPI
reports. Non-root ranks participate in the collective build and observe the
same final status without writing duplicate output.

Recommended sections:

- communicator summary fields for rank window time, timed-region envelope time,
  and summed lane work;
- a rank-level section with one row per communicator rank;
- a descriptor aggregate table with participating/missing ranks and
  eligible/participating rank/lane sample counts, plus missing counts only
  where the eligible participant universe is unambiguous. Ambiguous missing
  counts should be shown with an explicit unknown status rather than as `0`;
- optional rank/lane detail output only in an explicit detail mode.

The default text report may be abbreviated, but it must not hide participation
counts or label summed lane work as wall-clock time. Root output failures
should be synchronized to all ranks as `FTIMER_ERR_IO`, following the current
MPI report safety pattern.

## CSV Expectations

Hybrid CSV should use a dedicated schema, not the local/strict MPI
format-version-2 header and not the sparse MPI union header.

Recommended default record types:

- `record_type=summary` for communicator-level fields;
- `record_type=metadata` for caller metadata;
- `record_type=rank` for rank-level OpenMP summary fields;
- `record_type=entry` for descriptor aggregate rows.

An explicit detail CSV mode may add `record_type=rank_lane_entry` rows. The
default CSV should not require rank/lane detail rows.

CSV rows should use `summary_kind=mpi_openmp` and a hybrid-specific format
version. Appending to an existing CSV should require the exact hybrid header
for the chosen schema and should reject local, strict MPI, sparse MPI, and
older hybrid headers instead of mixing schemas silently.

Column names should make semantics visible:

- use `timed_region_envelope_time` for wall-clock region-envelope data;
- use `sum_lane_root_inclusive_time` for rank-level summed lane work;
- use `participating_rank_count` and `missing_rank_count` for rank
  participation;
- use `eligible_rank_lane_sample_count`,
  `participating_rank_lane_sample_count`, and
  `missing_rank_lane_sample_count` for rank/lane participation;
- include companion `*_known` columns for missing-count fields that can be
  ambiguous, such as `missing_rank_lane_sample_count_known`. When the known
  column is false, the corresponding numeric count column remains schema-valid
  but undefined and must not be read as zero;
- use `avg_participating_lane_*` names for averages over participating lanes.

## Error And Diagnostic Policy

Hybrid MPI entry points should follow current MPI and future OpenMP error
principles:

- With `ierr` present, return the collective status and write no stderr.
- With `ierr` omitted, write one deterministic aggregate diagnostic from a
  serial or communicator-root context, not unordered worker diagnostics.
- Do not return local fallback data on MPI-disabled, MPI-error, active-lane, or
  descriptor-inconsistency paths.
- In `FTIMER_USE_MPI=OFF` builds, hybrid MPI entry points return
  `FTIMER_ERR_NOT_IMPLEMENTED` and leave their result objects empty.
- Do not attempt MPI collectives from OpenMP worker threads. Calls made inside
  a parallel region should fail locally without MPI; inconsistent rank entry
  where other ranks enter the collective is caller misuse outside the supported
  contract.
- Do not insert automatic `MPI_Barrier` calls around timed user regions.
- Do not repair active or mismatched lane stacks during summary construction.

The exact diagnostic payload and overflow policy depend on #239's bounded
diagnostic storage and the validation plan introduced by #243, but the
implementation must not solve hybrid error noise by silently treating worker or
rank errors as success.

## Validation Expectations

The strict #271 implementation adds tests for:

- at least two MPI ranks and at least two OpenMP worker lanes per rank;
- all-rank/all-lane participation under the strict policy;
- strict-semantics validation coverage for different descriptor sets,
  different eligible lane sets, missing ranks, missing lanes, serial versus
  worker execution domains, and same timer names under different parent paths;
- active lane stacks before the collective, proving every rank returns
  `FTIMER_ERR_ACTIVE` without entering descriptor reductions;
- invalid calls from inside OpenMP parallel regions, proving the local worker
  path does not enter MPI and documenting that inconsistent rank entry is
  unsupported caller misuse;
- deterministic descriptor identity for same timer names under different parent
  paths and for serial versus worker execution domains;
- deterministic canonical entry order and `node_id`/`parent_id` assignment when
  local timer creation order differs across ranks;
- report and CSV output checks, including strict hybrid schema-append
  rejection;
- compatibility tests proving current `mpi_summary()`, `mpi_union_summary()`,
  and `FTIMER_USE_OPENMP=ON` master-thread-only behavior are unchanged.

Tests should use the injectable clock or an OpenMP-aware deterministic clock
model wherever possible. Sparse/union hybrid participation coverage should
exercise rank-conditional descriptors where some ranks are missing,
lane-conditional descriptors where some eligible lanes are missing within a
participating rank, different OpenMP team sizes across ranks under the
participation-aware policy, descriptor-union cost, rank-level materialization
cost, optional rank/lane detail cost, and warmed worker `start_id`/`stop_id`
overhead separately, following the validation plan introduced by #243.

## Rejected Alternatives

- **Extend `ftimer_mpi_summary_t` with lane fields.** The strict result type is
  already a rank-only identical-tree contract. Adding lanes there would change
  existing consumer meaning and hide a second participant dimension.
- **Extend `ftimer_mpi_union_summary_t` with lane fields.** The sparse result
  type is rank-participation specific. Hybrid summaries need to distinguish
  missing ranks from missing lanes inside participating ranks.
- **Relax strict hybrid summaries into sparse/union behavior automatically.**
  Strict hybrid summaries are useful precisely because they fail on missing
  ranks, missing lanes, and descriptor disagreement. Sparse/union hybrid
  participation needs its own additive API and tests so strict calls remain
  strict.
- **Publish detailed missing-lane semantics for mixed-epoch aggregates by
  default.** When one aggregate row combines epochs with different eligible
  lane sets, a precise missing-lane interpretation belongs in epoch-aware or
  rank/lane detail output rather than in an overconfident aggregate count.
- **Reduce full rank/lane rows by default.** Full detail is useful for
  validation, but default summaries should avoid unconditional
  `num_ranks * lane_count * descriptor_count` storage.
- **Use lane id as the aggregate descriptor key.** That would turn aggregate
  summaries into detail summaries and make default reports too large.
- **Use timer path only for descriptor identity.** Serial-lane and worker-team
  descriptors with the same names could be reduced together incorrectly.
- **Zero-fill missing ranks or lanes.** Absence and real zero work are distinct
  states and must remain distinguishable.
- **Add automatic MPI barriers.** fTimer records wall-clock intervals; callers
  own synchronization when they want phase-aligned measurements.
- **Add hybrid reductions to the procedural default instance.** The default
  instance is not the true OpenMP worker-timing object.

## Dependencies On Later Child Issues

- #239 provides the lane-owned runtime state, timed-region epoch model,
  all-lane active scan, and bounded diagnostics consumed by hybrid preflight.
- #240 provides the local OpenMP summary shape, self-time semantics, envelope
  fields, participation model, and optional lane detail input.
- #243 records the validation plan in
  [`docs/openmp-hybrid-validation-plan.md`](openmp-hybrid-validation-plan.md)
  and starts current installed-consumer checks for `mpi_f08` plus OpenMP.
  Issue #271 adds deterministic strict MPI+OpenMP validation, strict-semantics
  descriptor and participation tests, report/CSV output checks, and installed
  consumer coverage. Issue #272 adds sparse/union participation-aware test
  matrices for the initial public API; overhead measurements can expand as the
  API grows.
- #242 records the user-facing timing modes and migration guide in
  [`docs/openmp-timing-modes.md`](openmp-timing-modes.md). Hybrid examples
  should stay compile-checked against the runtime, summary, and reduction APIs
  that exist on current `main`.

## Non-Goals

- Implementing sparse/union MPI+OpenMP participation reductions as part of the
  strict #271 API.
- Adding hybrid reductions to the procedural default instance.
- Changing `mpi_summary()`, `mpi_union_summary()`, pure-MPI result types, or
  current MPI CSV/report schemas.
- Changing current `FTIMER_USE_OPENMP=ON` master-thread-only behavior.
- Adding automatic MPI barriers around timed regions.
- Supporting nested OpenMP teams, OpenMP task migration, accelerator/device
  timing, hardware counters, callback identity, or trace/timeline output.

## Validation

This document originally recorded the reduction contract before runtime changes.
The strict #271 implementation now validates the public hybrid API with
two-rank/two-lane MPI+OpenMP smoke coverage, active-lane and active-region
preflight failures, descriptor mismatch failures, rank/lane imbalance fields,
and strict hybrid report/CSV output. The sparse union #272 implementation adds
rank/lane-conditional descriptor coverage, active-lane preflight coverage, and
separate sparse hybrid report/CSV output.
