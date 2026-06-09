# CSV Schema Dictionary

This page is the compact field dictionary for fTimer CSV readers. It is meant
to help dashboard, parser, and archive consumers interpret the current CSV
families without scraping text reports.

## Decision

Issue #303 validates that fTimer needs this compact field dictionary plus tiny
parser-smoke fixtures. It does not need generated golden CSV fixtures in this
change, and it does not change CSV writer behavior, schema fields, append
validation, or sparse result models. The fixtures under
`tests/fixtures/csv-schema/` are reader aids for parser validation; they are not
generated-output compatibility fixtures.

The core rule is unchanged: missing sparse contributors are not zero-filled.
Sparse statistics are participation-only statistics. If an all-rank or
all-lane amortized view is ever added, it must use explicitly named fields in a
separate design change.

## Record Model

Each CSV file starts with a single header row followed by typed records.
Consumers should parse the file as standard CSV instead of splitting on commas.
Data records emitted by fTimer quote fields. Header rows are standard CSV too;
some families emit unquoted header fields and others emit quoted header fields.

Common record types:

| `record_type` | Meaning |
| --- | --- |
| `summary` | Run-level or communicator-level summary fields. |
| `metadata` | Caller-supplied `key` and `value` metadata. |
| `entry` | One aggregate timer descriptor row. |
| `rank` | Per-rank rows in strict and sparse MPI+OpenMP CSV families. |

Common field types:

| Field type | Interpretation |
| --- | --- |
| `*_time`, `*_inclusive_time`, `*_self_time`, `summary_window_time`, `timed_region_envelope_time` | Seconds. |
| `pct_time`, `*_pct_time` | Percent values on a 0 to 100 scale, not fractions. |
| `call_count`, `min_*_call_count`, `max_*_call_count` | Signed 64-bit decimal integer text where the structured field is `integer(int64)`. |
| `avg_*_call_count` | Real-valued average text. |
| `*_rank` | Communicator-local rank ids. |
| `*_count` | Counts of entries, ranks, lanes, or rank/lane samples as named. |
| `*_known`, `is_active`, `has_active_timers` | Logical text, currently `true` or `false`. |
| `start_date`, `end_date` | Timestamp strings from the summary writer; use timing fields for arithmetic. |
| `node_id`, `parent_id`, `depth`, `name`, `execution_domain` | Explicit tree identity and display fields for aggregate rows. |

## Schema Families

| Family | Writers | Signature | Record rows | Append compatibility |
| --- | --- | --- | --- | --- |
| Local and strict MPI | `write_summary_csv`, `ftimer_write_summary_csv`, `write_mpi_summary_csv`, `ftimer_write_mpi_summary_csv` | `format_version=2`, `summary_kind=local` or `summary_kind=mpi` | `summary`, `metadata`, `entry` | Same local/strict-MPI v2 header family. |
| Sparse MPI union | `write_mpi_union_summary_csv`, `ftimer_write_mpi_union_summary_csv` | `format_version=1`, `summary_kind=mpi_union` | `summary`, `metadata`, `entry` | Dedicated sparse MPI union header only. |
| Local OpenMP | `ftimer_openmp_t%write_openmp_summary_csv` | `format_version=1`, `summary_kind=openmp` | `summary`, `metadata`, `entry` | Dedicated local OpenMP header only. |
| Strict MPI+OpenMP | `ftimer_openmp_t%write_mpi_openmp_summary_csv` | `format_version=1`, `summary_kind=mpi_openmp` | `summary`, `metadata`, `rank`, `entry` | Dedicated strict hybrid header only. |
| Sparse MPI+OpenMP union | `ftimer_openmp_t%write_mpi_openmp_union_summary_csv` | `format_version=1`, `summary_kind=mpi_openmp_union`, `participation_policy=sparse_union` | `summary`, `metadata`, `rank`, `entry` | Dedicated sparse hybrid union header only. |

Appending to an existing non-empty CSV requires the exact header expected by
the API in use, well-formed CSV logical records with the header's field count,
recognized `summary_kind` and `record_type` combinations, and a newline at the
end of the current file. Append validation is a schema-shape and CSV-syntax
guard. It is not a semantic reparse of every numeric, logical, or timing field
already present. The no-behavior append-validation consolidation question is
tracked separately by #314.

## Local And Strict MPI Fields

The local and strict MPI writers share the same v2 header. Readers should route
each row by `summary_kind`.

Local rows:

- `summary_kind=local` `summary` rows populate `start_date`, `end_date`,
  `total_time`, `num_entries`, and `has_active_timers`.
- `summary_kind=local` `entry` rows populate `node_id`, `parent_id`, `depth`,
  `name`, `inclusive_time`, `self_time`, `call_count`, `avg_time`, `pct_time`,
  and `is_active`.
- Local summaries are live snapshots. If `has_active_timers=true` or an entry
  has `is_active=true`, the time fields include active work through the
  snapshot timestamp rather than a stopped-run final interval.
- Local `% Total` uses the local summary window `total_time` as its
  denominator.

Strict MPI rows:

- `summary_kind=mpi` `summary` rows populate `num_entries`, `num_ranks`,
  communicator-level total-time extrema and ranks, and
  `total_time_imbalance`.
- `summary_kind=mpi` `entry` rows populate explicit tree fields plus reduced
  `min_*`, `avg_*`, and `max_*` inclusive, self, call-count, and percent
  fields.
- Strict MPI requires identical descriptor trees across ranks. The CSV does not
  contain missing-rank participation fields because missing descriptors are an
  error for this family.
- MPI percent fields are based on each rank's local `% Total`. `avg_pct_time`
  is the arithmetic mean of rank-local percentages; it is not recomputed as
  `100 * avg_inclusive_time / avg_total_time`.

## Sparse MPI Union Fields

Sparse MPI union rows use `summary_kind=mpi_union`.

- `summary` rows keep communicator total-time fields as all-rank statistics
  because every rank contributes a local summary window.
- `entry` rows add `participating_rank_count` and `missing_rank_count`.
  `missing_rank_count` is `num_ranks - participating_rank_count`.
- Per-entry statistic fields are named with `participating`, for example
  `avg_participating_inclusive_time`,
  `max_participating_call_count`, and `avg_participating_pct_time`.
- The denominator for participating averages is `participating_rank_count`.
  Absent ranks do not contribute zero time, zero calls, or zero percent.
- A rank that materializes a descriptor with real zero elapsed time or zero
  calls participates with those zero values. A rank that does not materialize
  the descriptor is absent.

## Local OpenMP Fields

Local OpenMP rows use `summary_kind=openmp`.

- `summary_window_time` is the stopped-run object summary window.
- `timed_region_envelope_time` is wall-clock envelope time for timed OpenMP
  regions.
- `sum_lane_root_inclusive_time` and `sum_lane_self_time` are summed lane work
  fields. They can exceed wall-clock envelope time when multiple lanes
  participate.
- `configured_lane_capacity` is the configured serial-plus-worker lane
  capacity. It is not a denominator for missing work.
- `observed_participating_lane_count` is the number of lanes that participated
  in the stopped run.
- `entry` rows use `eligible_lane_count`, `participating_lane_count`,
  `missing_lane_count`, and `missing_lane_count_known` to describe lane
  participation. `avg_lane_*` fields divide by participating lanes, not by
  configured capacity or missing lanes.
- When one descriptor spans timed-region epochs with different OpenMP team
  sizes, `eligible_lane_count` is the maximum or union eligible lane count
  retained for that aggregate row. If `missing_lane_count_known=false`,
  `missing_lane_count` is schema-valid but not precise epoch-level absence.

## MPI+OpenMP Fields

Strict MPI+OpenMP rows use `summary_kind=mpi_openmp`.

- `summary` rows carry communicator-level extrema over rank OpenMP summary
  windows, timed-region envelopes, summed lane root work, and summed lane self
  work.
- `rank` rows carry each rank's summary-window, timed-region envelope, summed
  lane, configured capacity, and observed-participating-lane fields.
- `entry` rows aggregate participating rank/lane samples for each descriptor
  and `execution_domain`.
- Strict hybrid summaries reject descriptor, eligible-lane, and unknown
  missing-lane precision mismatches. Missing rank/lane samples are not
  zero-filled into strict output.

Sparse MPI+OpenMP union rows use `summary_kind=mpi_openmp_union` and
`participation_policy=sparse_union`.

- `summary` and `rank` rows keep the strict hybrid communicator and per-rank
  summary-window fields.
- `entry` rows add `participating_rank_count`, `missing_rank_count`,
  `eligible_rank_lane_sample_count`, `participating_rank_lane_sample_count`,
  `missing_rank_lane_sample_count`, and
  `missing_rank_lane_sample_count_known`.
- Per-entry statistic fields are named with `participating_lane`, for example
  `avg_participating_lane_inclusive_time`,
  `max_participating_lane_call_count`, and
  `avg_participating_lane_pct_time`.
- Participating-lane averages divide by
  `participating_rank_lane_sample_count`. Absent ranks and absent lanes do not
  contribute zero-valued samples.
- When mixed OpenMP epochs make missing-sample precision unavailable,
  `eligible_rank_lane_sample_count` remains an aggregate or maximum/union
  count and `missing_rank_lane_sample_count_known=false` means
  `missing_rank_lane_sample_count` must not be read as precise epoch-level
  absence.

## Reader-Aid Fixtures

The tiny CSV files under `tests/fixtures/csv-schema/` exercise the intended
reader interpretation:

- `local-active-reader-aid.csv` shows live active snapshot fields.
- `mpi-union-sparse-reader-aid.csv` shows rank participation without
  zero-filling the missing rank.
- `openmp-mixed-epoch-reader-aid.csv` shows a local OpenMP mixed-epoch row
  where missing lane precision is unknown.
- `mpi-openmp-union-mixed-epoch-reader-aid.csv` shows sparse hybrid
  rank/lane participation with unknown missing-sample precision.

These fixtures intentionally stay tiny. They are examples for parser smoke
tests and documentation review, not a new dashboard format or a replacement for
the writer behavior tests.
