# fTimer Installed API Stability

Stable source-level modules: `ftimer`, `ftimer_core`, `ftimer_types`.

The supported source-level import surface is intentionally narrow:

- `use ftimer` for the procedural API and default timer instance
- `use ftimer_core` for `type(ftimer_t)` and its OOP methods
- `use ftimer_types` for shared constants, status codes, callback interfaces, and summary types

Installed implementation module artifacts: `ftimer_clock.mod`, `ftimer_summary.mod`, `ftimer_mpi.mod`.

Those implementation module files may be present in the installed include tree because Fortran consumers need a coherent compiler module artifact set when they import the supported modules above. They are not stable import targets, and their installed visibility does not promote the corresponding source modules into supported API. Downstream code should not import `ftimer_clock`, `ftimer_summary`, or `ftimer_mpi` directly unless it is deliberately accepting implementation-detail coupling.

The exact installed module artifact set is curated and smoke-tested. Extra compiler-specific companion artifacts should be added only when a validated compiler requires them for downstream package consumption, and each such exception should be documented explicitly.
