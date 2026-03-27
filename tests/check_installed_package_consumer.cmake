cmake_minimum_required(VERSION 3.16)

set(install_prefix "${TEST_BINARY_DIR}/prefix")
set(consumer_build_dir "${TEST_BINARY_DIR}/consumer-build")
set(consumer_source_dir "${REPO_ROOT}/tests/install-consumer")

file(REMOVE_RECURSE "${TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")

set(configure_args
  -S "${REPO_ROOT}"
  -B "${TEST_BINARY_DIR}/producer-build"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_INSTALL_PREFIX=${install_prefix}
  -DFTIMER_BUILD_SMOKE_TESTS=OFF
  -DFTIMER_BUILD_TESTS=OFF
  -DFTIMER_BUILD_EXAMPLES=OFF
  -DFTIMER_BUILD_BENCH=OFF
)

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED CMAKE_Fortran_COMPILER AND NOT CMAKE_Fortran_COMPILER STREQUAL "")
  list(APPEND configure_args -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER})
endif()

if(DEFINED CMAKE_BUILD_TYPE AND NOT CMAKE_BUILD_TYPE STREQUAL "")
  list(APPEND configure_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${configure_args}
  RESULT_VARIABLE producer_configure_result
)
if(NOT producer_configure_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure the producer install tree.")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${TEST_BINARY_DIR}/producer-build"
  RESULT_VARIABLE producer_build_result
)
if(NOT producer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the producer install tree.")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --install "${TEST_BINARY_DIR}/producer-build"
  RESULT_VARIABLE producer_install_result
)
if(NOT producer_install_result EQUAL 0)
  message(FATAL_ERROR "Failed to install the producer package.")
endif()

set(consumer_configure_args
  -S "${consumer_source_dir}"
  -B "${consumer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_PREFIX_PATH=${install_prefix}
)

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED CMAKE_Fortran_COMPILER AND NOT CMAKE_Fortran_COMPILER STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER})
endif()

if(DEFINED CMAKE_BUILD_TYPE AND NOT CMAKE_BUILD_TYPE STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_configure_args}
  RESULT_VARIABLE consumer_configure_result
)
if(NOT consumer_configure_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure the installed-package consumer.")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" --build "${consumer_build_dir}"
  RESULT_VARIABLE consumer_build_result
)
if(NOT consumer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the installed-package consumer.")
endif()
