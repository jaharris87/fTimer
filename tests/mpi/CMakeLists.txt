set(MPI_TEST_SOURCES_2PE
  test_mpi_summary.pf
  test_mpi_consistency.pf
)

set(MPI_TEST_SOURCES_4PE
  test_mpi_summary_4pe.pf
  test_mpi_consistency_4pe.pf
)

set(MPI_TEST_PATHS_2PE)
set(MPI_TEST_PATHS_4PE)
set(MPI_TESTS_PRESENT TRUE)
foreach(source IN LISTS MPI_TEST_SOURCES_2PE)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    list(APPEND MPI_TEST_PATHS_2PE "${source}")
  else()
    set(MPI_TESTS_PRESENT FALSE)
  endif()
endforeach()

foreach(source IN LISTS MPI_TEST_SOURCES_4PE)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    list(APPEND MPI_TEST_PATHS_4PE "${source}")
  else()
    set(MPI_TESTS_PRESENT FALSE)
  endif()
endforeach()

if(MPI_TESTS_PRESENT)
  add_pfunit_ctest(ftimer_mpi_tests
    TEST_SOURCES ${MPI_TEST_PATHS_2PE}
    OTHER_SOURCES ../test_support.F90
    LINK_LIBRARIES ftimer_test
    LABELS mpi
    MAX_PES 2
  )

  add_pfunit_ctest(ftimer_mpi_tests_4pe
    TEST_SOURCES ${MPI_TEST_PATHS_4PE}
    OTHER_SOURCES ../test_support.F90
    LINK_LIBRARIES ftimer_test
    LABELS mpi
    MAX_PES 4
  )

  # pFUnit macro expansion can generate lines exceeding the default 132-char
  # free-form limit, triggering -Werror=line-truncation with GNU Fortran.
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(ftimer_mpi_tests PRIVATE -ffree-line-length-none)
    target_compile_options(ftimer_mpi_tests_4pe PRIVATE -ffree-line-length-none)
  endif()
else()
  message(WARNING
    "Skipping ftimer_mpi_tests because Phase 5 MPI test sources are not present yet."
  )
endif()
