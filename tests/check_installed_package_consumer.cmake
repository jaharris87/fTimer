cmake_minimum_required(VERSION 3.16)

set(install_prefix "${TEST_BINARY_DIR}/prefix")
set(consumer_build_dir "${TEST_BINARY_DIR}/consumer-build")
set(consumer_source_dir "${REPO_ROOT}/tests/install-consumer")
set(test_name "${TEST_NAME}")

if(test_name STREQUAL "")
  set(test_name "ftimer_installed_package_consumer")
endif()

if(DEFINED TEST_REQUIRED_COMPILER_NAMES AND NOT TEST_REQUIRED_COMPILER_NAMES STREQUAL "")
  string(REPLACE "," ";" required_compiler_names "${TEST_REQUIRED_COMPILER_NAMES}")
  find_program(ftimer_required_compiler NAMES ${required_compiler_names})
  if(NOT ftimer_required_compiler)
    message(STATUS
      "Skipping ${test_name}: none of the required compilers are available on PATH (${TEST_REQUIRED_COMPILER_NAMES})."
    )
    return()
  endif()

  set(test_fortran_compiler "${ftimer_required_compiler}")
else()
  set(test_fortran_compiler "${CMAKE_Fortran_COMPILER}")
endif()

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

if(TEST_ENABLE_MPI)
  list(APPEND configure_args -DFTIMER_USE_MPI=ON)
endif()

if(TEST_ENABLE_OPENMP)
  list(APPEND configure_args -DFTIMER_USE_OPENMP=ON)
endif()

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
  list(APPEND configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${configure_args}
  RESULT_VARIABLE producer_configure_result
)
if(NOT producer_configure_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure the producer install tree.")
endif()

set(producer_build_args
  --build "${TEST_BINARY_DIR}/producer-build"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_build_args}
  RESULT_VARIABLE producer_build_result
)
if(NOT producer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the producer install tree.")
endif()

set(producer_install_args
  --install "${TEST_BINARY_DIR}/producer-build"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_install_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_install_args}
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

if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_configure_args}
  RESULT_VARIABLE consumer_configure_result
)
if(NOT consumer_configure_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure the installed-package consumer.")
endif()

set(consumer_build_args
  --build "${consumer_build_dir}"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND consumer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_build_args}
  RESULT_VARIABLE consumer_build_result
)
if(NOT consumer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the installed-package consumer.")
endif()

set(consumer_executable "${consumer_build_dir}/ftimer_installed_consumer${TEST_EXECUTABLE_SUFFIX}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  set(configured_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_consumer${TEST_EXECUTABLE_SUFFIX}"
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
  message(FATAL_ERROR "Installed-package consumer executable exited with a nonzero status.")
endif()
