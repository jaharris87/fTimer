cmake_minimum_required(VERSION 3.16)

project(fTimer
  VERSION 0.1.0
  LANGUAGES Fortran
  DESCRIPTION "Lightweight, correctness-first wall-clock timing library for Fortran"
)

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

# Options
option(FTIMER_USE_MPI "Enable MPI support" OFF)
option(FTIMER_USE_OPENMP "Enable OpenMP master-thread guards" OFF)
option(FTIMER_BUILD_TESTS "Build pFUnit tests (requires pFUnit)" OFF)
option(FTIMER_BUILD_SMOKE_TESTS "Build Phase 0 smoke tests" ON)
option(FTIMER_BUILD_EXAMPLES "Build example programs" ON)

set(FTIMER_PUBLIC_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/ftimer")
set(FTIMER_TEST_LIBRARY_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/testlib")
set(FTIMER_TEST_MODULE_DIR "${CMAKE_BINARY_DIR}/mod/tests")

# MPI
if(FTIMER_USE_MPI)
  find_package(MPI REQUIRED COMPONENTS Fortran)
endif()

if(FTIMER_USE_OPENMP)
  find_package(OpenMP REQUIRED COMPONENTS Fortran)
endif()

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
install(DIRECTORY ${FTIMER_PUBLIC_MODULE_DIR}/
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
