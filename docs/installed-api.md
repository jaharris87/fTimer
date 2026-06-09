# fTimer Installed API Stability

Stable source-level modules: `ftimer`, `ftimer_core`, `ftimer_openmp`, `ftimer_types`.

Pre-1.0 CMake package version compatibility is limited to the same minor release line. A `0.2.z` package can satisfy `find_package(fTimer 0.2 CONFIG REQUIRED)` and compatible `0.2.x` requests, but different `0.x` minor lines are not considered compatible. This package does not promise all-`0.x` source or compiler-module compatibility. The `0.2` package line is the compatibility boundary for the production-readiness call-count widening: local `ftimer_summary_entry_t%call_count` plus MPI `min_call_count`/`max_call_count` summary/result fields are `integer(int64)` on this line. MPI `avg_call_count` remains `real(wp)` and may differ from the exact integer average by representable real rounding for signed-64-bit values that `real(wp)` cannot represent exactly. Local structured summaries also expose context-cardinality diagnostics through `ftimer_summary_t%total_contexts`, `ftimer_summary_t%max_contexts_per_timer`, `ftimer_summary_t%context_diagnostics`, `ftimer_summary_t%num_context_diagnostics`, and `ftimer_summary_entry_t%timer_context_count`; these fields do not change text or CSV schemas.

The supported source-level import surface is intentionally narrow:

- `use ftimer` for the procedural API and default timer instance
- `use ftimer_core` for `type(ftimer_t)`, its OOP methods, and the
  pointer-based `ftimer_oop_scope` scoped guard helper
- `use ftimer_openmp` for the explicit opt-in OpenMP timing API surface. In
  this release line, its lifecycle/configuration, timer catalog,
  timed-region, id-first thread-lane timing, stopped-run local summary, strict
  MPI+OpenMP summary, sparse MPI+OpenMP union summary, text report, and CSV
  entry points are real.
  `ftimer_openmp_t%init` requires `config=` and accepts `comm=` only by keyword
  in MPI builds. When `comm=` is omitted, MPI+OpenMP builds capture
  `MPI_COMM_WORLD`; pass `comm=` to use a caller-owned communicator explicitly.
  The MPI communicator handle is used by the strict and sparse union hybrid
  MPI+OpenMP summary/report families; local OpenMP summary/report behavior does
  not consume it.
  Registered timer ids remain valid across `reset()` and are invalidated
  across `finalize()`/reinit without being recycled in the same object.
  Current `ftimer_openmp_t` timing uses the non-MPI wall clock even in
  MPI-enabled packages, so worker timing does not call `MPI_Wtime()` from
  OpenMP threads or require an `MPI_Init_thread` support level. The strict
  hybrid summary family is collective over the init-captured communicator,
  returns `ftimer_mpi_openmp_summary_t`, and uses separate
  `summary_kind=mpi_openmp` CSV output rather than the existing rank-only MPI
  schemas. It requires identical timer descriptors and eligible lane
  participation on every rank. The sparse union hybrid family is a separate
  collective surface returning `ftimer_mpi_openmp_union_summary_t` and writing
  `summary_kind=mpi_openmp_union` CSV rows with explicit rank/lane
  participation metadata; it does not change the strict hybrid API.
  `config%max_lanes` counts the serial lane plus worker lanes. Serial timing
  uses lane 0. In `FTIMER_USE_OPENMP=ON` packages, worker timing inside an
  explicitly opened level-1 timed OpenMP region uses one lane per OpenMP
  thread id. OpenMP-region rejection and bounded worker diagnostics require a
  package built with `FTIMER_USE_OPENMP=ON`. Calls made inside an OpenMP
  parallel region without `ierr` queue bounded diagnostics instead of writing
  unordered stderr, except for valid worker `start_id`/`stop_id` calls inside an
  open timed region. Later serial lifecycle calls that clear diagnostics emit
  one aggregate diagnostic and proceed when `ierr` is absent. When `ierr` is
  present, a lifecycle call that observes queued worker diagnostics returns the
  first queued status without stderr and leaves lifecycle state unchanged; repeat
  the lifecycle call after that explicit drain to proceed. In non-OpenMP
  packages, this module is supported only for serial-context lifecycle/catalog/
  timing use. The local OpenMP summary family is separate from `ftimer_summary_t`
  and reports participation-aware lane aggregates rather than serial snapshot
  fields.
- `use ftimer_types` for shared constants, status codes, callback interfaces, and summary types

The source examples that exercise the installed import paths are
`examples/openmp_example.F90` for the compatibility carve-out,
`examples/openmp_worker_example.F90` for true OpenMP worker timing through
`use ftimer_openmp`, and `examples/mpi_openmp_example.F90` for strict plus
sparse union MPI+OpenMP hybrid timing through the same object API. Existing
serial, pure-MPI, and compatibility users do not need source changes to keep
their current behavior.

## MPI lifecycle and communicator ownership

MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`.
The installed MPI-enabled package uses `MPI_Wtime()` as its build-default clock
and its MPI summary/report entry points use MPI collectives, so pre-init or
post-finalize use is outside the supported runtime contract.
The explicit `ftimer_openmp_t` worker runtime is the exception to the clock
rule above: worker timing currently uses the non-MPI wall clock. The stored
communicator is used later at strict and sparse union hybrid summary/report calls, not during
timed OpenMP regions.

`init(config=...)` in an MPI build captures `MPI_COMM_WORLD` by default.
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

## Public-surface change map

This map is a contributor checklist for intentional public-surface changes. It
does not apply to private implementation changes that leave source imports,
installed artifacts, package-version behavior, report text, and CSV schemas
unchanged. The default answer for a proposed new public surface remains "no"
unless a linked issue explains the user need, compatibility boundary, and
validation plan.

Use the map when a PR changes any of these surfaces:

- stable or unstable module-level public symbols in `ftimer`, `ftimer_core`,
  `ftimer_openmp`, or `ftimer_types`;
- public fields or procedure bindings on stable installed types;
- installed `.mod` artifacts, installed docs, or CMake package version
  compatibility behavior;
- text report fields, CSV headers, `format_version`, `summary_kind`,
  append-compatibility rules, or schema-family membership;
- supported examples, installed-consumer paths, release claims, or CI jobs that
  prove one of those contracts.

Representative dry-run recorded for #307: promote the existing
`ftimer_summary_entry_t%timer_context_count` structured-summary field into the
local/strict-MPI text report and CSV schema. This PR does not make that change;
the dry-run exists only to expose the blast radius.

| Surface | Dry-run movement |
| --- | --- |
| Source declarations and formatting | `src/ftimer_types.F90` already exposes the structured field. A real report/CSV promotion would still move `src/ftimer_summary.F90` report formatting and `src/ftimer_core_summary_bindings.F90` local/strict-MPI CSV headers, rows, and append validation. A new entry point would also move `src/ftimer.F90`, `src/ftimer_core.F90`, and the public symbol allowlist. |
| Public symbol and installed API docs | Any new module-level symbol must update `tests/public_symbol_allowlist.txt` and this document's stable, unstable, or test-only classification. Stable type-field, report, or CSV promotions must update this document even when no module-level symbol changes. |
| CSV/schema docs and fixtures | `docs/csv-schema.md`, `README.md` CSV text, `docs/troubleshooting.md` if user-facing remedies change, `tests/check_csv_schema_docs.cmake`, and the reader-aid fixtures under `tests/fixtures/csv-schema/` must either move together or explicitly state why the schema family is unchanged. |
| Behavioral and contract tests | Local report/CSV behavior would need pFUnit coverage in `tests/test_summary.pf`, `tests/test_file_output.pf`, and procedural parity in `tests/test_procedural_api.pf`. MPI, OpenMP, or hybrid surfaces additionally require the matching `tests/mpi/` or OpenMP smoke tests and append-validation checks. |
| Examples and installed consumers | If the promoted surface is part of the supported user story, update the relevant `examples/*.F90` and `tests/install-consumer/*.F90` path. If examples should not change, record that decision so the surface is not accidentally advertised. |
| Installed artifacts and package version | Changes to the installed `.mod` artifact set, installed docs, or pre-1.0 compatibility rule must update `CMakeLists.txt`, `cmake/install_ftimer_modules.cmake.in` as applicable, and `tests/check_installed_package_consumer.cmake`, including package-version probes when the compatibility boundary changes. |
| Release evidence and CI | Update `docs/release-evidence.md`, `docs/release.md`, and any affected `.github/workflows/ci.yml` job names or filters when the release claim or proof path changes. Keep evidence narrow: local/strict MPI CSV, sparse MPI union CSV, OpenMP CSV, strict hybrid CSV, and sparse hybrid CSV are separate schema families. |

For related change-amplification examples, #312, #314, #315, and #316 identify
concrete API, CSV, report, and install-contract follow-ups, while #313 covers
test locality. Those issues should own their specific implementation scopes;
this map only keeps the shared public-surface blast radius visible.

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
- `ftimer_mpi_openmp_rank_t`
- `ftimer_mpi_openmp_summary_entry_t`
- `ftimer_mpi_openmp_summary_t`
- `ftimer_mpi_openmp_union_rank_t`
- `ftimer_mpi_openmp_union_summary_entry_t`
- `ftimer_mpi_openmp_union_summary_t`
- `ftimer_openmp_config_t`
- `ftimer_openmp_parallel_region_t`
- `ftimer_openmp_summary_entry_t`
- `ftimer_openmp_summary_t`
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
- `ftimer_test_set_next_segment_id`
- `ftimer_test_state_t`

## Installed implementation artifacts

Installed implementation module artifacts: `ftimer_clock.mod`,
`ftimer_csv_validation.mod`, `ftimer_summary.mod`, `ftimer_mpi.mod`.

Fortran `.mod` files are compiler-, toolchain-, and feature-mode-specific
artifacts. A prefix installed by one compiler or MPI/OpenMP mode is intended for
downstream builds that use the matching compiler family, MPI wrapper family,
and fTimer feature mode. Reusing installed module files across compilers or
across serial/MPI/OpenMP mode boundaries is outside the supported package
contract unless a release issue adds explicit validation for that combination.

Those implementation module files may be present in the installed include tree
because Fortran consumers need a coherent compiler module artifact set when they
import the supported modules above. They are not stable import targets, and
their installed visibility does not promote the corresponding source modules
into supported API. Downstream code should not import `ftimer_clock`,
`ftimer_csv_validation`, `ftimer_summary`, or `ftimer_mpi` directly unless it
is deliberately accepting implementation-detail coupling.

The exact installed module artifact set is curated and smoke-tested. Extra
compiler-specific companion artifacts should be added only when a validated
compiler requires them for downstream package consumption, and each such
exception should be documented explicitly.
