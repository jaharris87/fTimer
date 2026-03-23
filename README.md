# fTimer

A lightweight, correctness-first wall-clock timing library for modern Fortran.

## Status

**Under construction.** Scaffolding is in place; implementation is tracked in [TODO.md](TODO.md).

## Overview

fTimer provides stack-based hierarchical timing with:

- Context-sensitive accounting (same timer name tracked independently under different parents)
- Configurable mismatch handling (strict / warn / repair)
- Structured summary data (`get_summary()`) and formatted text reports (`print_summary()`)
- Exclusive/self time alongside inclusive time
- Optional MPI cross-rank statistics (min/max/avg/imbalance)
- Callback hooks for external profiling tools (PAPI, likwid, etc.)
- Injectable clock for deterministic testing

## Build

```bash
# Serial
cmake -B build && cmake --build build

# MPI
cmake -B build -DFTIMER_USE_MPI=ON && cmake --build build

# Test
ctest --test-dir build --output-on-failure

# Or use the Makefile wrapper
make        # serial build
make mpi    # MPI build
make test   # build + test
```

Requires: gfortran (or compatible Fortran compiler), CMake >= 3.16. Tests require [pFUnit](https://github.com/Goddard-Fortran-Ecosystem/pFUnit).

## License

BSD-3-Clause. See [LICENSE](LICENSE).
