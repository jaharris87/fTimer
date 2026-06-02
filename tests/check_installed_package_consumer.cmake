cmake_minimum_required(VERSION 3.16)

set(install_prefix "${TEST_BINARY_DIR}/prefix")
set(consumer_build_dir "${TEST_BINARY_DIR}/consumer-build")
set(consumer_source_dir "${REPO_ROOT}/tests/install-consumer")
set(test_name "${TEST_NAME}")

if(DEFINED TEST_INSTALL_INCLUDEDIR AND NOT TEST_INSTALL_INCLUDEDIR STREQUAL "")
  set(test_install_includedir "${TEST_INSTALL_INCLUDEDIR}")
else()
  set(test_install_includedir "include")
endif()

if(TEST_USE_DESTDIR)
  set(test_destdir "${TEST_BINARY_DIR}/destdir")
  set(effective_install_prefix "${test_destdir}${install_prefix}")
else()
  set(test_destdir "")
  set(effective_install_prefix "${install_prefix}")
endif()

set(installed_api_note_path "${effective_install_prefix}/share/doc/fTimer/installed-api.md")
set(installed_license_path "${effective_install_prefix}/share/doc/fTimer/LICENSE")

set(misinstalled_module_dirs)
if(IS_ABSOLUTE "${test_install_includedir}")
  if(TEST_USE_DESTDIR)
    set(installed_module_dir "${test_destdir}${test_install_includedir}/ftimer")
    list(APPEND misinstalled_module_dirs
      "${test_install_includedir}/ftimer"
      "${test_destdir}${install_prefix}${test_install_includedir}/ftimer"
    )
  else()
    set(installed_module_dir "${test_install_includedir}/ftimer")
    list(APPEND misinstalled_module_dirs
      "${install_prefix}${test_install_includedir}/ftimer"
    )
  endif()
else()
  set(installed_module_dir "${effective_install_prefix}/${test_install_includedir}/ftimer")
endif()

if(test_name STREQUAL "")
  set(test_name "ftimer_installed_package_consumer")
endif()

if(TEST_CLEAN_INSTALL_INCLUDEDIR AND IS_ABSOLUTE "${test_install_includedir}")
  get_filename_component(clean_install_includedir "${test_install_includedir}" ABSOLUTE)
  if(clean_install_includedir STREQUAL "/" OR clean_install_includedir STREQUAL "")
    message(FATAL_ERROR
      "Refusing to clean unsafe TEST_INSTALL_INCLUDEDIR path '${test_install_includedir}'."
    )
  endif()
  if(NOT clean_install_includedir MATCHES "ftimer-absolute-includedir-[0-9a-f]+")
    message(FATAL_ERROR
      "Refusing to clean TEST_INSTALL_INCLUDEDIR path outside the test-owned absolute include root: '${test_install_includedir}'."
    )
  endif()
  file(REMOVE_RECURSE "${clean_install_includedir}")
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
  -DCMAKE_INSTALL_INCLUDEDIR=${test_install_includedir}
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

if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
  list(APPEND configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
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

if(TEST_USE_DESTDIR)
  set(producer_install_command
    "${CMAKE_COMMAND}" -E env "DESTDIR=${test_destdir}" "${CMAKE_COMMAND}" ${producer_install_args}
  )
else()
  set(producer_install_command "${CMAKE_COMMAND}" ${producer_install_args})
endif()

execute_process(
  COMMAND ${producer_install_command}
  RESULT_VARIABLE producer_install_result
)
if(NOT producer_install_result EQUAL 0)
  message(FATAL_ERROR "Failed to install the producer package.")
endif()

function(ftimer_verify_installed_artifacts)
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

  foreach(misinstalled_module_dir IN LISTS misinstalled_module_dirs)
    if(EXISTS "${misinstalled_module_dir}")
      file(GLOB misinstalled_module_artifact_paths
        LIST_DIRECTORIES FALSE
        "${misinstalled_module_dir}/*.mod"
      )
      if(misinstalled_module_artifact_paths)
        message(FATAL_ERROR
          "Absolute CMAKE_INSTALL_INCLUDEDIR module artifacts were installed under an unexpected path '${misinstalled_module_dir}'."
        )
      endif()
    endif()
  endforeach()

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
endfunction()

function(ftimer_expect_integer_mpi_comm_rejected probe_name probe_source)
  set(probe_source_dir "${TEST_BINARY_DIR}/integer-mpi-comm-rejection-src-${probe_name}")
  set(probe_build_dir "${TEST_BINARY_DIR}/integer-mpi-comm-rejection-build-${probe_name}")

  file(REMOVE_RECURSE "${probe_source_dir}" "${probe_build_dir}")
  file(MAKE_DIRECTORY "${probe_source_dir}")
  file(WRITE "${probe_source_dir}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.16)
project(ftimer_integer_mpi_comm_rejection LANGUAGES Fortran)

find_package(fTimer CONFIG REQUIRED)

add_executable(ftimer_integer_mpi_comm_rejection main.F90)
target_link_libraries(ftimer_integer_mpi_comm_rejection PRIVATE fTimer::ftimer)
]=])
  file(WRITE "${probe_source_dir}/main.F90" "${probe_source}")

  set(probe_configure_args
    -S "${probe_source_dir}"
    -B "${probe_build_dir}"
    -G "${CMAKE_GENERATOR}"
    -DCMAKE_PREFIX_PATH=${install_prefix}
  )
  if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
    list(APPEND probe_configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
  endif()
  if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
  endif()
  if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
  endif()
  if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${probe_configure_args}
    RESULT_VARIABLE probe_configure_result
    OUTPUT_VARIABLE probe_configure_output
    ERROR_VARIABLE probe_configure_error
  )
  if(NOT probe_configure_result EQUAL 0)
    message(FATAL_ERROR
      "Failed to configure the installed integer-MPI-comm rejection probe '${probe_name}'.\n"
      "stdout:\n${probe_configure_output}\n"
      "stderr:\n${probe_configure_error}"
    )
  endif()

  set(probe_build_args --build "${probe_build_dir}")
  if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
    list(APPEND probe_build_args --config "${TEST_CONFIG}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${probe_build_args}
    RESULT_VARIABLE probe_build_result
    OUTPUT_VARIABLE probe_build_output
    ERROR_VARIABLE probe_build_error
  )
  if(probe_build_result EQUAL 0)
    message(FATAL_ERROR
      "Installed MPI package accepted legacy integer MPI comm probe '${probe_name}'; expected the build to fail."
    )
  endif()
endfunction()

function(ftimer_expect_integer_mpi_comm_rejected_cases)
  ftimer_expect_integer_mpi_comm_rejected(oop-keyword [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(comm=legacy_comm, ierr=ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-keyword [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(comm=legacy_comm, ierr=ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(oop-positional-single [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(legacy_comm)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-positional-single [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(legacy_comm)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(oop-positional-two-arg [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(legacy_comm, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-positional-two-arg [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(legacy_comm, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])
endfunction()

if(TEST_INSTALL_ONLY)
  ftimer_verify_installed_artifacts()
  return()
endif()

if(NOT DEFINED TEST_PACKAGE_VERSION OR TEST_PACKAGE_VERSION STREQUAL "")
  message(FATAL_ERROR "TEST_PACKAGE_VERSION must be provided.")
endif()
if(NOT DEFINED TEST_PACKAGE_VERSION_MAJOR OR TEST_PACKAGE_VERSION_MAJOR STREQUAL "")
  message(FATAL_ERROR "TEST_PACKAGE_VERSION_MAJOR must be provided.")
endif()
if(NOT DEFINED TEST_PACKAGE_VERSION_MINOR OR TEST_PACKAGE_VERSION_MINOR STREQUAL "")
  message(FATAL_ERROR "TEST_PACKAGE_VERSION_MINOR must be provided.")
endif()
if(NOT DEFINED TEST_PACKAGE_VERSION_PATCH OR TEST_PACKAGE_VERSION_PATCH STREQUAL "")
  message(FATAL_ERROR "TEST_PACKAGE_VERSION_PATCH must be provided.")
endif()
if(NOT DEFINED TEST_PACKAGE_VERSION_COMPATIBILITY OR TEST_PACKAGE_VERSION_COMPATIBILITY STREQUAL "")
  message(FATAL_ERROR "TEST_PACKAGE_VERSION_COMPATIBILITY must be provided.")
endif()

include(CMakePackageConfigHelpers)

function(ftimer_write_synthetic_package_prefix prefix_path package_version)
  set(synthetic_config_dir "${prefix_path}/lib/cmake/fTimer")
  file(MAKE_DIRECTORY "${synthetic_config_dir}")
  file(WRITE "${synthetic_config_dir}/fTimerConfig.cmake" "set(fTimer_FOUND TRUE)\n")
  write_basic_package_version_file(
    "${synthetic_config_dir}/fTimerConfigVersion.cmake"
    VERSION "${package_version}"
    COMPATIBILITY ${TEST_PACKAGE_VERSION_COMPATIBILITY}
  )
endfunction()

function(ftimer_check_package_version_request probe_name requested_version expected_result prefix_path)
  string(REPLACE "." "_" version_probe_fragment "${requested_version}")
  set(version_probe_source_dir
    "${TEST_BINARY_DIR}/version-probes/src-${probe_name}-${version_probe_fragment}"
  )
  set(version_probe_build_dir
    "${TEST_BINARY_DIR}/version-probes/build-${probe_name}-${version_probe_fragment}"
  )

  set(version_probe_cmake [=[
cmake_minimum_required(VERSION 3.16)
project(ftimer_package_version_probe LANGUAGES Fortran)
find_package(fTimer @requested_version@ CONFIG REQUIRED
  PATHS "@prefix_path@"
  NO_DEFAULT_PATH
)
]=])

  string(CONFIGURE "${version_probe_cmake}" version_probe_cmake_configured @ONLY)
  file(MAKE_DIRECTORY "${version_probe_source_dir}")
  file(WRITE "${version_probe_source_dir}/CMakeLists.txt"
    "${version_probe_cmake_configured}"
  )

  set(version_probe_configure_args
    -S "${version_probe_source_dir}"
    -B "${version_probe_build_dir}"
    -G "${CMAKE_GENERATOR}"
    -DCMAKE_PREFIX_PATH=${prefix_path}
  )
  if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
    list(APPEND version_probe_configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
  endif()
  if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
    list(APPEND version_probe_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
  endif()

  if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
    list(APPEND version_probe_configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
  endif()

  if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
    list(APPEND version_probe_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${version_probe_configure_args}
    RESULT_VARIABLE version_probe_result
    OUTPUT_VARIABLE version_probe_output
    ERROR_VARIABLE version_probe_error
  )

  if(expected_result STREQUAL "ACCEPT")
    if(NOT version_probe_result EQUAL 0)
      message(FATAL_ERROR
        "Expected fTimer package version request '${requested_version}' to be accepted.\n"
        "stdout:\n${version_probe_output}\n"
        "stderr:\n${version_probe_error}"
      )
    endif()
  elseif(expected_result STREQUAL "REJECT")
    if(version_probe_result EQUAL 0)
      message(FATAL_ERROR
        "Expected fTimer package version request '${requested_version}' to be rejected."
      )
    endif()
  else()
    message(FATAL_ERROR "Unknown package version expectation '${expected_result}'.")
  endif()
endfunction()

set(current_package_version_request "${TEST_PACKAGE_VERSION}")
set(same_minor_package_version_request
  "${TEST_PACKAGE_VERSION_MAJOR}.${TEST_PACKAGE_VERSION_MINOR}"
)
math(EXPR future_minor_package_version "${TEST_PACKAGE_VERSION_MINOR} + 1")
set(future_minor_package_version_request
  "${TEST_PACKAGE_VERSION_MAJOR}.${future_minor_package_version}.0"
)
math(EXPR same_minor_newer_patch_version "${TEST_PACKAGE_VERSION_PATCH} + 1")
math(EXPR same_minor_too_new_patch_version "${TEST_PACKAGE_VERSION_PATCH} + 2")
set(same_minor_newer_patch_package_version
  "${TEST_PACKAGE_VERSION_MAJOR}.${TEST_PACKAGE_VERSION_MINOR}.${same_minor_newer_patch_version}"
)
set(same_minor_too_new_patch_request
  "${TEST_PACKAGE_VERSION_MAJOR}.${TEST_PACKAGE_VERSION_MINOR}.${same_minor_too_new_patch_version}"
)
if(TEST_PACKAGE_VERSION_MINOR GREATER 0)
  math(EXPR previous_minor_package_version "${TEST_PACKAGE_VERSION_MINOR} - 1")
  set(incompatible_package_version_request
    "${TEST_PACKAGE_VERSION_MAJOR}.${previous_minor_package_version}.0"
  )
else()
  math(EXPR future_major_package_version "${TEST_PACKAGE_VERSION_MAJOR} + 1")
  set(incompatible_package_version_request "${future_major_package_version}.0.0")
endif()

ftimer_check_package_version_request(
  current
  "${current_package_version_request}"
  ACCEPT
  "${install_prefix}"
)
ftimer_check_package_version_request(
  same-minor
  "${same_minor_package_version_request}"
  ACCEPT
  "${install_prefix}"
)
ftimer_check_package_version_request(
  future-minor-request
  "${future_minor_package_version_request}"
  REJECT
  "${install_prefix}"
)
ftimer_check_package_version_request(
  incompatible-minor
  "${incompatible_package_version_request}"
  REJECT
  "${install_prefix}"
)

set(same_minor_newer_patch_prefix
  "${TEST_BINARY_DIR}/version-probes/same-minor-newer-patch-prefix"
)
ftimer_write_synthetic_package_prefix(
  "${same_minor_newer_patch_prefix}"
  "${same_minor_newer_patch_package_version}"
)
ftimer_check_package_version_request(
  same-minor-newer-patch-package
  "${current_package_version_request}"
  ACCEPT
  "${same_minor_newer_patch_prefix}"
)
ftimer_check_package_version_request(
  same-minor-too-new-patch-request
  "${same_minor_too_new_patch_request}"
  REJECT
  "${same_minor_newer_patch_prefix}"
)

set(future_minor_prefix "${TEST_BINARY_DIR}/version-probes/future-minor-prefix")
ftimer_write_synthetic_package_prefix(
  "${future_minor_prefix}"
  "${future_minor_package_version_request}"
)
ftimer_check_package_version_request(
  future-minor-package
  "${same_minor_package_version_request}"
  REJECT
  "${future_minor_prefix}"
)

ftimer_verify_installed_artifacts()

if(TEST_ENABLE_MPI)
  ftimer_expect_integer_mpi_comm_rejected_cases()
endif()

set(consumer_configure_args
  -S "${consumer_source_dir}"
  -B "${consumer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_PREFIX_PATH=${install_prefix}
  -DFTIMER_CONSUMER_ENABLE_MPI=${TEST_ENABLE_MPI}
)

if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
  list(APPEND consumer_configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
endif()

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
set(oop_consumer_executable "${consumer_build_dir}/ftimer_installed_oop_consumer${TEST_EXECUTABLE_SUFFIX}")
set(mixed_consumer_executable "${consumer_build_dir}/ftimer_installed_mixed_consumer${TEST_EXECUTABLE_SUFFIX}")
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  set(configured_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_oop_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_oop_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_mixed_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mixed_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  if(EXISTS "${configured_consumer_executable}")
    set(consumer_executable "${configured_consumer_executable}")
  endif()
  if(EXISTS "${configured_oop_consumer_executable}")
    set(oop_consumer_executable "${configured_oop_consumer_executable}")
  endif()
  if(EXISTS "${configured_mixed_consumer_executable}")
    set(mixed_consumer_executable "${configured_mixed_consumer_executable}")
  endif()
endif()

# Plain consumers do not call MPI_Init; MPI-enabled installed checks use the
# MPI-aware consumers below.
if(NOT TEST_ENABLE_MPI)
  execute_process(
    COMMAND "${consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE consumer_run_result
  )
  if(NOT consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package consumer executable exited with a nonzero status.")
  endif()

  execute_process(
    COMMAND "${oop_consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE oop_consumer_run_result
  )
  if(NOT oop_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package OOP consumer executable exited with a nonzero status.")
  endif()

  execute_process(
    COMMAND "${mixed_consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE mixed_consumer_run_result
  )
  if(NOT mixed_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package mixed-module consumer executable exited with a nonzero status.")
  endif()
endif()

if(TEST_ENABLE_MPI)
  set(mpi_consumer_executable "${consumer_build_dir}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}")
  if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
    set(configured_mpi_consumer_executable
      "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    if(EXISTS "${configured_mpi_consumer_executable}")
      set(mpi_consumer_executable "${configured_mpi_consumer_executable}")
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
  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_union_summary.txt")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_union_summary.txt.")
  endif()
  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_union_summary.csv")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_union_summary.csv.")
  endif()
  file(READ "${consumer_build_dir}/consumer_mpi_union_summary.csv" ftimer_consumer_union_csv_text)
  if(NOT ftimer_consumer_union_csv_text MATCHES "mpi_union")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the mpi_union summary kind.")
  endif()
  if(NOT ftimer_consumer_union_csv_text MATCHES "participating_rank_count")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the sparse participation schema.")
  endif()
  if(NOT ftimer_consumer_union_csv_text MATCHES "consumer_mpi_work")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the expected consumer_mpi_work entry.")
  endif()
endif()
