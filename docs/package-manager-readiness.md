# Spack and EasyBuild Readiness Note

Issue #311 records a package-manager readiness spike for Spack and EasyBuild.
This note is evidence and maintainer guidance, not an in-repository package
recipe. fTimer does not currently own, ship, test, or maintain Spack
`package.py` or EasyBuild easyconfig files. Do not treat any prototype below as
a copy-paste-ready recipe unless a later issue accepts that support cost.

Status date: 2026-06-09.

## Spike Summary

fTimer appears package-manager friendly for source builds that follow its
existing CMake install contract. The package recipe should configure, build,
install, and then run a downstream `find_package(fTimer CONFIG REQUIRED)`
consumer against the installed prefix. No fTimer source patches were identified
for the serial, MPI, OpenMP, or MPI+OpenMP feature modes.

The main packaging boundary is that Fortran `.mod` files are compiler-,
wrapper-, and feature-mode-specific. A package manager should treat serial,
MPI, OpenMP, and MPI+OpenMP builds as distinct concrete packages or variants
whose consumers use the same compiler family, MPI wrapper family, and enabled
feature set as the installed package.

Local package-manager execution was not available during this spike: `spack`
and `eb` were not on `PATH` in the validation environment. The out-of-tree
prototypes below were therefore checked against fTimer's CMake options,
install layout, and installed-consumer contract rather than installed through
Spack or EasyBuild directly.

## Out-of-Tree Spack Prototype

A Spack package can be modeled as a `CMakePackage` with `mpi` and `openmp`
variants. The serial prototype is the base case; MPI, OpenMP, and MPI+OpenMP
add dependencies, CMake option flips, and the feature-mode caveats below.

**Maintainer-only sketch, not a maintained Spack recipe:** this block is
deliberately incomplete, was not executed by Spack during the readiness spike,
and contains placeholders for a future upstream/site maintainer to replace with
real ownership metadata, release versions, checksums, and package-manager
validation.

```python
from spack.package import *


class Ftimer(CMakePackage):
    """Lightweight wall-clock timing library for modern Fortran."""

    homepage = "https://github.com/jaharris87/fTimer"
    url = "https://github.com/jaharris87/fTimer/archive/refs/tags/v0.2.0.tar.gz"

    maintainers("TODO-site-or-upstream-maintainer")

    version("0.2.0", sha256="TODO-release-tarball-sha256")

    variant("mpi", default=False, description="Enable MPI timing support")
    variant("openmp", default=False, description="Enable OpenMP timing support")

    depends_on("cmake@3.16:", type="build")
    depends_on("cmake@3.24:", when="+openmp", type="build")
    depends_on("fortran", type="build")
    depends_on("mpi", when="+mpi")

    def cmake_args(self):
        return [
            self.define_from_variant("FTIMER_USE_MPI", "mpi"),
            self.define_from_variant("FTIMER_USE_OPENMP", "openmp"),
            self.define("FTIMER_BUILD_TESTS", False),
            self.define("FTIMER_BUILD_SMOKE_TESTS", False),
            self.define("FTIMER_BUILD_EXAMPLES", False),
            self.define("FTIMER_BUILD_BENCH", False),
        ]
```

Spack support assumptions:

- Use Spack's selected Fortran compiler for serial and OpenMP packages.
- Use the selected MPI provider's Fortran wrapper for `+mpi`, or otherwise
  ensure CMake's `MPI::MPI_Fortran` target and the active compiler pass
  fTimer's `mpi_f08` configure probes.
- Add an install-time or post-install smoke check that builds a tiny external
  CMake consumer with `CMAKE_PREFIX_PATH` set to the installed prefix.
- Keep `+openmp` off by default until the selected compiler/runtime pair is
  validated by fTimer's OpenMP configure probe.
- The prototype conservatively requires CMake 3.24 or newer for `+openmp` so
  LLVM Flang OpenMP packages have the compiler-id support fTimer requires.
  Site recipes that scope OpenMP support to GNU Fortran may relax that
  requirement after validating their selected compiler/runtime pair.

## Out-of-Tree EasyBuild Prototype

EasyBuild can use `CMakeMake` with one easyconfig per feature mode and
toolchain. The serial easyconfig is the base case:

**Maintainer-only sketch, not a maintained EasyBuild easyconfig:** this block
is deliberately incomplete, was not executed by EasyBuild during the readiness
spike, and contains placeholders for a future site maintainer to replace with a
real toolchain, dependency versions, checksums, and package-manager validation.

```python
easyblock = 'CMakeMake'

name = 'fTimer'
version = '0.2.0'

homepage = 'https://github.com/jaharris87/fTimer'
description = 'Lightweight wall-clock timing library for modern Fortran.'

toolchain = {'name': 'GCC', 'version': 'TODO'}
source_urls = ['https://github.com/jaharris87/fTimer/archive/refs/tags/']
sources = ['v%(version)s.tar.gz']
checksums = ['TODO-release-tarball-sha256']

builddependencies = [('CMake', 'TODO')]

configopts = ' '.join([
    '-DFTIMER_BUILD_TESTS=OFF',
    '-DFTIMER_BUILD_SMOKE_TESTS=OFF',
    '-DFTIMER_BUILD_EXAMPLES=OFF',
    '-DFTIMER_BUILD_BENCH=OFF',
])

sanity_check_paths = {
    'files': [
        'lib/cmake/fTimer/fTimerConfig.cmake',
        'lib/libftimer.a',
        'include/ftimer/ftimer.mod',
        'share/doc/fTimer/installed-api.md',
    ],
    'dirs': ['include/ftimer'],
}

moduleclass = 'tools'
```

EasyBuild feature-mode deltas:

- MPI: use an MPI-enabled toolchain or `toolchainopts = {'usempi': True}` as
  appropriate for the site toolchain, add `-DFTIMER_USE_MPI=ON`, and run a
  two-rank downstream consumer sanity check when the site permits `mpiexec`.
- OpenMP: add `toolchainopts = {'openmp': True}` as appropriate for the
  selected toolchain and add `-DFTIMER_USE_OPENMP=ON`.
- MPI+OpenMP: combine the MPI and OpenMP deltas in a separate easyconfig or
  version suffix so the installed `.mod` artifacts are not mixed with serial
  or single-feature installs.

## Variant Readiness

| Variant | Readiness | Required patches | Unsupported assumptions and blockers |
| --- | --- | --- | --- |
| Serial | Package-manager friendly. | None identified. | Requires a Fortran compiler supported by CMake. Release validation covers GNU Fortran and LLVM Flang smoke/library builds; other compilers remain plausible but unvalidated. |
| MPI | Package-manager friendly when the package manager selects a coherent MPI Fortran wrapper stack. | None identified. | Requires `mpi_f08`, `type(MPI_Comm)`, and `MPI_Type_match_size` support. Plain compiler plus discovered MPI is supported only if fTimer's configure probes pass. Consumers must stay within the MPI lifetime contract. |
| OpenMP | Package-manager friendly for validated compiler/runtime pairs. | None identified. | Requires CMake to resolve `OpenMP::OpenMP_Fortran` and requires fTimer's OpenMP master-thread runtime probe to execute successfully. LLVM Flang OpenMP validation requires CMake 3.24 or newer. |
| MPI+OpenMP | Package-manager friendly, but more site-sensitive than the other modes. | None identified. | Requires the MPI assumptions plus the OpenMP assumptions in the same toolchain environment. Permanent CI currently covers the OpenMPI wrapper hybrid path; MPICH hybrid has focused local evidence but not permanent CI coverage. |
| Cross-compiling or execution-restricted OpenMP | Conditional. | None identified. | The OpenMP configure probe cannot run without `CMAKE_CROSSCOMPILING_EMULATOR`. `FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK=ON` is available only after an external maintainer validates equivalent OpenMP runtime semantics for the selected compiler/runtime pair. |

## Recommendation

Recommended action: docs clarification plus future upstream recipe
contribution.

Specifically:

- Do not add maintained in-repository Spack or EasyBuild recipe files now.
- Keep the existing CMake install/export and installed-consumer tests as the
  source of truth for package behavior.
- Consider an upstream Spack recipe contribution after a release tarball and
  checksum are available, using `mpi` and `openmp` variants and an external
  CMake consumer smoke check.
- Treat EasyBuild support as site recipe guidance unless a maintainer or HPC
  site volunteers to own concrete easyconfigs for its toolchain matrix.
- Document packaging caveats rather than widening fTimer's support boundary:
  compiler-specific `.mod` artifacts, feature-mode-specific prefixes, MPI
  wrapper coherence, OpenMP runtime probing, and cross-compile assumptions.
