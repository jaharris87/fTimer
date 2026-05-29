cmake_minimum_required(VERSION 3.16)

set(install_prefix "${TEST_BINARY_DIR}/prefix")
set(consumer_build_dir "${TEST_BINARY_DIR}/consumer-build")
set(consumer_source_dir "${REPO_ROOT}/tests/install-consumer")
set(test_name "${TEST_NAME}")
set(installed_module_dir "${install_prefix}/include/ftimer")
set(installed_api_note_path "${install_prefix}/share/doc/fTimer/installed-api.md")
set(installed_license_path "${install_prefix}/share/doc/fTimer/LICENSE")

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

set(expected_installed_module_artifacts
  ftimer.mod
  ftimer_clock.mod
  ftimer_core.mod
  ftimer_mpi.mod
  ftimer_summary.mod
  ftimer_types.mod
)

file(GLOB installed_module_artifact_paths LIST_DIRECTORIES FALSE "${installed_module_dir}/*")
set(installed_module_artifact_names)
foreach(installed_module_artifact_path IN LISTS installed_module_artifact_paths)
  get_filename_component(installed_module_artifact_name "${installed_module_artifact_path}" NAME)
  list(APPEND installed_module_artifact_names "${installed_module_artifact_name}")
endforeach()

list(SORT expected_installed_module_artifacts)
list(SORT installed_module_artifact_names)

if(NOT installed_module_artifact_names STREQUAL expected_installed_module_artifacts)
  list(JOIN expected_installed_module_artifacts ", " expected_installed_module_artifacts_text)
  list(JOIN installed_module_artifact_names ", " installed_module_artifact_names_text)
  message(FATAL_ERROR
    "Installed module artifact set mismatch.\n"
    "Expected: ${expected_installed_module_artifacts_text}\n"
    "Actual: ${installed_module_artifact_names_text}"
  )
endif()

if(NOT EXISTS "${installed_api_note_path}")
  message(FATAL_ERROR
    "Installed API stability note was not found at '${installed_api_note_path}'."
  )
endif()

file(READ "${REPO_ROOT}/docs/installed-api.md" expected_installed_api_note)
file(READ "${installed_api_note_path}" installed_api_note)
if(NOT installed_api_note STREQUAL expected_installed_api_note)
  message(FATAL_ERROR
    "Installed API stability note does not match docs/installed-api.md."
  )
endif()

if(NOT EXISTS "${installed_license_path}")
  message(FATAL_ERROR
    "Installed BSD license was not found at '${installed_license_path}'."
  )
endif()

file(READ "${REPO_ROOT}/LICENSE" expected_license)
file(READ "${installed_license_path}" installed_license)
if(NOT installed_license STREQUAL expected_license)
  message(FATAL_ERROR
    "Installed BSD license does not match LICENSE."
  )
endif()

set(consumer_configure_args
  -S "${consumer_source_dir}"
  -B "${consumer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_PREFIX_PATH=${install_prefix}
  -DFTIMER_CONSUMER_ENABLE_MPI=${TEST_ENABLE_MPI}
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

if(TEST_ENABLE_MPI)
  set(mpi_consumer_executable "${consumer_build_dir}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}")
  set(legacy_mpi_consumer_executable "${consumer_build_dir}/ftimer_installed_legacy_mpi_consumer${TEST_EXECUTABLE_SUFFIX}")
  if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
    set(configured_mpi_consumer_executable
      "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    if(EXISTS "${configured_mpi_consumer_executable}")
      set(mpi_consumer_executable "${configured_mpi_consumer_executable}")
    endif()
    set(configured_legacy_mpi_consumer_executable
      "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_legacy_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    if(EXISTS "${configured_legacy_mpi_consumer_executable}")
      set(legacy_mpi_consumer_executable "${configured_legacy_mpi_consumer_executable}")
    endif()
  endif()

  if(DEFINED TEST_MPIEXEC_EXECUTABLE AND NOT TEST_MPIEXEC_EXECUTABLE STREQUAL "")
    set(ftimer_mpiexec "${TEST_MPIEXEC_EXECUTABLE}")
  else()
    find_program(ftimer_mpiexec NAMES mpiexec mpirun)
  endif()
  if(NOT ftimer_mpiexec)
    message(STATUS "Skipping ${test_name} MPI run: no mpiexec/mpirun found on PATH.")
    return()
  endif()

  set(ftimer_mpi_launch_command "${ftimer_mpiexec}")
  if(DEFINED TEST_MPIEXEC_NUMPROC_FLAG AND NOT TEST_MPIEXEC_NUMPROC_FLAG STREQUAL "")
    list(APPEND ftimer_mpi_launch_command "${TEST_MPIEXEC_NUMPROC_FLAG}" 2)
  else()
    list(APPEND ftimer_mpi_launch_command -n 2)
  endif()
  if(DEFINED TEST_MPIEXEC_PREFLAGS AND NOT TEST_MPIEXEC_PREFLAGS STREQUAL "")
    list(APPEND ftimer_mpi_launch_command ${TEST_MPIEXEC_PREFLAGS})
  endif()
  list(APPEND ftimer_mpi_launch_command "${mpi_consumer_executable}")
  if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_mpi_launch_command ${TEST_MPIEXEC_POSTFLAGS})
  endif()

  execute_process(
    COMMAND ${ftimer_mpi_launch_command}
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE mpi_consumer_run_result
  )
  if(NOT mpi_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package MPI consumer executable exited with a nonzero status.")
  endif()

  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_summary.txt")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_summary.txt.")
  endif()

  set(ftimer_legacy_mpi_launch_command "${ftimer_mpiexec}")
  if(DEFINED TEST_MPIEXEC_NUMPROC_FLAG AND NOT TEST_MPIEXEC_NUMPROC_FLAG STREQUAL "")
    list(APPEND ftimer_legacy_mpi_launch_command "${TEST_MPIEXEC_NUMPROC_FLAG}" 2)
  else()
    list(APPEND ftimer_legacy_mpi_launch_command -n 2)
  endif()
  if(DEFINED TEST_MPIEXEC_PREFLAGS AND NOT TEST_MPIEXEC_PREFLAGS STREQUAL "")
    list(APPEND ftimer_legacy_mpi_launch_command ${TEST_MPIEXEC_PREFLAGS})
  endif()
  list(APPEND ftimer_legacy_mpi_launch_command "${legacy_mpi_consumer_executable}")
  if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_legacy_mpi_launch_command ${TEST_MPIEXEC_POSTFLAGS})
  endif()

  execute_process(
    COMMAND ${ftimer_legacy_mpi_launch_command}
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE legacy_mpi_consumer_run_result
  )
  if(NOT legacy_mpi_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package legacy MPI consumer executable exited with a nonzero status.")
  endif()

  if(NOT EXISTS "${consumer_build_dir}/consumer_legacy_mpi_summary.txt")
    message(FATAL_ERROR "Installed-package legacy MPI consumer did not write consumer_legacy_mpi_summary.txt.")
  endif()
endif()
