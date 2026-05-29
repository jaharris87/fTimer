cmake_minimum_required(VERSION 3.16)

find_program(ftimer_gfortran_compiler NAMES gfortran)
if(NOT ftimer_gfortran_compiler)
  message(STATUS
    "Skipping FTIMER_USE_OPENMP=OFF/global OpenMP regression: gfortran is not available on PATH."
  )
  return()
endif()

set(install_prefix "${TEST_BINARY_DIR}/prefix")
set(producer_build_dir "${TEST_BINARY_DIR}/producer-build")
set(consumer_source_dir "${REPO_ROOT}/tests/openmp-option-off-global-flags")
set(consumer_build_dir "${TEST_BINARY_DIR}/consumer-build")

file(REMOVE_RECURSE "${TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")

set(producer_configure_args
  -S "${REPO_ROOT}"
  -B "${producer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_Fortran_COMPILER=${ftimer_gfortran_compiler}
  -DCMAKE_Fortran_FLAGS=-fopenmp
  -DCMAKE_INSTALL_PREFIX=${install_prefix}
  -DFTIMER_USE_OPENMP=OFF
  -DFTIMER_BUILD_SMOKE_TESTS=OFF
  -DFTIMER_BUILD_TESTS=OFF
  -DFTIMER_BUILD_EXAMPLES=OFF
  -DFTIMER_BUILD_BENCH=OFF
)

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND producer_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND producer_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_configure_args}
  RESULT_VARIABLE producer_configure_result
)
if(NOT producer_configure_result EQUAL 0)
  message(FATAL_ERROR
    "Failed to configure fTimer with FTIMER_USE_OPENMP=OFF and global -fopenmp flags."
  )
endif()

set(producer_build_args --build "${producer_build_dir}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_build_args}
  RESULT_VARIABLE producer_build_result
)
if(NOT producer_build_result EQUAL 0)
  message(FATAL_ERROR
    "Failed to build fTimer with FTIMER_USE_OPENMP=OFF and global -fopenmp flags."
  )
endif()

set(producer_install_args --install "${producer_build_dir}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_install_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_install_args}
  RESULT_VARIABLE producer_install_result
)
if(NOT producer_install_result EQUAL 0)
  message(FATAL_ERROR
    "Failed to install fTimer built with FTIMER_USE_OPENMP=OFF and global -fopenmp flags."
  )
endif()

set(consumer_configure_args
  -S "${consumer_source_dir}"
  -B "${consumer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_PREFIX_PATH=${install_prefix}
  -DCMAKE_Fortran_COMPILER=${ftimer_gfortran_compiler}
)

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_configure_args}
  RESULT_VARIABLE consumer_configure_result
)
if(NOT consumer_configure_result EQUAL 0)
  message(FATAL_ERROR
    "Failed to configure the FTIMER_USE_OPENMP=OFF/global OpenMP regression consumer."
  )
endif()

set(consumer_build_args --build "${consumer_build_dir}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND consumer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_build_args}
  RESULT_VARIABLE consumer_build_result
)
if(NOT consumer_build_result EQUAL 0)
  message(FATAL_ERROR
    "Failed to build the FTIMER_USE_OPENMP=OFF/global OpenMP regression consumer."
  )
endif()

set(consumer_executable "${consumer_build_dir}/ftimer_openmp_option_off_global_flags${TEST_EXECUTABLE_SUFFIX}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  set(configured_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_openmp_option_off_global_flags${TEST_EXECUTABLE_SUFFIX}"
  )
  if(EXISTS "${configured_consumer_executable}")
    set(consumer_executable "${configured_consumer_executable}")
  endif()
endif()

execute_process(
  COMMAND "${consumer_executable}"
  WORKING_DIRECTORY "${consumer_build_dir}"
  RESULT_VARIABLE consumer_run_result
)
if(NOT consumer_run_result EQUAL 0)
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=OFF/global OpenMP regression consumer exited with a nonzero status."
  )
endif()
