# First-Hour Timing Mode Validation

Issue: #308
Date: 2026-06-09

## Method

Six concrete onboarding scenarios were read against the current README,
`docs/openmp-timing-modes.md`, CSV schema notes, and examples. Each row records
the section a representative reader would likely choose first, whether that path
selects the correct API family, and where the reader is likely to hesitate.

## Scenario Record

| Representative reader and scenario | First section chosen | Correct API choice | Hesitation observed |
| --- | --- | --- | --- |
| Serial application developer wants a final timing table and a CSV artifact for one process. | README "Quick Start", then "CSV Export". | `ftimer_init`, `ftimer_start`, `ftimer_stop`, `ftimer_get_summary`, and `ftimer_write_summary_csv`. | The README already says local summaries are live snapshots, but the first mode-selection paragraph did not make "stop all timers for a final report" part of the first choice. |
| MPI maintainer wants a communicator-level phase summary where every rank times the same named phase. | README "Supported Workflows", then `examples/mpi_example.F90`. | `ftimer_init(comm=...)` inside the MPI lifetime, stopped timers, then `ftimer_mpi_summary` or strict MPI text/CSV reports. | The reader has to connect "strict" with "same descriptor tree" and remember that fTimer does not insert barriers. |
| MPI user has rank-conditional setup work that exists only on rank 0. | README "Current Limitations And Contracts", then "CSV Export". | `ftimer_mpi_union_summary` / sparse MPI union report or CSV family. | The strict-vs-sparse decision is correct in the README, but the first-hour path requires jumping to limitations to learn that strict MPI rejects rank-conditional descriptors. |
| OpenMP user wants one wall-clock interval around a parallel loop. | README "Supported Workflows", then `docs/openmp-timing-modes.md` "Current Accepted Patterns". | Existing `ftimer` or `ftimer_core` calls outside the `!$omp parallel` block. | The user may still ask whether `FTIMER_USE_OPENMP=ON` means per-worker timing; the no-op worker caveat needs to stay visible at mode-choice time. |
| OpenMP user wants every worker lane to contribute timing data inside one level-1 team. | `docs/openmp-timing-modes.md` "Mode Summary", then `examples/openmp_worker_example.F90`. | `type(ftimer_openmp_t)`, pre-registered ids, `begin_parallel_region`, worker `start_id`/`stop_id`, `end_parallel_region`, then local OpenMP summary/report/CSV. | The correct path is clear once the user reaches the OpenMP guide, but stopped-run summaries versus local live snapshots is easy to miss from the README front door. |
| Hybrid MPI+OpenMP maintainer has one all-rank/all-lane phase and one rank/lane-conditional phase. | `docs/openmp-timing-modes.md` "Mode Summary", then `examples/mpi_openmp_example.F90`. | `ftimer_openmp_t%mpi_openmp_summary` for the all-rank/all-lane phase, and `ftimer_openmp_t%mpi_openmp_union_summary` for rank/lane-conditional participation. | The current docs are accurate, but the reader must compare strict and sparse hybrid report families plus dedicated CSV schemas before choosing. |

## Decision

A one-screen chooser is needed in the README. The existing detailed docs are
honest and should remain the source for lifecycle and contract caveats, but the
first README path should expose the three high-risk decisions before a user
chooses an example or API:

- OpenMP compatibility timing versus true worker timing.
- Strict MPI or strict MPI+OpenMP summaries versus sparse union summaries.
- Local live snapshots versus stopped-run OpenMP and hybrid summary families.

The chosen change is a compact README table that points each measurement goal to
the smallest appropriate mode, names the first API or report family, and keeps
the relevant caveat in the same row. This keeps onboarding simpler without
adding new modes, changing API behavior, or hiding measurement semantics.
