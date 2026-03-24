# Implementation TODO

The in-repo design reference for implementation is [docs/design.md](docs/design.md).

## Phase 1: Types + Clock

Foundation types and injectable clock — everything else depends on these. No tests yet (pFUnit tests come in Phase 2 alongside the core), but these modules must compile cleanly in both serial and MPI builds.

- [x] `src/ftimer_types.F90` — `wp` kind parameter, `FTIMER_NAME_LEN`, error code constants (`FTIMER_ERR_NOT_INIT`, `FTIMER_ERR_UNKNOWN`, `FTIMER_ERR_ACTIVE`, `FTIMER_ERR_MISMATCH`, `FTIMER_ERR_MPI_INCON`, `FTIMER_ERR_IO`), mismatch mode constants (`FTIMER_MISMATCH_STRICT`, `FTIMER_MISMATCH_WARN`, `FTIMER_MISMATCH_REPAIR`), event constants (`FTIMER_EVENT_START`, `FTIMER_EVENT_STOP`), `ftimer_metadata_t` type, `ftimer_summary_entry_t` type (with MPI fields defaulting to `-1.0_wp`), `ftimer_summary_t` type, `ftimer_call_stack_t` type (with `push`, `pop`, `top`, `equals`, `copy` procedures), `ftimer_context_list_t` type (with `find`, `add` procedures), `ftimer_segment_t` type, `ftimer_clock_func` abstract interface, `ftimer_hook_proc` abstract interface (depends on `iso_c_binding`)
- [x] `src/ftimer_clock.F90` — `ftimer_default_clock()` function using `system_clock` (double precision), `ftimer_mpi_clock()` function using `MPI_Wtime()` (guarded by `#ifdef FTIMER_USE_MPI`), `ftimer_date_string()` utility returning formatted date/time string
- [x] Verify: `cmake -B build && cmake --build build` compiles both modules (serial). `cmake -B build-mpi -DFTIMER_USE_MPI=ON && cmake --build build-mpi` compiles with MPI.

## Phase 2: Core Timer Class

The `ftimer_t` class with all timer operations. Write pFUnit tests FIRST for each behavior, then implement.

- [x] `src/ftimer_core.F90` — `ftimer_t` derived type with private components: `call_stack`, `segments(:)`, `num_segments`, `init_wtime`, `init_date`, `initialized`, `mismatch_mode`, MPI fields (guarded), `clock` procedure pointer, `on_event` procedure pointer, `user_data` c_ptr
- [x] `ftimer_t%init(...)` — Initialize timer. Accept optional `comm` (integer), `mismatch_mode`, `ierr`. Set clock to `ftimer_default_clock` (or `ftimer_mpi_clock` when MPI), record `init_wtime` and `init_date`.
- [x] `ftimer_t%finalize(...)` — Deallocate all. Warn/error if timers active. Force-stop all active timers when `ierr` absent.
- [x] `ftimer_t%start(name, ...)` — Lookup/create segment, find/create context for current call stack, push onto stack, record start_time, increment call_count, fire `on_event` if associated.
- [x] `ftimer_t%stop(name, ...)` — Lookup segment (don't create), verify top-of-stack match, pop stack, find context, accumulate time, fire `on_event`. On mismatch: dispatch to strict/warn/repair.
- [x] `ftimer_t%repair_mismatch(idx)` — Capture single `now`. Unwind stack to target. Accumulate times for unwound timers. Stop target. Restart unwound in reverse. Do NOT fire `on_event`.
- [x] `ftimer_t%start_id(id, ...)` / `ftimer_t%stop_id(id, ...)` — Fast-path by cached integer ID.
- [x] `ftimer_t%lookup(name, ...) -> id` — Get or create integer ID for a timer name.
- [x] `ftimer_t%reset(...)` — Zero times/counts, keep definitions. Error if timers active.
- [x] Private helper: `ftimer_t%wtime()` — Call `self%clock` if associated, else `ftimer_default_clock()`.
- [x] Private helper: `ftimer_t%find_or_create_segment(name) -> idx` — Linear search, grow array if new.
- [x] **Tests** (write BEFORE implementation):
  - `tests/test_basic.pf` — init/finalize, single start/stop, auto-creation, ID lookup, time accumulation with mock clock
  - `tests/test_nesting.pf` — 2-level nesting, deep nesting (10+), mismatch in all three modes
  - `tests/test_context.pf` — Same timer under different parents tracked separately
  - `tests/test_callcount.pf` — Single call, multiple calls, counts per context
  - `tests/test_reset.pf` — Reset zeros times/counts, preserves names; reset with active timers
  - `tests/test_edge_cases.pf` — Stop unknown, start before init, finalize with active, name length limits, ierr contract

## Phase 3: Summary Building

Structured summary data + text formatting. Depends on Phase 2.

- [x] `src/ftimer_summary.F90` — `build_summary()` subroutine: recursive tree walk building `ftimer_summary_t` from `ftimer_t` state. Compute inclusive time per (timer, context). Second pass: compute self_time = inclusive - sum(direct children).
- [x] Text formatting: `format_summary()` producing hierarchical indented table with columns: timer name, inclusive time, self time, call count, % of total. Metadata header lines from `ftimer_metadata_t` array.
- [x] `ftimer_t%get_summary(summary, ...)` — Call `build_summary()`, return structured data.
- [x] `ftimer_t%print_summary(...)` — Call `get_summary()` + `format_summary()`, write to stdout or specified unit. Accept optional `metadata` array.
- [x] `ftimer_t%write_summary(...)` — Write formatted summary to file (new or append mode). Return `FTIMER_ERR_IO` on failure.
- [x] **Tests**:
  - `tests/test_summary.pf` — `get_summary()` returns correct structured data (entry count, names, depths, inclusive times, call counts, percentages). Golden text output comparison for `print_summary()`. Metadata appears in header.
  - `tests/test_self_time.pf` — Parent(10s) containing child(7s) → parent self_time = 3s. Multiple children. Deeply nested.
  - `tests/test_file_output.pf` — Write to new file, append to existing, invalid path returns `FTIMER_ERR_IO`.
  - `tests/test_callbacks.pf` — `on_event` fires with correct args on normal start/stop. Repair does NOT fire callbacks.

## Phase 4: Procedural Convenience API

Default global instance + procedural wrappers. Thin layer over Phase 2-3.

- [x] `src/ftimer.F90` — Module-level default timer instance (`ftimer_default_instance`) with thin procedural wrappers: `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_print_summary`, `ftimer_write_summary`.
- [x] Verify: both `use ftimer` (procedural) and `use ftimer_core` (OOP only, no global state) work independently.
- [x] Update tests to verify procedural interface produces same results as OOP interface.

## Phase 5: MPI Support

Cross-rank summary with hash preflight. Depends on Phases 2-3.

- [x] `src/ftimer_mpi.F90` — Hash preflight: each rank hashes sorted canonical timer descriptor list, `MPI_Allgather` to compare. If mismatch, set `FTIMER_ERR_MPI_INCON`, fall back to local-only.
- [x] MPI reduce: `MPI_Reduce` for min/max/sum of each entry's inclusive_time. Compute avg = sum/nprocs, imbalance = max/avg. Populate `ftimer_summary_entry_t` MPI fields on root.
- [x] `ftimer_t%mpi_summary(...)` — Call hash preflight, then MPI reduce, then build summary. Set `has_mpi_data = .true.` on result.
- [x] `ftimer_mpi_summary` procedural wrapper in `ftimer.F90`.
- [x] **Tests** (`tests/mpi/`):
  - [x] `test_mpi_summary.pf` — min/max/avg/imbalance correctness with mock clock per rank
  - [x] `test_mpi_consistency.pf` — Consistent timers succeed; inconsistent detected, returns `FTIMER_ERR_MPI_INCON`

## Phase 6: OpenMP Guards

Master-thread-only timing. Light touch — guards only, not thread-local instances.

- [x] Add `!$omp master` / `!$omp end master` guards around all timer operations in `ftimer_core.F90`
- [x] Document OpenMP limitations in `docs/semantics.md`: master-thread-only, not thread-safe, non-master calls are no-ops
- [ ] Optional: `suppress_in_parallel` flag to skip timer calls within parallel regions

## Phase 7: Documentation + Examples

- [ ] `docs/semantics.md` — Full semantics reference: inclusive/exclusive time definitions, nesting rules, mismatch modes and their behavior, reset behavior, error contract (ierr vs stderr), MPI guarantees (hash preflight, comm handle compatibility with mpif.h and mpi_f08), OpenMP limitations, callback contract
- [ ] `examples/basic_usage.F90` — Simple start/stop/print_summary
- [ ] `examples/nested_timers.F90` — Multi-level nesting with golden expected output
- [ ] `examples/mpi_example.F90` — MPI summary with imbalance metrics
- [ ] `README.md` — Complete with identity statement, quick start, API reference, build instructions, example output

## Phase 8: Polish + CI Verification

- [ ] Run `fprettify` on all source files, fix any formatting issues
- [ ] Verify serial CI: `cmake -B build && cmake --build build && ctest --test-dir build`
- [ ] Verify MPI CI: `cmake -B build -DFTIMER_USE_MPI=ON && cmake --build build && ctest --test-dir build`
- [ ] Verify all examples run and produce expected output
- [ ] Final review: CLAUDE.md, README, docs/semantics.md all match implementation

## Verification

- [ ] All tests pass (`ctest --test-dir build --output-on-failure`)
- [ ] MPI tests pass (`ctest --test-dir build -L mpi`)
- [ ] Linter clean (`fprettify --diff src/*.F90`)
- [ ] CI green on all jobs
- [ ] README accurate and complete
