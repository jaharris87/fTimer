## Build / Portability Review

You are performing a long-form review as a build and portability reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to find places where the implementation may be logically correct but fragile across compilers, build modes, package-consumer workflows, or HPC environments. Focus on build-system correctness and toolchain portability - not code style issues.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **Does this diff build correctly across the intended modes?** (serial, MPI, smoke-test path, behavioral-test path, installed-package consumer path)
2. **Does this diff introduce compiler- or toolchain-specific assumptions?**
3. **Are CMake options, preprocessing, and dependencies wired correctly and consistently?**
4. **Could this diff work on the author’s machine but fail in another reasonable environment? Why?**
5. **Does the installed/exported package remain usable by downstream consumers?**

### What to Look For

- **Compiler assumptions**: GNU-only behavior, preprocessor assumptions, OpenMP/MPI detection quirks, unsupported Fortran features.
- **Mode drift**: Serial path works but MPI path breaks, smoke tests pass but pFUnit path fails, source build works but installed-package consumer path fails.
- **CMake mistakes**: Missing compile definitions, target-link issues, stale options, inconsistent install/export behavior.
- **Environment leakage**: Local compiler paths, Homebrew-specific assumptions, machine-local PFUNIT_DIR or OpenMP settings baked into the code or docs.
- **Preprocessor fragility**: `#ifdef FTIMER_USE_MPI` or similar guards inconsistent across files.
- **Downstream breakage**: Missing module installation, broken exported targets, missing dependencies in config files.

### How to Report

- Cite the specific file, build mode, and portability risk for each finding.
- Classify each finding: **build break**, **portability risk**, **config drift**, **packaging issue**, or **environment assumption**.
- Explain which environment or build mode would fail and how.
- Prefer findings that would affect CI, common HPC toolchains, or downstream consumers.
- **Begin your response with "## Build / Portability Review" so it is clear which review type this is.**
