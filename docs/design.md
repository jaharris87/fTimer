# fTimer: A Modern Fortran Wall-Clock Timing Library

> This document is a forward-looking design reference. Unless a section explicitly says otherwise, it describes the target architecture and API for later phases rather than the exact runtime behavior on current `main`.

## Context

> fTimer is a lightweight, correctness-first timing library for Fortran codes. Inspired by Flash-X's MPINative Timers but designed as a standalone profiling substrate, it preserves the proven conceptual model (stack-based nesting, context-sensitive accounting, hierarchical summary) while optimizing for correctness, clarity, portability, and composability.

**Scope (implemented through Phase 5):** A portable wall-clock timer library with profiling extensibility hooks plus local structured summaries, formatted reports, a procedural convenience API over the OOP core, and MPI-reduced structured summaries with cross-rank preflight. fTimer does NOT itself provide hardware counter or power measurements — it provides callback hooks so external tools (PAPI, likwid, etc.) can attach to timer boundaries in the future.

**Where fTimer preserves Flash-X's design:** strict stack-based nesting, context-sensitive accounting of the same timer under different parents, hierarchical summary logic, low conceptual overhead, string and integer-key access.

**Where fTimer intentionally diverges:**
- Correctness-first defaults (strict mismatch handling, not silent repair)
- Timing data as structured data first, formatted report second (programmatic `get_summary()` API)
- Exclusive/self time alongside inclusive time
- No domain-specific concepts (`nsteps` → generic metadata)
- MPI imbalance metrics beyond min/max/avg
- OOP core with encapsulated state and multiple instances
- Injectable clock, configurable error handling, callback hooks with full context

## Current Phase 5 Snapshot

Current `main` is intentionally narrower than the target design below:

- the library, examples, packaging, and smoke tests are buildable
- `ftimer_types.F90` provides the shared constants, summary/container types, and abstract interfaces
- `ftimer_clock.F90` provides the default wall clock, MPI wall clock wrapper, and date-string utility
- `ftimer_core.F90` implements `init`, `finalize`, `start`, `stop`, `start_id`, `stop_id`, `lookup`, `reset`, `get_summary`, `print_summary`, and `write_summary`
- `ftimer_summary.F90` implements local summary building and formatted text reporting
- `ftimer.F90` now exports the local procedural wrapper surface: `ftimer_init`, `ftimer_finalize`, `ftimer_start`, `ftimer_stop`, `ftimer_start_id`, `ftimer_stop_id`, `ftimer_lookup`, `ftimer_reset`, `ftimer_get_summary`, `ftimer_print_summary`, and `ftimer_write_summary`
  Current Phase 5 note: the procedural wrapper keeps the legacy one-argument positional `ftimer_init(ierr)` calling form, so `comm` and `mismatch_mode` are keyword arguments in the current implementation
- stack-based nesting, context-sensitive accounting, injectable clock use, and strict/warn/repair mismatch dispatch are implemented in the core runtime
- pFUnit-backed behavioral tests exist for the Phase 2 core behaviors plus Phase 3 summary/self-time/file/callback coverage, Phase 4 procedural parity coverage, and Phase 5 MPI summary coverage
- `mpi_summary()` / `ftimer_mpi_summary()` now provide MPI-reduced structured summaries on root after a descriptor-hash preflight, return local-only summaries with `FTIMER_ERR_MPI_INCON` on inconsistent ranks, return `FTIMER_ERR_NOT_IMPLEMENTED` in non-MPI builds, and require all timers to be stopped before cross-rank reduction

For the current user-facing contract, prefer `README.md` and the source in `src/`. Use this document as the implementation target for future phases.

## Key Decisions

- **Build system**: CMake with a convenience Makefile wrapper (`make`, `make test`, `make install` delegate to cmake/ctest)
- **Current baseline**: buildable Phase 5 foundation + core runtime + local summary/reporting + procedural wrappers + MPI-reduced structured summaries + smoke tests + opt-in serial/MPI pFUnit tests; later phases add OpenMP guards
- **Testing**: current `main` uses smoke tests by default and pFUnit with an injectable mock clock when `FTIMER_BUILD_TESTS=ON`
- **Timer model**: Strict nesting only (stack-based, no overlapping timers)
- **Mismatch handling**: Configurable (`strict`/`warn`/`repair`), **default `strict`**. `repair` mode is Flash-X compatibility. Internal repair transitions do NOT fire user callbacks.
- **Error model**: Optional `ierr` argument on all public routines (standard Fortran pattern). When `ierr` absent, print warning to stderr.
- **GitHub**: `jaharris87/fTimer`, public
- **License**: BSD-3-Clause

## Target Project Structure

```
fTimer/
├── CMakeLists.txt                     # Top-level CMake (library + tests + examples)
├── Makefile                           # Convenience wrapper (delegates to cmake)
├── CLAUDE.md                          # Builder agent instructions
├── AGENTS.md                          # Reviewer agent context
├── README.md                          # User-facing docs
├── LICENSE
├── docs/
│   └── semantics.md                   # Timing semantics: inclusive/exclusive time,
│                                      #   nesting rules, mismatch policy, reset behavior,
│                                      #   MPI/OpenMP guarantees, error contract
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                     # CI: build, lint, test (serial + MPI)
│   │   └── codex-review.yml          # Codex review triggers
│   └── prompts/
│       ├── software-review.md         # Condensed native trigger prompt
│       ├── methodology-review.md      # Condensed timing/HPC trigger prompt
│       ├── red-team-review.md         # Condensed adversarial trigger prompt
│       └── detailed/
│           ├── software-review.md     # Detailed software review prompt
│           ├── methodology-review.md  # Detailed methodology review prompt
│           ├── red-team-review.md     # Detailed adversarial review prompt
│           ├── api-compat-review.md   # Long-horizon API/compatibility review
│           ├── build-portability-review.md
│           ├── docs-contract-review.md
│           ├── mpi-safety-review.md
│           ├── performance-overhead-review.md
│           └── test-quality-review.md
├── .claude/
│   └── settings.json
├── src/
│   ├── CMakeLists.txt
│   ├── ftimer_types.F90               # Derived types, kind params, constants, enums, summary type
│   ├── ftimer_clock.F90               # Wall-clock abstraction (injectable, MPI_Wtime vs system_clock)
│   ├── ftimer_core.F90               # ftimer_t class: init, start, stop, reset, finalize, lookup
│   ├── ftimer_summary.F90             # Summary building: structured data + text formatting
│   ├── ftimer_mpi.F90                 # MPI gather/reduce for cross-rank summary
│   └── ftimer.F90                     # Procedural convenience wrappers + default global instance
├── tests/
│   ├── CMakeLists.txt
│   ├── test_basic.pf                  # Init/finalize, single start/stop, timer creation
│   ├── test_nesting.pf               # Nested timer hierarchies, mismatch modes
│   ├── test_context.pf               # Same timer in different parent contexts
│   ├── test_callcount.pf             # Call count tracking
│   ├── test_reset.pf                 # Reset behavior
│   ├── test_edge_cases.pf            # Boundary conditions, error handling, ierr contract
│   ├── test_summary.pf              # Structured summary correctness + text format (golden output)
│   ├── test_self_time.pf             # Exclusive/self time computation
│   ├── test_file_output.pf           # File I/O (new + append)
│   ├── test_callbacks.pf             # on_event fires correctly; repair does NOT fire callbacks
│   └── mpi/
│       ├── CMakeLists.txt
│       ├── test_mpi_summary.pf       # MPI min/max/avg/imbalance correctness
│       └── test_mpi_consistency.pf   # Cross-rank timer consistency checks
├── examples/
│   ├── CMakeLists.txt
│   ├── basic_usage.F90
│   ├── nested_timers.F90             # With golden expected output
│   └── mpi_example.F90
└── fixtures/
```

## Target Public API

Users interact via `use ftimer` (procedural) or `use ftimer_core` (OOP only, no global state).

### OOP Interface
```fortran
type(ftimer_t) :: timer
call timer%init([comm] [, mismatch_mode] [, ierr])
call timer%start("name" [, ierr])
call timer%stop("name" [, ierr])

! Structured data access
type(ftimer_summary_t) :: summary
call timer%get_summary(summary [, ierr])      ! programmatic access
! summary%entries(:) contains name, inclusive_time, self_time, call_count, pct, depth, ...

! Formatted reports
call timer%print_summary([unit] [, metadata] [, ierr])
call timer%finalize([ierr])
```

### Procedural Convenience Interface
```fortran
! Current Phase 5 implementation preserves legacy `ftimer_init(ierr)` positional usage.
! Pass `comm` and `mismatch_mode` by keyword in the procedural wrapper.
call ftimer_init([ierr])
call ftimer_init(comm=..., mismatch_mode=..., ierr=...)
call ftimer_start("name" [, ierr])
call ftimer_stop("name" [, ierr])
call ftimer_get_summary(summary [, ierr])
call ftimer_print_summary([unit] [, metadata] [, ierr])
call ftimer_finalize([ierr])
```

### Full API

| Type-bound method | Procedural wrapper | Description |
|---|---|---|
| `timer%init(...)` | `ftimer_init(...)` | Initialize. Optional MPI comm (integer handle), mismatch mode. |
| `timer%finalize([ierr])` | `ftimer_finalize(...)` | Deallocate all. Warns if timers active. |
| `timer%start(name [, ierr])` | `ftimer_start(...)` | Start timer by name (auto-creates). |
| `timer%stop(name [, ierr])` | `ftimer_stop(...)` | Stop timer by name. |
| `timer%start_id(id [, ierr])` | `ftimer_start_id(...)` | Start by cached integer ID (fast path). |
| `timer%stop_id(id [, ierr])` | `ftimer_stop_id(...)` | Stop by cached integer ID. |
| `timer%lookup(name [, ierr]) -> id` | `ftimer_lookup(...)` | Get/create integer ID. |
| `timer%reset([ierr])` | `ftimer_reset(...)` | Zero times/counts, keep definitions. |
| `timer%get_summary(summary [, ierr])` | `ftimer_get_summary(...)` | **Structured data**: returns `ftimer_summary_t` with all timing data. |
| `timer%print_summary(...)` | `ftimer_print_summary(...)` | **Formatted text**: hierarchical table to stdout or unit. |
| `timer%write_summary(...)` | `ftimer_write_summary(...)` | Formatted text to file (new or append). |
| `timer%mpi_summary(...)` | `ftimer_mpi_summary(...)` | MPI-reduced structured summary on root. |

### Summary Metadata (replaces `nsteps`)

Instead of a domain-specific `nsteps` argument, summaries accept generic metadata:

```fortran
type(ftimer_metadata_t) :: meta(2)
meta(1) = ftimer_metadata("evolution steps", "10")
meta(2) = ftimer_metadata("grid blocks", "1024")
call timer%print_summary(metadata=meta)
```

This produces header lines like:
```
 evolution steps :                   10
 grid blocks     :                 1024
```

The `ftimer_metadata_t` type is a simple key-value pair:
```fortran
type :: ftimer_metadata_t
  character(len=FTIMER_NAME_LEN) :: key = ''
  character(len=FTIMER_NAME_LEN) :: value = ''
end type
```

### Error Contract

All public routines accept optional `integer, intent(out) :: ierr`:
- **`ierr` present**: Set to 0 on success, non-zero on error. No stderr output.
- **`ierr` absent**: Print warning to stderr, continue execution (no abort).

| Condition | Code | Default behavior (no `ierr`) |
|---|---|---|
| `start`/`stop` before `init` | `FTIMER_ERR_NOT_INIT` | Warn, no-op |
| `stop` on unknown timer | `FTIMER_ERR_UNKNOWN` | Warn, no-op |
| `finalize` with active timers | `FTIMER_ERR_ACTIVE` | Warn, force-stop all, then finalize |
| `reset` with active timers | `FTIMER_ERR_ACTIVE` | Warn, force-stop all, then reset |
| Mismatch stop (strict mode) | `FTIMER_ERR_MISMATCH` | Warn, do NOT stop the timer |
| MPI timer inconsistency | `FTIMER_ERR_MPI_INCON` | Warn, fall back to local-only summary |
| File I/O failure | `FTIMER_ERR_IO` | Warn, no-op |

### Mismatch Handling Modes

Set at init via `mismatch_mode`:

| Mode | Constant | Behavior |
|---|---|---|
| **Strict** (default) | `FTIMER_MISMATCH_STRICT` | Set `ierr` or warn. Do not stop the timer. User must fix nesting. |
| **Warn** | `FTIMER_MISMATCH_WARN` | Print diagnostic, then iteratively repair. |
| **Repair** | `FTIMER_MISMATCH_REPAIR` | Silent iterative repair. Flash-X compatibility mode. |

In `warn` and `repair` modes, internal repair transitions do NOT fire user callbacks.

### Profiling Extensibility (callback hooks)

```fortran
! Declared in ftimer_types (no dependency on ftimer_t — avoids circular reference).
! The user_data c_ptr provides instance/state context; passing the ftimer_t instance
! itself would create a circular type dependency between the interface and the class.
abstract interface
  subroutine ftimer_hook_proc(timer_id, context_idx, event, timestamp, user_data)
    import :: wp, c_ptr
    integer, intent(in) :: timer_id, context_idx
    integer, intent(in) :: event              ! FTIMER_EVENT_START or FTIMER_EVENT_STOP
    real(wp), intent(in) :: timestamp
    type(c_ptr), intent(in) :: user_data      ! opaque user state (e.g., PAPI context)
  end subroutine
end interface

! Register:
timer%on_event => my_papi_handler
timer%user_data = c_loc(my_papi_state)
```

## Target Data Structure Design

### Structured Summary Type (in `ftimer_types.F90`)

The key "data first, report second" type. This is what `get_summary()` returns.

A single flat entry type includes both local and MPI fields. MPI fields default to `-1.0_wp` (sentinel) and are only populated by `mpi_summary()`. The `has_mpi_data` flag on the summary indicates whether MPI fields are valid. This avoids polymorphic storage (`class(...)` allocatable arrays) which adds complexity without benefit here.

```fortran
type :: ftimer_summary_entry_t
  character(len=FTIMER_NAME_LEN) :: name
  integer :: depth                    ! nesting depth (0 = top-level)
  real(wp) :: inclusive_time          ! total time including children
  real(wp) :: self_time              ! exclusive time = inclusive - sum(children)
  integer :: call_count
  real(wp) :: avg_time               ! inclusive_time / call_count
  real(wp) :: pct_time               ! percentage of total monitoring period
  ! MPI fields — only valid when summary%has_mpi_data is .true.
  real(wp) :: min_time = -1.0_wp
  real(wp) :: max_time = -1.0_wp
  real(wp) :: avg_across_ranks = -1.0_wp
  real(wp) :: imbalance = -1.0_wp     ! max_time / avg_across_ranks (1.0 = perfect)
end type

type :: ftimer_summary_t
  character(len=40) :: start_date, end_date
  real(wp) :: total_time             ! wall-clock monitoring period
  logical :: has_mpi_data = .false.  ! .true. when populated by mpi_summary
  integer :: num_entries = 0
  type(ftimer_summary_entry_t), allocatable :: entries(:)
end type
```

### Core Types

```fortran
integer, parameter :: wp = selected_real_kind(15, 307)
integer, parameter :: FTIMER_NAME_LEN = 64

type :: ftimer_call_stack_t
  integer :: depth = 0
  integer, allocatable :: ids(:)
contains
  procedure :: push, pop, top, equals, copy
end type

type :: ftimer_context_list_t
  integer :: count = 0
  type(ftimer_call_stack_t), allocatable :: stacks(:)
contains
  procedure :: find, add
end type

! Per-timer segment — NO pct_time here (computed in summary only)
type :: ftimer_segment_t
  character(len=FTIMER_NAME_LEN) :: name = ''
  real(wp), allocatable :: time(:)         ! accumulated inclusive time per context
  real(wp), allocatable :: start_time(:)   ! pending start timestamp per context
  logical, allocatable  :: is_running(:)   ! currently active per context
  integer, allocatable  :: call_count(:)   ! invocation count per context
  type(ftimer_context_list_t) :: contexts
end type

! Clock procedure interface (injectable for testing)
abstract interface
  function ftimer_clock_func() result(t)
    import :: wp
    real(wp) :: t
  end function
end interface

! Callback interface — in ftimer_types, no dependency on ftimer_t
abstract interface
  subroutine ftimer_hook_proc(timer_id, context_idx, event, timestamp, user_data)
    import :: wp, c_ptr
    integer, intent(in) :: timer_id, context_idx, event
    real(wp), intent(in) :: timestamp
    type(c_ptr), intent(in) :: user_data
  end subroutine
end interface

! Main timer class
type :: ftimer_t
  private
  type(ftimer_call_stack_t) :: call_stack
  type(ftimer_segment_t), allocatable :: segments(:)
  integer :: num_segments = 0
  real(wp) :: init_wtime = 0.0_wp
  character(len=40) :: init_date = ''
  logical :: initialized = .false.
  integer :: mismatch_mode = FTIMER_MISMATCH_STRICT  ! default: strict
#ifdef FTIMER_USE_MPI
  integer :: mpi_comm = -1       ! integer handle (mpif.h and mpi_f08 compatible)
  integer :: mpi_rank = -1
  integer :: mpi_nprocs = 1
#endif
  procedure(ftimer_clock_func), pointer, nopass :: clock => null()
  procedure(ftimer_hook_proc), pointer, nopass :: on_event => null()
  type(c_ptr) :: user_data = c_null_ptr
contains
  procedure :: init, finalize, start, stop, start_id, stop_id
  procedure :: lookup, reset
  procedure :: get_summary          ! -> ftimer_summary_t (structured data)
  procedure :: print_summary        ! formatted text output
  procedure :: write_summary        ! formatted text to file
  procedure :: mpi_summary          ! MPI-reduced (structured or formatted)
  procedure, private :: wtime, find_or_create_segment, repair_mismatch
end type
```

### Module-level default instance (in `ftimer.F90`)

```fortran
type(ftimer_t), save, target :: default_timer
! Procedural wrappers delegate to default_timer
! Users who only need the class import ftimer_core (no global state)
```

## Key Algorithms

### Timer Start (`self%start(name)`)
1. Check `self%initialized`; if not, set `ierr`/warn and return
2. Look up timer name → index (linear search, create if new)
3. Find current `self%call_stack` in `self%segments(idx)%contexts`
4. If not found, add current call_stack as new context, grow per-context arrays
5. Push `idx` onto `self%call_stack`
6. `now = self%wtime()`
7. Record `start_time(ctx) = now`, increment `call_count(ctx)`, set `is_running(ctx) = .true.`
8. If `self%on_event` associated, call with `FTIMER_EVENT_START` and `now`

### Timer Stop (`self%stop(name)`)
1. Look up timer index (do not create). If not found, set `ierr`/warn and return.
2. If `idx` matches top of `self%call_stack` (normal case):
   - Pop `self%call_stack`
   - Find context matching the popped call_stack
   - `now = self%wtime()`
   - Accumulate: `time(ctx) += now - start_time(ctx)`
   - Set `is_running(ctx) = .false.`
   - If `self%on_event` associated, call with `FTIMER_EVENT_STOP` and `now`
3. If mismatch — dispatch on `self%mismatch_mode`:
   - **strict**: set `ierr = FTIMER_ERR_MISMATCH` or warn, return without stopping
   - **warn**: print diagnostic, then `self%repair_mismatch(idx)`
   - **repair**: `self%repair_mismatch(idx)` silently

### Iterative Mismatch Repair (`self%repair_mismatch`)
1. Capture `now = self%wtime()` **once**
2. Build unwind list: pop `self%call_stack` until finding `idx`, collecting unwound (id, context) pairs
3. For each unwound timer: accumulate `time(ctx) += now - start_time(ctx)`, set `is_running = .false.`
4. Stop the requested timer `idx` using the same `now`
5. Restart unwound timers in **reverse order**: push back, set `start_time(ctx) = now`, `is_running = .true.`
6. **Do NOT fire `on_event`** during any repair step

### Summary Building (recursive tree walk)
Produces `ftimer_summary_t` (structured data). Text formatting is a separate step.

```
recursive subroutine build_summary_entries(entries, count, root_stack, depth)
  do i = 1, num_segments
    ctx = segments(i)%contexts%find(root_stack)
    if (ctx > 0) then
      ! Compute inclusive time
      inclusive = segments(i)%time(ctx)
      ! Self time computed in a second pass (inclusive - sum of direct children)
      entries(count) = ftimer_summary_entry_t(name, depth, inclusive, ...)
      count = count + 1
      child_stack = root_stack; push i onto child_stack
      call build_summary_entries(entries, count, child_stack, depth+1)
    end if
  end do
end subroutine
```

Self time: after building the full entry list, iterate and for each entry subtract the inclusive times of its direct children (entries at depth+1 that immediately follow it before the next entry at the same or lesser depth).

### MPI Summary
1. **Deterministic preflight**: Each rank hashes its canonical timer descriptor list (sorted timer names + context stack signatures). Exchange hashes via `MPI_Allgather`. If any differ, set `ierr = FTIMER_ERR_MPI_INCON` or warn, fall back to local-only.
2. If consistent: `MPI_Reduce` for min/max/sum of each entry's inclusive_time
3. Compute `avg = sum / nprocs`, `imbalance = max / avg`
4. Root populates `ftimer_mpi_summary_entry_t` entries
5. Format and output (or return structured `ftimer_summary_t` with MPI entries)

## MPI and OpenMP Strategy

### MPI (`#ifdef FTIMER_USE_MPI`)
- `init(comm)` accepts integer comm handle — compatible with `include 'mpif.h'` (integers natively) and `use mpi_f08` (via `comm%MPI_VAL`). Document both in `docs/semantics.md`.
- `self%wtime()` uses `MPI_Wtime()` when MPI enabled, `system_clock` otherwise
- `mpi_summary()` does collective operations; `print_summary()` is local-only
- Stubs when MPI disabled: `mpi_summary` falls back to `print_summary`

### OpenMP
- All timer operations guarded by `!$omp master` / `!$omp end master` (same approach as Flash-X)
- **Master-thread-only, NOT generally thread-safe.** Timer calls inside parallel regions are no-ops on non-master threads. Concurrent access from multiple threads (e.g., via `omp single`) is undefined behavior.
- Optional `suppress_in_parallel` flag to skip timer calls entirely within parallel regions
- Limitations documented explicitly in `docs/semantics.md`
- Phase 2 could explore thread-local timer instances for per-thread measurement

## Testing Strategy (pFUnit + Mock Clock)

### Injectable Mock Clock
```fortran
real(wp), save :: fake_time = 0.0_wp
function mock_clock() result(t)
  real(wp) :: t
  t = fake_time
end function

! In test setup:
timer%clock => mock_clock
fake_time = 0.0_wp

! In test: advance deterministically
call timer%start("A")
fake_time = 2.5_wp
call timer%stop("A")
! Assert: timer "A" accumulated exactly 2.5 seconds
```

### Serial tests
| Test file | What it covers |
|-----------|---------------|
| `test_basic.pf` | init/finalize, single start/stop, auto-creation, ID lookup, time accumulation (mock clock) |
| `test_nesting.pf` | 2-level nesting, deep nesting (10+), mismatch in all three modes (strict returns error, warn prints + repairs, repair is silent) |
| `test_context.pf` | Same timer under different parents tracked separately, times independent |
| `test_callcount.pf` | Single call, multiple calls, counts per context |
| `test_reset.pf` | Reset zeros times/counts, preserves names; reset with active timers returns `FTIMER_ERR_ACTIVE` |
| `test_edge_cases.pf` | stop unknown, start before init, finalize with active, name at/beyond `FTIMER_NAME_LEN`, dynamic growth — all verified via `ierr` |
| `test_summary.pf` | `get_summary()` returns correct structured data; `print_summary()` matches golden text output; metadata appears in header |
| `test_self_time.pf` | Exclusive/self time: parent(10s) containing child(7s) → parent self_time = 3s |
| `test_file_output.pf` | Write to new file, append to existing, invalid path returns `FTIMER_ERR_IO` |
| `test_callbacks.pf` | `on_event` fires with correct args on normal start/stop; repair does NOT fire callbacks |

### MPI tests (run with 2+ ranks)
| Test file | What it covers |
|-----------|---------------|
| `test_mpi_summary.pf` | min/max/avg/imbalance correctness with mock clock per rank |
| `test_mpi_consistency.pf` | Consistent timers succeed; inconsistent detected via hash, returns `FTIMER_ERR_MPI_INCON` |

## Framework Scaffolding

### CLAUDE.md key content
- Build: `cmake -B build && cmake --build build`, `ctest --test-dir build`
- MPI build: `cmake -B build -DFTIMER_USE_MPI=ON`
- Lint: `find src -name '*.F90' -exec fprettify --diff {} +` plus matching checks for `tests/` and `examples/`
- Architecture: `ftimer` (procedural wrappers) → `ftimer_core` (OOP class) → `ftimer_types` (data structures + summary types), with `ftimer_summary` (tree walk + formatting), `ftimer_mpi` (MPI collectives), `ftimer_clock` (injectable time source)

### AGENTS.md key risks
1. **Context mismatch in start/stop** — stop pops stack BEFORE looking up context; reversing silently zeroes times
2. **Iterative repair timestamp consistency** — must use single `now`; independent clock reads cause gaps or double-counting
3. **Repair firing user callbacks** — repair transitions must NOT fire `on_event`; if they do, external profiling corrupted
4. **Self-time computation error** — if child iteration boundaries are wrong, self_time can go negative or exceed inclusive_time
5. **Double-precision truncation** — any implicit conversion to default `real` degrades accuracy for runs > 1 hour
6. **MPI summary hangs on inconsistent timer sets** — hash-based preflight is mandatory before any collectives
7. **Array growth divergence across MPI ranks** — if ranks create timers in different orders, segment indices diverge

### Methodology review focus
- Timing correctness: context attribution, precision, inclusive/exclusive time consistency
- Stack integrity: push/pop balance, iterative repair correctness
- Error contract: every edge case follows the `ierr`/warn contract
- MPI correctness: hash preflight, collective safety, imbalance metric validity
- OpenMP: master-only access, documented limitations

### CI workflow
- Current jobs: serial build+smoke test, MPI build+smoke test, lint
- Runner: ubuntu-latest with gfortran + OpenMPI
- pFUnit CI is deferred until the real test suite exists
- Intel ifx CI deferred to Phase 2

### `.claude/settings.json` permissions
- `Bash(cmake *)`, `Bash(make *)`, `Bash(ctest *)`, `Bash(gfortran *)`, `Bash(mpif90 *)`, `Bash(mpirun *)`, `Bash(fprettify *)`

## Implementation Order

1. **Scaffolding**: `init-project.sh`, fill templates, directory structure, git + GitHub repo + labels
2. **Types + Clock**: `ftimer_types.F90` (all types, enums, errors, summary types, metadata), `ftimer_clock.F90` (injectable with defaults) — compile-check serial and MPI
3. **Core**: `ftimer_core.F90` — `ftimer_t` class: init, start, stop (with mismatch dispatch), reset, finalize, lookup, repair_mismatch + serial pFUnit tests with mock clock
4. **Summary**: `ftimer_summary.F90` — `get_summary()` returning `ftimer_summary_t` with self-time + `print_summary()`/`write_summary()` text formatting + golden output tests
5. **Public API**: `ftimer.F90` — default_timer + procedural wrappers, verify both interfaces
6. **MPI**: `ftimer_mpi.F90` — hash preflight + MPI reduce + imbalance metrics + `mpi_summary()` + MPI tests
7. **OpenMP guards**: `!$omp master` throughout `ftimer_core.F90`
8. **Docs**: `docs/semantics.md` — inclusive/exclusive time, nesting rules, mismatch modes, reset behavior, MPI/OpenMP guarantees, error contract, `mpi_f08` usage
9. **Examples**: basic, nested (with golden expected output), MPI
10. **Polish**: fprettify, README (with identity statement), CI verification

### Implementation Watch Items (not blockers)
- **Linear search performance**: Timer name lookup and context matching are O(N). Fine for phase 1 (expected N < 200), but if a project needs thousands of timers, a hash map optimization would be warranted. The integer ID caching mechanism already eliminates repeated lookups in hot loops.
- **Callback interface Fortran mechanics**: The abstract interface is cleanly in `ftimer_types` with no circular dependency. If implementation reveals awkwardness with specific compilers, the signature can be adjusted without API breakage since callbacks are an opt-in feature.

### Phase 2 (future, not in this implementation)
- Built-in counter backend (PAPI, likwid)
- Scoped timer convenience type (Fortran `final` support permitting)
- Intel ifx CI
- Thread-local timer instances for per-thread OpenMP measurement
- CSV/JSON export utilities
- Hash-based timer name lookup (if profiling reveals linear search as bottleneck)

## Target Verification

- `cmake -B build && cmake --build build` — serial build succeeds
- `cmake -B build -DFTIMER_USE_MPI=ON && cmake --build build` — MPI build succeeds
- `ctest --test-dir build` — all serial pFUnit tests pass (deterministic, mock clock, no sleeps)
- `ctest --test-dir build -L mpi` — all MPI tests pass (2 and 4 ranks)
- `find src tests examples -name '*.F90' -exec fprettify --diff {} +` plus `find tests -name '*.pf' -exec fprettify --diff {} +` — no formatting differences
- Run `examples/nested_timers.F90` — output matches golden expected output
- Run `examples/mpi_example.F90` with `mpirun -np 4` — MPI summary with min/max/avg/imbalance
- Error contract: tests confirm every edge case returns correct `ierr` value
- Mismatch modes: tests cover strict (error, no repair), warn (diagnostic + repair), repair (silent)
- Self time: tests confirm `parent_self = parent_inclusive - sum(children_inclusive)`
- Callback safety: test confirms repair events do not fire `on_event`

## Author Reference Notes

These references informed the design but are not required to work in this repo:

- Flash-X MPINative timer sources, especially `Timers_data.F90`, `Timers_start.F90`, `Timers_stop.F90`, `tmr_buildSummary.F90`, and `tmr_stackLib.F90`
- the author's project scaffolding templates and init scripts used during the initial repo setup
