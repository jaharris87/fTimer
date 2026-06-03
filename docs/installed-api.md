# fTimer Installed API Stability

Stable source-level modules: `ftimer`, `ftimer_core`, `ftimer_openmp`, `ftimer_types`.

Pre-1.0 CMake package version compatibility is limited to the same minor release line. A `0.2.z` package can satisfy `find_package(fTimer 0.2 CONFIG REQUIRED)` and compatible `0.2.x` requests, but different `0.x` minor lines are not considered compatible. This package does not promise all-`0.x` source or compiler-module compatibility. The `0.2` package line is the compatibility boundary for the production-readiness call-count widening: local `ftimer_summary_entry_t%call_count` plus MPI `min_call_count`/`max_call_count` summary/result fields are `integer(int64)` on this line. MPI `avg_call_count` remains `real(wp)` and may differ from the exact integer average by representable real rounding for signed-64-bit values that `real(wp)` cannot represent exactly. Local structured summaries also expose context-cardinality diagnostics through `ftimer_summary_t%total_contexts`, `ftimer_summary_t%max_contexts_per_timer`, `ftimer_summary_t%context_diagnostics`, `ftimer_summary_t%num_context_diagnostics`, and `ftimer_summary_entry_t%timer_context_count`; these fields do not change text or CSV schemas.

The supported source-level import surface is intentionally narrow:

- `use ftimer` for the procedural API and default timer instance
- `use ftimer_core` for `type(ftimer_t)`, its OOP methods, and the
  pointer-based `ftimer_oop_scope` scoped guard helper
- `use ftimer_openmp` for the explicit opt-in OpenMP timing API surface. In
  this release line, its lifecycle/configuration and timer catalog entry points
  are real, while otherwise valid worker timing and timed parallel-region calls
  are intentionally present but return `FTIMER_ERR_NOT_IMPLEMENTED` until the
  thread-lane runtime lands. Lifecycle, active-region, and unknown-id
  validation errors are reported before the deferred-runtime status.
  `ftimer_openmp_t%init` requires `config=` and accepts `comm=` only by keyword
  in MPI builds. The MPI communicator handle is stored for future hybrid
  reductions; no current public `ftimer_openmp` summary/report behavior consumes
  it. Registered timer ids remain
  valid across `reset()` and are invalidated across `finalize()`/reinit without
  being recycled in the same object. OpenMP-region rejection and bounded worker
  diagnostics require a package built with `FTIMER_USE_OPENMP=ON`. Calls made
  inside an OpenMP parallel region without `ierr` queue bounded diagnostics
  instead of writing unordered stderr, including thread 0 because the
  object-level API rejects in-parallel lifecycle/catalog/timed-region calls.
  Later serial lifecycle calls that clear them emit one aggregate diagnostic
  when `ierr` is absent, or return the first queued status without stderr when
  `ierr` is present. In non-OpenMP packages, this module is supported only for
  serial-context lifecycle/catalog use.
- `use ftimer_types` for shared constants, status codes, callback interfaces, and summary types

## MPI lifecycle and communicator ownership

MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`.
The installed MPI-enabled package uses `MPI_Wtime()` as its build-default clock
and its MPI summary/report entry points use MPI collectives, so pre-init or
post-finalize use is outside the supported runtime contract.

`init(comm=...)` stores the selected communicator as a non-owning handle. The
selected communicator is an `mpi_f08` `type(MPI_Comm)` value; legacy integer
communicator handles are not part of the installed MPI API. fTimer does not
duplicate caller-provided communicators and does not free them. Code that passes
a subcommunicator must keep that communicator valid until all fTimer MPI
summaries, MPI reports, `finalize()`, or `init()` reinitialization that may use
that communicator are complete.

Integer `init` options such as `mismatch_mode` and `ierr` are keyword-only at
the installed source API boundary. Positional integer `init` arguments are
rejected so removed legacy communicator handles cannot silently bind to
non-communicator options.

The checked module-level public-symbol boundary for those modules is
`tests/public_symbol_allowlist.txt`. Any module-level public symbol added to
`src/ftimer.F90`, `src/ftimer_core.F90`, `src/ftimer_openmp.F90`, or
`src/ftimer_types.F90` must be added there intentionally and documented here as
either stable API, unstable public-by-necessity API, or test-only API. The
allowlist check intentionally requires default-private modules and standalone
`public :: name` declarations so new module-level exports cannot bypass the
checked boundary through implicit visibility or declaration attributes.

## Stable user API

Stable public symbols in `ftimer`:

- `ftimer_guard_t`
- `ftimer_init`
- `ftimer_finalize`
- `ftimer_start`
- `ftimer_stop`
- `ftimer_scope`
- `ftimer_start_id`
- `ftimer_stop_id`
- `ftimer_lookup`
- `ftimer_reset`
- `ftimer_get_summary`
- `ftimer_mpi_summary`
- `ftimer_mpi_union_summary`
- `ftimer_print_summary`
- `ftimer_write_summary`
- `ftimer_write_summary_csv`
- `ftimer_print_mpi_summary`
- `ftimer_write_mpi_summary`
- `ftimer_write_mpi_summary_csv`
- `ftimer_print_mpi_union_summary`
- `ftimer_write_mpi_union_summary`
- `ftimer_write_mpi_union_summary_csv`
- `ftimer_default_instance`

Stable public symbols in `ftimer_core`:

- `ftimer_t`
- `ftimer_oop_guard_t`
- `ftimer_oop_scope`

Stable public symbols in `ftimer_openmp`:

- `FTIMER_OPENMP_MODE_THREAD_LANES`
- `ftimer_openmp_config_t`
- `ftimer_openmp_parallel_region_t`
- `ftimer_openmp_t`

Stable public symbols in `ftimer_types`:

- `FTIMER_SUCCESS`
- `FTIMER_ERR_NOT_INIT`
- `FTIMER_ERR_NOT_IMPLEMENTED`
- `FTIMER_ERR_UNKNOWN`
- `FTIMER_ERR_ACTIVE`
- `FTIMER_ERR_MISMATCH`
- `FTIMER_ERR_MPI_INCON`
- `FTIMER_ERR_IO`
- `FTIMER_ERR_INVALID_NAME`
- `FTIMER_NAME_LEN`
- `FTIMER_MISMATCH_STRICT`
- `FTIMER_MISMATCH_WARN`
- `FTIMER_MISMATCH_REPAIR`
- `FTIMER_EVENT_START`
- `FTIMER_EVENT_STOP`
- `wp`
- `ftimer_metadata_t`
- `ftimer_context_diagnostic_t`
- `ftimer_summary_entry_t`
- `ftimer_summary_t`
- `ftimer_mpi_summary_entry_t`
- `ftimer_mpi_summary_t`
- `ftimer_mpi_union_summary_entry_t`
- `ftimer_mpi_union_summary_t`
- `ftimer_clock_func`
- `ftimer_hook_proc`

## Unstable public-by-necessity symbols

The following names are visible from stable modules because current Fortran
module layering requires helper modules to share implementation storage or
because the scoped guard implementations delegate exact activation ownership to
the OOP core. They are not part of the stable downstream contract and may
change, move, narrow, or disappear before a future compatibility boundary:

- `ftimer_call_stack_t`
- `ftimer_context_list_t`
- `ftimer_segment_t`
- `ftimer_internal_start_scope_activation`
- `ftimer_internal_stop_scope_activation`

Downstream application code should not import or declare those names unless it
is deliberately coupling to fTimer internals. Supported user code should use
the procedural `ftimer_scope()` helper, the OOP pointer-based `ftimer_oop_scope()`
helper, or explicit `start`/`stop` instead of the internal scoped activation
hooks, and should use summary result types instead of the runtime storage types.

## Test-only public symbols

The following names are public only in `FTIMER_BUILD_TESTS` helper builds and
are never installed as stable API:

- `ftimer_test_get_state`
- `ftimer_test_set_call_count`
- `ftimer_test_state_t`

## Installed implementation artifacts

Installed implementation module artifacts: `ftimer_clock.mod`,
`ftimer_summary.mod`, `ftimer_mpi.mod`.

Those implementation module files may be present in the installed include tree
because Fortran consumers need a coherent compiler module artifact set when they
import the supported modules above. They are not stable import targets, and
their installed visibility does not promote the corresponding source modules
into supported API. Downstream code should not import `ftimer_clock`,
`ftimer_summary`, or `ftimer_mpi` directly unless it is deliberately accepting
implementation-detail coupling.

The exact installed module artifact set is curated and smoke-tested. Extra
compiler-specific companion artifacts should be added only when a validated
compiler requires them for downstream package consumption, and each such
exception should be documented explicitly.
