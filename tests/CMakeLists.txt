set(CMAKE_Fortran_MODULE_DIRECTORY "${FTIMER_TEST_MODULE_DIR}")

if(FTIMER_BUILD_SMOKE_TESTS)
  add_executable(ftimer_phase0_smoke test_phase0_smoke.F90)
  target_link_libraries(ftimer_phase0_smoke PRIVATE ftimer)
  add_test(NAME ftimer_phase0_smoke COMMAND ftimer_phase0_smoke)

  add_executable(ftimer_openmp_api_smoke test_openmp_api_smoke.F90)
  target_link_libraries(ftimer_openmp_api_smoke PRIVATE ftimer_smoke_test)
  add_test(NAME ftimer_openmp_api_smoke COMMAND ftimer_openmp_api_smoke)

  add_executable(ftimer_openmp_api_ierr_silence test_openmp_api_ierr_silence.F90)
  target_link_libraries(ftimer_openmp_api_ierr_silence PRIVATE ftimer)
  add_test(NAME ftimer_openmp_api_ierr_silence
    COMMAND ${CMAKE_COMMAND}
      -DTEST_EXECUTABLE=$<TARGET_FILE:ftimer_openmp_api_ierr_silence>
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_openmp_api_ierr_silence.cmake
  )

  add_executable(ftimer_openmp_api_serial_diagnostics test_openmp_api_serial_diagnostics.F90)
  target_link_libraries(ftimer_openmp_api_serial_diagnostics PRIVATE ftimer)
  add_test(NAME ftimer_openmp_api_serial_diagnostics
    COMMAND ${CMAKE_COMMAND}
      -DTEST_EXECUTABLE=$<TARGET_FILE:ftimer_openmp_api_serial_diagnostics>
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_openmp_api_serial_diagnostics.cmake
  )

  if(FTIMER_USE_OPENMP)
    add_executable(ftimer_openmp_api_diagnostics test_openmp_api_diagnostics.F90)
    target_link_libraries(ftimer_openmp_api_diagnostics PRIVATE ftimer)
    add_test(NAME ftimer_openmp_api_diagnostics
      COMMAND ${CMAKE_COMMAND}
        -DTEST_EXECUTABLE=$<TARGET_FILE:ftimer_openmp_api_diagnostics>
        -P ${CMAKE_CURRENT_SOURCE_DIR}/check_openmp_api_diagnostics.cmake
    )

    add_executable(ftimer_openmp_summary_smoke test_openmp_summary_smoke.F90)
    target_link_libraries(ftimer_openmp_summary_smoke PRIVATE ftimer_smoke_test)
    add_test(NAME ftimer_openmp_summary_smoke
      COMMAND ${CMAKE_COMMAND}
        -DTEST_EXECUTABLE=$<TARGET_FILE:ftimer_openmp_summary_smoke>
        -P ${CMAKE_CURRENT_SOURCE_DIR}/check_openmp_summary_smoke.cmake
    )
  endif()

  if(FTIMER_USE_MPI AND FTIMER_USE_OPENMP)
    add_executable(ftimer_openmp_mpi_summary_smoke test_openmp_mpi_summary_smoke.F90)
    target_link_libraries(ftimer_openmp_mpi_summary_smoke PRIVATE ftimer_smoke_test)

    set(ftimer_openmp_mpi_summary_command "${MPIEXEC_EXECUTABLE}")
    if(DEFINED MPIEXEC_NUMPROC_FLAG AND NOT MPIEXEC_NUMPROC_FLAG STREQUAL "")
      list(APPEND ftimer_openmp_mpi_summary_command "${MPIEXEC_NUMPROC_FLAG}" 2)
    else()
      list(APPEND ftimer_openmp_mpi_summary_command -n 2)
    endif()
    if(DEFINED MPIEXEC_PREFLAGS AND NOT MPIEXEC_PREFLAGS STREQUAL "")
      list(APPEND ftimer_openmp_mpi_summary_command ${MPIEXEC_PREFLAGS})
    endif()
    list(APPEND ftimer_openmp_mpi_summary_command "$<TARGET_FILE:ftimer_openmp_mpi_summary_smoke>")
    if(DEFINED MPIEXEC_POSTFLAGS AND NOT MPIEXEC_POSTFLAGS STREQUAL "")
      list(APPEND ftimer_openmp_mpi_summary_command ${MPIEXEC_POSTFLAGS})
    endif()

    add_test(NAME ftimer_openmp_mpi_summary_smoke COMMAND ${ftimer_openmp_mpi_summary_command})
    set_tests_properties(ftimer_openmp_mpi_summary_smoke PROPERTIES LABELS "mpi;openmp")
  endif()
endif()

function(ftimer_add_installed_consumer_test test_name test_binary_dir)
  set(options
    ALLOW_CONFIGURE_SKIP
    CLEAN_INSTALL_INCLUDEDIR
    ENABLE_MPI
    ENABLE_OPENMP
    INSTALL_ONLY
    USE_DESTDIR
  )
  set(oneValueArgs INSTALL_INCLUDEDIR OPENMP_ROOT REQUIRED_COMPILER_NAMES)
  cmake_parse_arguments(FTIMER_CONSUMER "${options}" "${oneValueArgs}" "" ${ARGN})

  add_test(NAME ${test_name}
    COMMAND ${CMAKE_COMMAND}
      -DREPO_ROOT=${CMAKE_SOURCE_DIR}
      -DTEST_NAME=${test_name}
      -DTEST_BINARY_DIR=${test_binary_dir}
      -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
      -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
      -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
      -DTEST_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      "-DTEST_CONFIG=$<CONFIG>"
      -DTEST_REQUIRED_COMPILER_NAMES=${FTIMER_CONSUMER_REQUIRED_COMPILER_NAMES}
      -DTEST_INSTALL_INCLUDEDIR=${FTIMER_CONSUMER_INSTALL_INCLUDEDIR}
      -DTEST_CLEAN_INSTALL_INCLUDEDIR=${FTIMER_CONSUMER_CLEAN_INSTALL_INCLUDEDIR}
      -DTEST_INSTALL_ONLY=${FTIMER_CONSUMER_INSTALL_ONLY}
      -DTEST_USE_DESTDIR=${FTIMER_CONSUMER_USE_DESTDIR}
      -DTEST_ENABLE_MPI=${FTIMER_CONSUMER_ENABLE_MPI}
      -DTEST_ENABLE_OPENMP=${FTIMER_CONSUMER_ENABLE_OPENMP}
      -DTEST_OPENMP_ROOT=${FTIMER_CONSUMER_OPENMP_ROOT}
      -DTEST_ALLOW_CONFIGURE_SKIP=${FTIMER_CONSUMER_ALLOW_CONFIGURE_SKIP}
      -DTEST_EXECUTABLE_SUFFIX=${CMAKE_EXECUTABLE_SUFFIX}
      -DTEST_PACKAGE_VERSION=${PROJECT_VERSION}
      -DTEST_PACKAGE_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
      -DTEST_PACKAGE_VERSION_MINOR=${PROJECT_VERSION_MINOR}
      -DTEST_PACKAGE_VERSION_PATCH=${PROJECT_VERSION_PATCH}
      -DTEST_PACKAGE_VERSION_COMPATIBILITY=${FTIMER_PACKAGE_VERSION_COMPATIBILITY}
      -DTEST_MPIEXEC_EXECUTABLE=${MPIEXEC_EXECUTABLE}
      "-DTEST_MPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
      "-DTEST_MPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
      "-DTEST_MPIEXEC_POSTFLAGS=${MPIEXEC_POSTFLAGS}"
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_installed_package_consumer.cmake
  )
endfunction()

add_test(NAME ftimer_init_contract_docs
  COMMAND ${CMAKE_COMMAND}
    -DREPO_ROOT=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_init_contract_docs.cmake
)

add_test(NAME ftimer_mpi_lifecycle_contract_docs
  COMMAND ${CMAKE_COMMAND}
    -DREPO_ROOT=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_mpi_lifecycle_contract_docs.cmake
)

add_test(NAME ftimer_public_symbol_allowlist
  COMMAND ${CMAKE_COMMAND}
    -DREPO_ROOT=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_public_symbol_allowlist.cmake
)

add_test(NAME ftimer_release_docs_contract
  COMMAND ${CMAKE_COMMAND}
    -DREPO_ROOT=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_release_docs_contract.cmake
)

if(FTIMER_BUILD_SMOKE_TESTS)
  if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(ftimer_absolute_includedir_base "$ENV{TMPDIR}")
  elseif(DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
    set(ftimer_absolute_includedir_base "$ENV{TEMP}")
  elseif(UNIX)
    set(ftimer_absolute_includedir_base "/tmp")
  else()
    set(ftimer_absolute_includedir_base "${CMAKE_CURRENT_BINARY_DIR}")
  endif()
  get_filename_component(
    ftimer_absolute_includedir_base
    "${ftimer_absolute_includedir_base}"
    ABSOLUTE
  )
  string(SHA256 ftimer_absolute_includedir_hash "${CMAKE_CURRENT_BINARY_DIR}")
  string(SUBSTRING "${ftimer_absolute_includedir_hash}" 0 12 ftimer_absolute_includedir_hash)
  set(ftimer_absolute_includedir_test_root
    "${ftimer_absolute_includedir_base}/ftimer-absolute-includedir-${ftimer_absolute_includedir_hash}"
  )

  ftimer_add_installed_consumer_test(
    ftimer_installed_package_consumer
    ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer
  )

  ftimer_add_installed_consumer_test(
    ftimer_installed_package_consumer_absolute_includedir
    ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer_absolute_includedir
    INSTALL_INCLUDEDIR
      ${ftimer_absolute_includedir_test_root}/installed_package_consumer_absolute_includedir/include
    CLEAN_INSTALL_INCLUDEDIR
  )

  ftimer_add_installed_consumer_test(
    ftimer_absolute_includedir_destdir_install
    ${CMAKE_CURRENT_BINARY_DIR}/absolute_includedir_destdir_install
    INSTALL_INCLUDEDIR
      ${ftimer_absolute_includedir_test_root}/absolute_includedir_destdir_install/include
    CLEAN_INSTALL_INCLUDEDIR
    INSTALL_ONLY
    USE_DESTDIR
  )

  ftimer_add_installed_consumer_test(
    ftimer_installed_package_consumer_mpi
    ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer_mpi
    REQUIRED_COMPILER_NAMES mpifort,mpif90
    ENABLE_MPI
  )

  if(FTIMER_USE_MPI AND FTIMER_USE_OPENMP)
    ftimer_add_installed_consumer_test(
      ftimer_installed_package_consumer_mpi_openmp
      ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer_mpi_openmp
      ENABLE_MPI
      ENABLE_OPENMP
    )
  endif()

  ftimer_add_installed_consumer_test(
    ftimer_installed_package_consumer_openmp
    ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer_openmp
    REQUIRED_COMPILER_NAMES gfortran
    ENABLE_OPENMP
  )

  if(FTIMER_USE_OPENMP)
    set(ftimer_openmp_flang_consumer_args
      REQUIRED_COMPILER_NAMES flang-19,flang-new-19,flang-new,flang
      ENABLE_OPENMP
    )
    if(DEFINED OpenMP_ROOT AND NOT OpenMP_ROOT STREQUAL "")
      list(APPEND ftimer_openmp_flang_consumer_args OPENMP_ROOT ${OpenMP_ROOT})
    endif()
    if(NOT FTIMER_REQUIRE_FLANG_OPENMP_CONTRACT)
      list(APPEND ftimer_openmp_flang_consumer_args ALLOW_CONFIGURE_SKIP)
    endif()

    ftimer_add_installed_consumer_test(
      ftimer_installed_package_consumer_openmp_flang
      ${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer_openmp_flang
      ${ftimer_openmp_flang_consumer_args}
    )
  endif()

  add_test(NAME ftimer_configure_contracts
    COMMAND ${CMAKE_COMMAND}
      -DREPO_ROOT=${CMAKE_SOURCE_DIR}
      -DTEST_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/configure_contracts
      -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
      -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
      -DFTIMER_REQUIRE_FLANG_OPENMP_CONTRACT=${FTIMER_REQUIRE_FLANG_OPENMP_CONTRACT}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_configure_contracts.cmake
  )

  add_test(NAME ftimer_make_wrapper_contracts
    COMMAND ${CMAKE_COMMAND}
      -DREPO_ROOT=${CMAKE_SOURCE_DIR}
      -DTEST_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/make_wrapper_contracts
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_make_wrapper_contracts.cmake
  )

  add_test(NAME ftimer_openmp_option_off_ignores_global_flags
    COMMAND ${CMAKE_COMMAND}
      -DREPO_ROOT=${CMAKE_SOURCE_DIR}
      -DTEST_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/openmp_option_off_global_flags
      -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
      -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
      -DTEST_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      "-DTEST_CONFIG=$<CONFIG>"
      -DTEST_EXECUTABLE_SUFFIX=${CMAKE_EXECUTABLE_SUFFIX}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_openmp_option_off_global_flags.cmake
  )
endif()

if(FTIMER_BUILD_TESTS)
  # Serial pFUnit tests
  set(SERIAL_TEST_SOURCES
    test_basic.pf
    test_call_stack.pf
    test_nesting.pf
    test_context.pf
    test_callcount.pf
    test_reset.pf
    test_edge_cases.pf
    test_summary.pf
    test_self_time.pf
    test_file_output.pf
    test_callbacks.pf
    test_procedural_api.pf
    test_scoped_guard.pf
    test_oop_scoped_guard.pf
  )

  if(FTIMER_USE_OPENMP)
    list(APPEND SERIAL_TEST_SOURCES
      test_openmp_guards.pf
    )
  endif()

  if(NOT FTIMER_USE_MPI)
    list(APPEND SERIAL_TEST_SOURCES
      test_mpi_disabled.pf
    )
  endif()

  add_pfunit_ctest(ftimer_serial_tests
    TEST_SOURCES ${SERIAL_TEST_SOURCES}
    OTHER_SOURCES test_support.F90
    LINK_LIBRARIES ftimer_test
  )

  # pFUnit macro expansion can generate lines exceeding the default 132-char
  # free-form limit, triggering -Werror=line-truncation with GNU Fortran.
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(ftimer_serial_tests PRIVATE -ffree-line-length-none)
  endif()

  # MPI tests (only when MPI enabled)
  if(FTIMER_USE_MPI)
    add_subdirectory(mpi)
  endif()
endif()
