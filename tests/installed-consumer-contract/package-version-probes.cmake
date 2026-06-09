# fTimer package-version compatibility probes for installed consumers.

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
