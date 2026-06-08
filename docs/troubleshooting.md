> **When to read this:** When a first build, MPI summary/report, CSV export, or
> OpenMP timing attempt fails and you want the practical next step. This is a
> troubleshooting guide, not a replacement for the full runtime contract in
> [`docs/semantics.md`](semantics.md).

# fTimer Troubleshooting

Start with the smallest build that exercises what you need:

```bash
cmake -B build-smoke
cmake --build build-smoke
cmake -E chdir build-smoke ctest --output-on-failure
```

For the first example only:

```bash
cmake --build build-smoke --target basic_usage
./build-smoke/examples/basic_usage
```

That path should not require MPI or pFUnit. If it fails, fix the serial build
first before adding MPI, OpenMP, or the pFUnit suite.

## Configure Cannot Find A Fortran Compiler

CMake needs a Fortran compiler with preprocessing support. Install or load a
validated compiler, then configure with that compiler explicitly:

```bash
FC=gfortran cmake -B build-smoke
```

GNU Fortran and LLVM Flang are the validated serial smoke paths. Other serial
compilers may work, but they are outside the current release-validated matrix.

## Configure Fails After Switching Compilers Or Modes

CMake build trees are not portable across compiler or mode changes. A build
directory configured with `gfortran` should not be reused for `mpifort`,
`flang-19`, `FTIMER_USE_MPI=ON`, or `FTIMER_USE_OPENMP=ON`.

Use a separate build directory:

```bash
FC=gfortran cmake -B build-smoke
FC=mpifort cmake -B build-mpi-smoke -DFTIMER_USE_MPI=ON
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON
```

For a clean reconfigure, remove the old build directory or use a fresh one.
With CMake 3.24 or newer, `cmake --fresh` is also available as a convenience.

## Configure Fails With pFUnit Enabled

`FTIMER_BUILD_TESTS=ON` enables the pFUnit behavioral suite. That requires a
pFUnit installation built for the same compiler and, for MPI tests, the same MPI
toolchain family.

Pass the install prefix explicitly:

```bash
FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit
```

If you only want the smoke path and examples, leave `FTIMER_BUILD_TESTS=OFF`.
The default smoke build does not require pFUnit.

## Configure Fails With MPI Enabled

`FTIMER_USE_MPI=ON` is intended for MPI wrapper compilers such as `mpifort`.
Configure runs a small `mpi_f08` probe and fails early if the active compiler
cannot consume the discovered MPI module files.

Use a wrapper from the same toolchain as the MPI installation:

```bash
FC=mpifort cmake -B build-mpi-smoke -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=OFF
```

If the error mentions `mpi_f08`, `MPI_Type_match_size`, or
`MPI_ERRORS_RETURN`, check that:

- `FC` or `CMAKE_Fortran_COMPILER` points at the MPI wrapper you meant to use.
- The wrapper belongs to the MPI installation CMake discovered.
- The MPI implementation provides the `mpi_f08` interfaces fTimer validates.

The supported communicator interface is `type(MPI_Comm)` from `mpi_f08`.
Legacy integer communicator handles and `mpif.h` are not supported paths.

## Configure Fails With OpenMP Enabled

`FTIMER_USE_OPENMP=ON` is currently validated for GNU Fortran and LLVM Flang.
The configure step rejects unvalidated compiler IDs before trying to discover
the OpenMP runtime.

Use one of the documented paths:

```bash
FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON
FC=flang-19 cmake -B build-openmp-flang -DFTIMER_USE_OPENMP=ON -DOpenMP_ROOT=/path/to/libomp
```

LLVM Flang OpenMP validation requires CMake 3.24 or newer so CMake reports the
compiler ID as `LLVMFlang`. If runtime execution is unavailable because you are
cross-compiling or packaging in a restricted environment,
`FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK=ON` is an advanced maintainer escape hatch
and should be used only after independently validating equivalent OpenMP
master-thread and worker-lane semantics.

## OpenMP Worker Calls Do Not Appear In The Summary

For the existing `ftimer` and `ftimer_core` APIs, `FTIMER_USE_OPENMP=ON` enables
a master-thread-only compatibility carve-out. Worker-thread calls made inside an
OpenMP parallel region are silent no-ops: no summary row, no call-count
increment, and no changed `ierr`.

To time a parallel region as one wall-clock interval, place `start` and `stop`
outside the `!$omp parallel` block. To record worker-lane participation, use the
explicit `ftimer_openmp_t` API with registered ids and an explicitly opened
timed region. See [`docs/openmp-timing-modes.md`](openmp-timing-modes.md).

Global compiler flags such as `-fopenmp` do not enable fTimer's guards when the
library was configured with `FTIMER_USE_OPENMP=OFF`. The CMake option is the
source-level switch for the guard code and the supported worker-timing runtime.

## MPI Checklist

Before debugging the output, confirm the lifecycle and communicator contract:

- Call MPI-enabled fTimer only after `MPI_Init` and before `MPI_Finalize`.
- Finish fTimer MPI summaries, reports, CSV writes, `finalize()`, and any
  reinitialization before freeing a caller-owned communicator.
- Keep `init(comm=...)` communicators valid; fTimer stores borrowed,
  non-owning handles and does not call `MPI_Comm_dup` or `MPI_Comm_free`.
- Have every rank in the captured communicator enter each MPI summary/report
  collective.
- Stop all timers before MPI summary/report calls. Local summaries can snapshot
  active timers; MPI summaries are stopped-run-only.
- Use strict MPI summary/report APIs only when all participating ranks have the
  same descriptor tree.
- Use sparse union APIs for rank-conditional timer trees.

fTimer does not insert MPI barriers around timed regions. It reduces rank-local
wall-clock intervals. If you need a synchronized global phase, add the barrier
or synchronization you intend to measure in application code.

## MPI Summary Returns `FTIMER_ERR_MPI_INCON`

Strict MPI summaries and reports require identical timer descriptor trees across
all ranks in the captured communicator. Extra timers, missing timers, renamed
timers, or different parent/child structure cause `FTIMER_ERR_MPI_INCON`.

Fix by making every participating rank create the same timer tree, or switch to
the sparse union API for rank-conditional work:

```fortran
call ftimer_mpi_union_summary(summary, ierr=ierr)
call ftimer_write_mpi_union_summary_csv("ftimer-mpi-union.csv", ierr=ierr)
```

Sparse union entries report explicit participation counts. A missing rank is
absent from that descriptor; it is not the same as a rank that participated with
a real zero-time, zero-call entry.

## MPI Summary Returns `FTIMER_ERR_ACTIVE`

MPI summaries and MPI report/CSV writers require a fully stopped timer set. If
any participating rank still has an active timer, the collective summary/report
path returns `FTIMER_ERR_ACTIVE` and leaves the MPI result or normal artifact
empty.

Stop every timer on every rank before calling:

```fortran
call ftimer_stop("phase", ierr=ierr)
call ftimer_mpi_summary(summary, ierr=ierr)
```

For local debugging snapshots, use `ftimer_get_summary()` separately. Local
summary APIs can show active timers; MPI summary APIs intentionally do not.

## MPI Summary Hangs

The practical failure mode for divergent communicators or missing collective
participants is a hang. fTimer can detect descriptor disagreement only after all
ranks have entered the same communicator collective. It cannot safely rendezvous
across different communicator choices after the application has already split.

Check that:

- Every rank that belongs to the captured communicator reaches the same
  `mpi_summary`, MPI report, or MPI CSV call.
- All ranks captured the same communicator choice at `init`.
- Caller-owned subcommunicators were not freed before fTimer finished using
  them.
- Rank-conditional code does not skip the collective itself. Use sparse union
  APIs for conditional descriptors, not conditional collective entry.

## MPI APIs Return `FTIMER_ERR_NOT_IMPLEMENTED`

If fTimer was built with `FTIMER_USE_MPI=OFF`, MPI summary/report APIs return
`FTIMER_ERR_NOT_IMPLEMENTED`. They do not fall back to local summaries and do
not create or replace MPI report files.

Reconfigure with MPI enabled if you need MPI reports:

```bash
FC=mpifort cmake -B build-mpi-smoke -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=OFF
```

If you only need rank-local data from a non-MPI build, call the local summary or
CSV APIs instead.

## CSV Columns Look Different Between Files

fTimer has several CSV schemas. They are separate on purpose:

- Local and strict MPI CSV use `format_version=2`.
- Sparse MPI union CSV uses `format_version=1` and `summary_kind=mpi_union`.
- Local OpenMP, strict MPI+OpenMP, and sparse MPI+OpenMP CSV each use their own
  `format_version=1` schema.

Small examples:

```fortran
call ftimer_write_summary_csv("local.csv", ierr=ierr)
call ftimer_write_mpi_summary_csv("mpi-strict.csv", ierr=ierr)
call ftimer_write_mpi_union_summary_csv("mpi-union.csv", ierr=ierr)
```

Do not append sparse union rows to a local/strict MPI CSV file or the reverse.
Those headers are not append-compatible.

## CSV Append Returns `FTIMER_ERR_IO`

With `append=.true.`, fTimer validates the existing non-empty file before adding
new records. It rejects the append with `FTIMER_ERR_IO` if the target has:

- a mismatched header or older schema
- rows with the wrong field count
- unrecognized `summary_kind` or `record_type` combinations
- malformed CSV quoting
- a final record that is not newline-terminated
- a schema from a different report family, such as sparse union CSV versus
  local/strict MPI CSV

The existing file is left unchanged on validation failure. Start a new output
file, append only to files produced by the same API/schema, or repair the
existing file so the header, records, quoting, and final newline are valid.

## CSV Counts Or Text Fields Look Surprising

Local `call_count` and strict MPI `min_call_count`/`max_call_count` are emitted
as signed 64-bit decimal text. Parse them as at least signed 64-bit integers.
Strict MPI `avg_call_count` remains a real-valued field.

Timer names and metadata key/value fields use standard CSV quoting. CSV output
does not use the visible escaping used by human text reports, and it is not
spreadsheet-formula-sanitized. Treat CSV as data from the generating program
when opening it in spreadsheet software.

## Reports Look Incomplete

Local, strict MPI, sparse MPI union, local OpenMP, strict MPI+OpenMP, and sparse
MPI+OpenMP report APIs are distinct surfaces.

- `print_summary()` and `write_summary()` are local snapshot reports.
- `print_mpi_summary()` and `write_mpi_summary()` are strict MPI reports.
- `print_mpi_union_summary()` and `write_mpi_union_summary()` are sparse MPI
  union reports.
- The `ftimer_openmp_t` report families are separate from the classic local and
  pure-MPI report families.

Strict MPI text reports are abbreviated human reports. The complete
machine-facing data is in `ftimer_mpi_summary_t` or the strict MPI CSV output.
For sparse/rank-conditional work, use `ftimer_mpi_union_summary_t` or sparse
union CSV so participation and missing-rank counts are explicit.

## Active Local Summaries Are Snapshots

Local summaries can include active timers as a snapshot at summary time. That is
useful for diagnostics, but it is not a final stopped-run report. Stop all
timers first when you need a final local report, and check
`summary%has_active_timers == .false.`.

MPI summaries, MPI reports, OpenMP worker summaries, and hybrid summaries are
stricter merge/report points. They require stopped timers or stopped timed
regions and return `FTIMER_ERR_ACTIVE` when that preflight fails.

## Timings Do Not Include Device Or Synchronized MPI Time

fTimer records host wall-clock time between your `start` and `stop` calls. It
does not synchronize GPU/device queues, and it does not insert MPI barriers. Add
device synchronization or MPI synchronization in the application when that is
the quantity you intend to measure.
