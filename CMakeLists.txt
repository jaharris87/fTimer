cmake_minimum_required(VERSION 3.16)

project(fTimer
  VERSION 0.1.0
  LANGUAGES Fortran
  DESCRIPTION "Lightweight, correctness-first wall-clock timing library for Fortran"
)

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

function(ftimer_try_compile_mpi out_var)
  set(_ftimer_mpi_probe_src "${CMAKE_BINARY_DIR}/CMakeFiles/ftimer_mpi_probe.F90")
  file(WRITE "${_ftimer_mpi_probe_src}" [=[
program ftimer_mpi_probe
  use mpi
  implicit none
  integer :: ierr

  call MPI_Init(ierr)
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

# Options
option(FTIMER_USE_MPI "Enable MPI support" OFF)
option(FTIMER_USE_OPENMP "Enable OpenMP master-thread guards" OFF)
option(FTIMER_BUILD_TESTS "Build pFUnit tests (requires pFUnit)" OFF)
option(FTIMER_BUILD_SMOKE_TESTS "Build Phase 0 smoke tests" ON)
option(FTIMER_BUILD_EXAMPLES "Build example programs" ON)

# MPI
if(FTIMER_USE_MPI)
  find_package(MPI REQUIRED COMPONENTS Fortran)

  ftimer_try_compile_mpi(FTIMER_MPI_TOOLCHAIN_OK)
  if(NOT FTIMER_MPI_TOOLCHAIN_OK)
    message(FATAL_ERROR
      "FTIMER_USE_MPI=ON requires a compiler/toolchain pair that can compile 'use mpi' against the discovered MPI installation.\n"
      "CMake found MPI, but the active Fortran compiler '${CMAKE_Fortran_COMPILER}' failed a configure-time MPI probe.\n"
      "Supported path: select an MPI wrapper compiler from the same toolchain, for example 'FC=mpifort cmake -B build-mpi -DFTIMER_USE_MPI=ON ...' or '-DCMAKE_Fortran_COMPILER=mpifort'.\n"
      "Plain compiler + find_package(MPI) is not treated as a documented supported path unless that probe succeeds."
    )
  endif()
endif()

if(FTIMER_USE_OPENMP)
  if(NOT CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON is currently supported only with GNU Fortran ('gfortran').\n"
      "The active compiler is '${CMAKE_Fortran_COMPILER_ID}' at '${CMAKE_Fortran_COMPILER}'.\n"
      "Supported path: configure with 'FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON ...'."
    )
  endif()

  find_package(OpenMP COMPONENTS Fortran)
  if(NOT OpenMP_Fortran_FOUND)
    message(FATAL_ERROR
      "FTIMER_USE_OPENMP=ON requires a GNU Fortran toolchain where CMake can find OpenMP::OpenMP_Fortran.\n"
      "CMake could not find the Fortran OpenMP runtime for '${CMAKE_Fortran_COMPILER}'.\n"
      "Supported path: configure with 'FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON ...'."
    )
  endif()
endif()

# Fortran module output directory
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)

# Library
add_subdirectory(src)

# Tests
if(FTIMER_BUILD_TESTS OR FTIMER_BUILD_SMOKE_TESTS)
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

# Install
install(TARGETS ftimer
  EXPORT fTimerTargets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/ftimer
)
install(DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY}/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/ftimer
)

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
  COMPATIBILITY SameMajorVersion
)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfig.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/fTimerConfigVersion.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/fTimer
)
