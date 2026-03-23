cmake_minimum_required(VERSION 3.16)

project(fTimer
  VERSION 0.1.0
  LANGUAGES Fortran
  DESCRIPTION "Lightweight, correctness-first wall-clock timing library for Fortran"
)

# Options
option(FTIMER_USE_MPI "Enable MPI support" OFF)
option(FTIMER_BUILD_TESTS "Build tests (requires pFUnit)" ON)
option(FTIMER_BUILD_EXAMPLES "Build example programs" ON)

# MPI
if(FTIMER_USE_MPI)
  find_package(MPI REQUIRED COMPONENTS Fortran)
endif()

# Fortran module output directory
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)

# Library
add_subdirectory(src)

# Tests
if(FTIMER_BUILD_TESTS)
  enable_testing()
  # pFUnit
  if(DEFINED ENV{PFUNIT_DIR})
    set(PFUNIT_DIR $ENV{PFUNIT_DIR} CACHE PATH "pFUnit install prefix")
  elseif(NOT DEFINED PFUNIT_DIR)
    set(PFUNIT_DIR "/opt/homebrew/PFUNIT-4.16" CACHE PATH "pFUnit install prefix")
  endif()
  find_package(PFUNIT REQUIRED HINTS ${PFUNIT_DIR})
  add_subdirectory(tests)
endif()

# Examples
if(FTIMER_BUILD_EXAMPLES)
  add_subdirectory(examples)
endif()

# Install
include(GNUInstallDirs)
install(TARGETS ftimer
  EXPORT fTimerTargets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY}/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/ftimer
)
install(EXPORT fTimerTargets
  FILE fTimerConfig.cmake
  NAMESPACE fTimer::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/fTimer
)
