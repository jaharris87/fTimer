set(MPI_TEST_SOURCES
  test_mpi_summary.pf
  test_mpi_consistency.pf
)

add_pfunit_ctest(ftimer_mpi_tests
  TEST_SOURCES ${MPI_TEST_SOURCES}
  LINK_LIBRARIES ftimer
  LABELS mpi
)

# Run MPI tests with 2 ranks by default
set_tests_properties(ftimer_mpi_tests PROPERTIES
  PROCESSORS 2
)
