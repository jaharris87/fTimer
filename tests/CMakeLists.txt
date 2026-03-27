set(CMAKE_Fortran_MODULE_DIRECTORY "${FTIMER_TEST_MODULE_DIR}")

if(FTIMER_BUILD_SMOKE_TESTS)
  add_executable(ftimer_phase0_smoke test_phase0_smoke.F90)
  target_link_libraries(ftimer_phase0_smoke PRIVATE ftimer)
  add_test(NAME ftimer_phase0_smoke COMMAND ftimer_phase0_smoke)
endif()

add_test(NAME ftimer_init_contract_docs
  COMMAND ${CMAKE_COMMAND}
    -DREPO_ROOT=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_init_contract_docs.cmake
)

if(FTIMER_BUILD_SMOKE_TESTS)
  add_test(NAME ftimer_installed_package_consumer
    COMMAND ${CMAKE_COMMAND}
      -DREPO_ROOT=${CMAKE_SOURCE_DIR}
      -DTEST_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/installed_package_consumer
      -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
      -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
      -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
      -DTEST_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      "-DTEST_CONFIG=$<CONFIG>"
      -P ${CMAKE_CURRENT_SOURCE_DIR}/check_installed_package_consumer.cmake
  )
endif()

if(FTIMER_BUILD_TESTS)
  # Serial pFUnit tests
  set(SERIAL_TEST_SOURCES
    test_basic.pf
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
