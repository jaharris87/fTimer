set(MPI_TEST_SOURCES
  test_mpi_summary.pf
  test_mpi_consistency.pf
)

set(MPI_TEST_PATHS)
set(MPI_TESTS_PRESENT TRUE)
foreach(source IN LISTS MPI_TEST_SOURCES)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    list(APPEND MPI_TEST_PATHS "${source}")
  else()
    set(MPI_TESTS_PRESENT FALSE)
  endif()
endforeach()

if(MPI_TESTS_PRESENT)
  add_pfunit_ctest(ftimer_mpi_tests
    TEST_SOURCES ${MPI_TEST_PATHS}
    LINK_LIBRARIES ftimer
    LABELS mpi
  )

  # Run MPI tests with 2 ranks by default
  set_tests_properties(ftimer_mpi_tests PROPERTIES
    PROCESSORS 2
  )
else()
  message(WARNING
    "Skipping ftimer_mpi_tests because Phase 5 MPI test sources are not present yet."
  )
endif()
