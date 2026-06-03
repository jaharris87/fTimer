cmake_minimum_required(VERSION 3.16)

project(fTimer
  VERSION 0.2.0
  LANGUAGES Fortran
  DESCRIPTION "Lightweight, correctness-first wall-clock timing library for Fortran"
)

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

function(ftimer_try_compile_mpi out_var)
  set(_ftimer_mpi_probe_src "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_mpi_probe.F90")
  file(WRITE "${_ftimer_mpi_probe_src}" [=[
program ftimer_mpi_probe
  use mpi_f08
  implicit none
  integer :: ierr
  integer :: rank
  type(MPI_Comm) :: comm

  call MPI_Init(ierr)
  comm = MPI_COMM_WORLD
  call MPI_Comm_rank(comm, rank, ierr)
  call MPI_Finalize(ierr)
end program ftimer_mpi_probe
]=])

  try_compile(_ftimer_mpi_probe_ok
    "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_mpi_probe_build"
    SOURCES "${_ftimer_mpi_probe_src}"
    LINK_LIBRARIES MPI::MPI_Fortran
  )

  set(${out_var} "${_ftimer_mpi_probe_ok}" PARENT_SCOPE)
endfunction()

function(ftimer_try_compile_mpi_datatype_probe out_var)
  set(_ftimer_mpi_datatype_probe_src "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_mpi_datatype_probe.F90")
  file(WRITE "${_ftimer_mpi_datatype_probe_src}" [=[
program ftimer_mpi_datatype_probe
  use, intrinsic :: iso_fortran_env, only: int64
  use mpi_f08
  implicit none

  integer, parameter :: wp = selected_real_kind(15, 307)
  type(MPI_Datatype) :: dtype
  type(MPI_Errhandler) :: errhandler
  integer :: ierr
  integer :: nbytes

  call MPI_Comm_get_errhandler(MPI_COMM_SELF, errhandler, ierr)
  call MPI_Comm_set_errhandler(MPI_COMM_SELF, MPI_ERRORS_RETURN, ierr)

  nbytes = storage_size(1.0_wp)/8
  call MPI_Type_match_size(MPI_TYPECLASS_REAL, nbytes, dtype, ierr)
  call MPI_Type_size(dtype, nbytes, ierr)

  nbytes = storage_size(0_int64)/8
  call MPI_Type_match_size(MPI_TYPECLASS_INTEGER, nbytes, dtype, ierr)
  call MPI_Type_size(dtype, nbytes, ierr)

  call MPI_Comm_set_errhandler(MPI_COMM_SELF, errhandler, ierr)
  call MPI_Errhandler_free(errhandler, ierr)
end program ftimer_mpi_datatype_probe
]=])

  try_compile(_ftimer_mpi_datatype_probe_ok
    "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_mpi_datatype_probe_build"
    SOURCES "${_ftimer_mpi_datatype_probe_src}"
    LINK_LIBRARIES MPI::MPI_Fortran
  )

  set(${out_var} "${_ftimer_mpi_datatype_probe_ok}" PARENT_SCOPE)
endfunction()

function(ftimer_try_run_openmp_master_probe out_var details_var)
  set(_ftimer_openmp_probe_src "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_openmp_master_probe.F90")
  file(WRITE "${_ftimer_openmp_probe_src}" [=[
program ftimer_openmp_master_probe
  use omp_lib, only: omp_get_num_threads, omp_get_thread_num, omp_set_dynamic
  implicit none

  integer :: master_hits
  integer :: worker_hits
  integer :: threads
  integer :: thread_num
  logical :: master_thread_was_zero

  call omp_set_dynamic(.false.)

  master_hits = 0
  worker_hits = 0
  threads = 0
  master_thread_was_zero = .false.

!$omp parallel num_threads(2) default(shared) private(thread_num)
  thread_num = omp_get_thread_num()
  if (thread_num /= 0) then
!$omp atomic update
    worker_hits = worker_hits + 1
  end if

!$omp master
  master_hits = master_hits + 1
  threads = omp_get_num_threads()
  master_thread_was_zero = (omp_get_thread_num() == 0)
!$omp end master
!$omp end parallel

  if (master_hits /= 1) error stop "OpenMP master region did not execute exactly once"
  if (.not. master_thread_was_zero) error stop "OpenMP master region did not run on thread zero"
  if (worker_hits < 1) error stop "OpenMP parallel region did not create a worker thread"
  if (threads < 2) error stop "OpenMP parallel region did not report two threads"
end program ftimer_openmp_master_probe
]=])

  try_compile(_ftimer_openmp_compile_ok
    "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_openmp_master_probe_compile"
    SOURCES "${_ftimer_openmp_probe_src}"
    LINK_LIBRARIES OpenMP::OpenMP_Fortran
    OUTPUT_VARIABLE _ftimer_openmp_compile_output
  )

  if(NOT _ftimer_openmp_compile_ok)
    string(CONCAT _ftimer_openmp_details
      "compile_result='${_ftimer_openmp_compile_ok}'\n"
      "compile_output:\n${_ftimer_openmp_compile_output}"
    )
    set(${out_var} FALSE PARENT_SCOPE)
    set(${details_var} "${_ftimer_openmp_details}" PARENT_SCOPE)
    return()
  endif()

  if(FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK)
    string(CONCAT _ftimer_openmp_details
      "compile_result='${_ftimer_openmp_compile_ok}'\n"
      "run_result='assumed by FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK'\n"
      "compile_output:\n${_ftimer_openmp_compile_output}"
    )
    set(${out_var} TRUE PARENT_SCOPE)
    set(${details_var} "${_ftimer_openmp_details}" PARENT_SCOPE)
    return()
  endif()

  if(CMAKE_CROSSCOMPILING AND NOT CMAKE_CROSSCOMPILING_EMULATOR)
    string(CONCAT _ftimer_openmp_details
      "compile_result='${_ftimer_openmp_compile_ok}'\n"
      "run_result='not run because CMake is cross-compiling without CMAKE_CROSSCOMPILING_EMULATOR'\n"
      "compile_output:\n${_ftimer_openmp_compile_output}"
    )
    set(${out_var} FALSE PARENT_SCOPE)
    set(${details_var} "${_ftimer_openmp_details}" PARENT_SCOPE)
    return()
  endif()

  try_run(_ftimer_openmp_run_result _ftimer_openmp_compile_ok
    "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_openmp_master_probe_run"
    "${_ftimer_openmp_probe_src}"
    LINK_LIBRARIES OpenMP::OpenMP_Fortran
    COMPILE_OUTPUT_VARIABLE _ftimer_openmp_run_compile_output
    RUN_OUTPUT_VARIABLE _ftimer_openmp_run_output
  )

  string(CONCAT _ftimer_openmp_details
    "compile_result='${_ftimer_openmp_compile_ok}'\n"
    "run_result='${_ftimer_openmp_run_result}'\n"
    "compile_output:\n${_ftimer_openmp_compile_output}\n${_ftimer_openmp_run_compile_output}\n"
    "run_output:\n${_ftimer_openmp_run_output}"
  )

  if(_ftimer_openmp_compile_ok AND _ftimer_openmp_run_result EQUAL 0)
    set(${out_var} TRUE PARENT_SCOPE)
  else()
    set(${out_var} FALSE PARENT_SCOPE)
  endif()

  set(${details_var} "${_ftimer_openmp_details}" PARENT_SCOPE)
endfunction()

# Options
option(FTIMER_USE_MPI "Enable MPI support" OFF)
option(FTIMER_USE_OPENMP "Enable OpenMP master-thread guards and ftimer_openmp worker timing" OFF)
option(
  FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK
  "Assume the OpenMP capability probe passes after compile/link succeeds; intended only for cross-compiling or execution-restricted packaging environments"
  OFF
)
option(FTIMER_BUILD_TESTS "Build pFUnit tests (requires pFUnit)" OFF)
option(FTIMER_BUILD_SMOKE_TESTS "Build Phase 0 smoke tests" ON)
option(FTIMER_BUILD_EXAMPLES "Build example programs" ON)
option(FTIMER_BUILD_BENCH "Build performance measurement harness" OFF)
mark_as_advanced(FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK)

set(FTIMER_PACKAGE_VERSION_COMPATIBILITY SameMinorVersion)

set(FTIMER_PUBLIC_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/ftimer")
set(FTIMER_TEST_LIBRARY_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/testlib")
set(FTIMER_SMOKE_TEST_LIBRARY_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/smokelib")
set(FTIMER_TEST_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/tests")

# MPI
if(FTIMER_USE_MPI)
  find_package(MPI REQUIRED COMPONENTS Fortran)

  ftimer_try_compile_mpi(FTIMER_MPI_TOOLCHAIN_OK)
  if(NOT FTIMER_MPI_TOOLCHAIN_OK)
    message(FATAL_ERROR
      "FTIMER_USE_MPI=ON requires a compiler/toolchain pair that can compile 'use mpi_f08' against the discovered MPI installation.\n"
      "CMake found MPI, but the active Fortran compiler '${CMAKE_Fortran_COMPILER}' failed a configure-time MPI probe.\n"
      "Supported path: select an MPI wrapper compiler from the same toolchain, for example 'FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON ...' or '-DCMAKE_Fortran_COMPILER=mpifort'.\n"
      "Plain compiler + find_package(MPI) is not treated as a documented supported path unless that probe succeeds."
    )
  endif()

  ftimer_try_compile_mpi_datatype_probe(FTIMER_MPI_DATATYPES_PROBE_OK)
  if(NOT FTIMER_MPI_DATATYPES_PROBE_OK)
    message(FATAL_ERROR
      "FTIMER_USE_MPI=ON requires an MPI 'mpi_f08' implementation that exposes MPI_Type_match_size for validating fTimer's real(wp) and integer(int64) reduction datatypes.\n"
      "This configure-time probe intentionally validates the primary mpi_f08 contract."
    )
  endif()
endif()

if(FTIMER_USE_OPENMP)
  set(FTIMER_VALIDATED_OPENMP_COMPILER_IDS GNU LLVMFlang)
  if(CMAKE_VERSION VERSION_LESS 3.24 AND NOT CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON with LLVM Flang requires CMake 3.24 or newer so CMake reports compiler ID 'LLVMFlang'.\n"
      "The active CMake version is ${CMAKE_VERSION}, and the active compiler ID is '${CMAKE_Fortran_COMPILER_ID}' at '${CMAKE_Fortran_COMPILER}'.\n"
      "Supported paths: use GNU Fortran with this CMake version, or upgrade CMake for LLVM Flang OpenMP validation."
    )
  endif()

  if(NOT CMAKE_Fortran_COMPILER_ID IN_LIST FTIMER_VALIDATED_OPENMP_COMPILER_IDS)
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON is not currently validated for compiler ID '${CMAKE_Fortran_COMPILER_ID}'.\n"
      "The active compiler is '${CMAKE_Fortran_COMPILER_ID}' at '${CMAKE_Fortran_COMPILER}'.\n"
      "Validated OpenMP compiler IDs: GNU and LLVMFlang.\n"
      "Supported paths: configure with GNU Fortran ('FC=gfortran ...') or LLVM Flang ('FC=flang-19 ...') and a discoverable OpenMP runtime.\n"
      "Other compilers must be added only after fTimer's OpenMP capability probe and smoke coverage validate master-thread guards plus ftimer_openmp worker timing."
    )
  endif()

  find_package(OpenMP COMPONENTS Fortran)
  if(NOT OpenMP_Fortran_FOUND OR NOT TARGET OpenMP::OpenMP_Fortran)
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON requires CMake to resolve OpenMP::OpenMP_Fortran for the active validated compiler.\n"
      "CMake could not find the Fortran OpenMP runtime for compiler ID '${CMAKE_Fortran_COMPILER_ID}' at '${CMAKE_Fortran_COMPILER}'.\n"
      "Supported paths: configure with GNU Fortran or LLVM Flang plus a discoverable OpenMP runtime. On platforms where LLVM Flang's libomp is not auto-discovered, pass '-DOpenMP_ROOT=/path/to/libomp'."
    )
  endif()

  ftimer_try_run_openmp_master_probe(FTIMER_OPENMP_MASTER_PROBE_OK FTIMER_OPENMP_MASTER_PROBE_DETAILS)
  if(NOT FTIMER_OPENMP_MASTER_PROBE_OK)
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON requires a validated compiler/runtime pair that passes fTimer's OpenMP capability probe.\n"
      "The probe compiles, links, and runs a Fortran program using omp_lib, a two-thread parallel region, omp_get_thread_num introspection, and !$omp master semantics.\n"
      "For cross-compiling or execution-restricted package builds, maintainers may set FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK=ON after independently validating equivalent runtime semantics for the selected compiler/runtime pair.\n"
      "Active compiler ID: '${CMAKE_Fortran_COMPILER_ID}' at '${CMAKE_Fortran_COMPILER}'.\n"
      "${FTIMER_OPENMP_MASTER_PROBE_DETAILS}"
    )
  endif()
endif()

# Library
add_subdirectory(src)

# Tests
if(FTIMER_BUILD_TESTS OR FTIMER_BUILD_SMOKE_TESTS OR FTIMER_BUILD_BENCH)
  enable_testing()
endif()

if(FTIMER_BUILD_TESTS)
  # pFUnit
  if(DEFINED ENV{PFUNIT_DIR})
    set(PFUNIT_DIR $ENV{PFUNIT_DIR} CACHE PATH "pFUnit install prefix")
  endif()
  find_package(PFUNIT REQUIRED HINTS ${PFUNIT_DIR})
endif()

if(FTIMER_BUILD_TESTS OR FTIMER_BUILD_SMOKE_TESTS)
  add_subdirectory(tests)
endif()

# Examples
if(FTIMER_BUILD_EXAMPLES)
  add_subdirectory(examples)
endif()

# Benchmark / measurement harness
if(FTIMER_BUILD_BENCH)
  add_subdirectory(bench)
endif()

# Install
install(TARGETS ftimer
  EXPORT fTimerTargets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/ftimer
)

configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/cmake/install_ftimer_modules.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/install_ftimer_modules.cmake
  @ONLY
)

install(SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/install_ftimer_modules.cmake)

install(EXPORT fTimerTargets
  FILE fTimerTargets.cmake
  NAMESPACE fTimer::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/fTimer
)

configure_package_config_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/cmake/fTimerConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfig.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/fTimer
)

write_basic_package_version_file(
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfigVersion.cmake
  VERSION ${PROJECT_VERSION}
  COMPATIBILITY ${FTIMER_PACKAGE_VERSION_COMPATIBILITY}
)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfig.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfigVersion.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/fTimer
)

install(FILES
  ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
  ${CMAKE_CURRENT_SOURCE_DIR}/docs/installed-api.md
  DESTINATION ${CMAKE_INSTALL_DOCDIR}
)
