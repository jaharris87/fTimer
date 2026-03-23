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
)

add_pfunit_ctest(ftimer_serial_tests
  TEST_SOURCES ${SERIAL_TEST_SOURCES}
  LINK_LIBRARIES ftimer
)

# MPI tests (only when MPI enabled)
if(FTIMER_USE_MPI)
  add_subdirectory(mpi)
endif()
