> **When to read this:** When deciding whether rank-conditional MPI timers should be summarized, or when implementing the sparse/union MPI follow-ups from issue #149. This is a design decision record, not the current `mpi_summary()` runtime contract.

# Sparse MPI Summary Decision

Issue #149 asked whether fTimer should support MPI summaries for timer descriptors that are present on only some ranks.

## Decision

Sparse/union MPI summaries are implemented as an explicit opt-in MPI summary path. The existing strict `mpi_summary()` contract stays unchanged: it requires identical descriptor trees on all participating ranks and returns `FTIMER_ERR_MPI_INCON` when timer descriptors differ.

Follow-up work is split into:

- #169: define the sparse MPI summary API and data model
- #170: implement the descriptor-union summary builder
- #171: add sparse MPI reporting, docs, and adoption tests

Issue #169 chooses the public shape for that follow-up:

- Sparse MPI summaries use a separate opt-in API: `mpi_union_summary()` on `type(ftimer_t)` and `ftimer_mpi_union_summary()` for the procedural default instance.
- Sparse MPI summaries use a distinct result type: `ftimer_mpi_union_summary_t` with `ftimer_mpi_union_summary_entry_t` entries. The strict `ftimer_mpi_summary_t` shape is not extended with sparse-only fields.
- #170 implements the descriptor-union builder for the structured result. `mpi_union_summary()` now preserves the same stopped-timer, communicator, datatype-validation, no-local-fallback, and `ierr`/stderr preconditions as the strict MPI summary path, then returns a participation-aware sparse result.

## Evidence

The current implementation is strict by construction:

- `src/ftimer_mpi.F90` builds canonical descriptor path strings, hashes the ordered descriptor list, compares those hashes against a rank-0 reference, and returns `FTIMER_ERR_MPI_INCON` before reductions when any rank differs.
- After the preflight, `src/ftimer_mpi.F90` reduces per-entry arrays by canonical index and divides averages by `nprocs`. That is correct only when every rank has the same descriptor set.
- `src/ftimer_summary.F90` only emits visible local contexts. A lookup-only timer definition with no recorded context is not enough, by itself, to appear in the current local summary.
- `src/ftimer_types.F90` has no per-entry participation or absence fields in `ftimer_mpi_summary_entry_t`, so the current result type cannot distinguish "timer absent on this rank" from "timer present with zero calls".
- `tests/mpi/test_mpi_consistency.pf` and `tests/mpi/test_mpi_consistency_4pe.pf` assert that extra timers, missing timers, renamed timers, hierarchy/context mismatches, and long-name descriptor mismatches fail cleanly with an empty MPI result.
- `docs/semantics.md` and `README.md` document the identical-tree requirement, no-barrier timing interpretation, and no local fallback on MPI summary errors.

Prior MPI cleanup work supports keeping the default strict path:

- #119 replaced the earlier hybrid local-plus-reduced result with a distinct `ftimer_mpi_summary_t` and first-class MPI report paths.
- #124 narrowed the MPI summary contract, added extrema-rank attribution, and improved descriptor mismatch diagnostics.
- #129 positioned fTimer around disciplined serial and pure-MPI timing with correctness-first contracts.

## Rationale

Rank-conditional work is common in MPI applications: I/O ranks, restart paths, optional diagnostics, boundary-only work, rank-role splits, and adaptive mesh levels are all legitimate places to time work on only a subset of ranks.

Rejecting non-identical descriptor trees is still the right default. It prevents silent wrong reductions when ranks accidentally create different timer trees or when array indices would otherwise align unrelated timers. A sparse mode is valuable only if it makes absence explicit and keeps the strict path available for users who want identical-tree validation.

## Sparse Semantics

The sparse path should keep these inherited MPI contracts:

- It is collective over the communicator captured by `init`.
- All ranks in that communicator must enter the call with fully stopped timers.
- It does not insert `MPI_Barrier` or any other synchronization around timed regions.
- It reduces rank-local intervals; callers own any synchronization needed to interpret a global phase.
- It does not return local fallback data on errors.

The sparse path should differ from strict `mpi_summary()` in these ways:

- It builds a canonical union of descriptor paths across ranks rather than requiring every local descriptor list to hash identically.
- The first sparse implementation should treat a rank as participating when the descriptor is materialized in that rank's local summary. Lookup-only timer definitions should remain outside the initial sparse presence model unless #169 deliberately adds a first-class registration contract.
- A rank participates in an entry when that descriptor is present according to the sparse reporting data model.
- `participating_rank_count` records how many ranks had the descriptor.
- Missing-rank count is a required semantic, but it does not need to be stored redundantly: `absent_rank_count = num_ranks - participating_rank_count`.
- A present zero-call entry, if the sparse data model materializes one, is still participating. It contributes zero calls and its recorded time values to participating-rank statistics.
- An absent rank does not participate in per-entry min, max, or participating-rank averages.
- `min_*`, `avg_*`, `max_*`, imbalance, call-count, and rank-local percent statistics in `ftimer_mpi_union_summary_entry_t` are defined over participating ranks only.
- Initial per-entry rank-attributed extrema should preserve parity with the current strict MPI result by covering inclusive-time extrema; additional rank-attributed extrema for self time, call count, or percent time should wait for a concrete consumer need.
- Communicator total-time fields remain all-rank fields because every rank has a local summary window even when some entries are sparse.

The first sparse implementation does not provide an implicit zero-filled compatibility mode. Zero filling makes absence too easy to confuse with real zero work. If an all-rank amortized view is added later, it should be explicitly named and derived from participation-aware data rather than replacing participating-rank statistics. No all-rank zero-filled fields are part of the current result type.

The sparse API follows the same `mpi_f08` primary contract as strict MPI summaries: communicator choice is captured at `init` as `type(MPI_Comm)` on the validated path, with legacy integer communicator capture remaining only as transitional compatibility until #187 removes it. No sparse API overload is added for per-call communicator selection, so #187 does not need to change the sparse summary entry point.

## Non-Goals

Issue #149 did not implement sparse summaries. It recorded the decision and created the split implementation issues.

The follow-up work should not weaken the existing descriptor preflight for `mpi_summary()`, change strict summary averages, add barriers, or require every future report format to expose every sparse field. Sparse text and CSV report output remain deferred to #171.
