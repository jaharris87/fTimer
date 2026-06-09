# Shared path, option, compiler, and scratch-directory setup for installed-consumer checks.

set(ftimer_installed_consumer_contract_stop FALSE)
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

if(NOT DEFINED TEST_EXECUTE_TIMEOUT_SECONDS OR TEST_EXECUTE_TIMEOUT_SECONDS STREQUAL "")
  set(TEST_EXECUTE_TIMEOUT_SECONDS 120)
endif()

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
    set(ftimer_installed_consumer_contract_stop TRUE)
    return()
  endif()

  set(test_fortran_compiler "${ftimer_required_compiler}")
else()
  set(test_fortran_compiler "${CMAKE_Fortran_COMPILER}")
endif()

file(REMOVE_RECURSE "${TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")
