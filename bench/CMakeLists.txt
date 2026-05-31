add_executable(ftimer_bench ftimer_bench.F90)
target_link_libraries(ftimer_bench PRIVATE ftimer)

set(ftimer_bench_command "$<TARGET_FILE:ftimer_bench>")
if(FTIMER_USE_MPI)
  set(ftimer_bench_command "${MPIEXEC_EXECUTABLE}")
  if(DEFINED MPIEXEC_NUMPROC_FLAG AND NOT MPIEXEC_NUMPROC_FLAG STREQUAL "")
    list(APPEND ftimer_bench_command "${MPIEXEC_NUMPROC_FLAG}" 2)
  else()
    list(APPEND ftimer_bench_command -n 2)
  endif()
  if(DEFINED MPIEXEC_PREFLAGS AND NOT MPIEXEC_PREFLAGS STREQUAL "")
    list(APPEND ftimer_bench_command ${MPIEXEC_PREFLAGS})
  endif()
  list(APPEND ftimer_bench_command "$<TARGET_FILE:ftimer_bench>")
  if(DEFINED MPIEXEC_POSTFLAGS AND NOT MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_bench_command ${MPIEXEC_POSTFLAGS})
  endif()
endif()

add_test(NAME bench_smoke COMMAND ${ftimer_bench_command})
set_tests_properties(bench_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
  RUN_SERIAL TRUE
)

set(ftimer_bench_script_args
  -DFTIMER_BENCH_EXE=$<TARGET_FILE:ftimer_bench>
  -DFTIMER_BENCH_USE_MPI=${FTIMER_USE_MPI}
  -DFTIMER_BENCH_MPIEXEC_EXECUTABLE=${MPIEXEC_EXECUTABLE}
  "-DFTIMER_BENCH_MPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
  "-DFTIMER_BENCH_MPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
  "-DFTIMER_BENCH_MPIEXEC_POSTFLAGS=${MPIEXEC_POSTFLAGS}"
)

add_test(NAME bench_csv_smoke
  COMMAND ${CMAKE_COMMAND}
    ${ftimer_bench_script_args}
    -DFTIMER_BENCH_CSV=${CMAKE_CURRENT_BINARY_DIR}/ftimer_bench_results.csv
    -DFTIMER_BENCH_MPI_NPROCS=2
    -DFTIMER_BENCH_EXPECT_MPI_STRICT_ROW=${FTIMER_USE_MPI}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_bench_csv_output.cmake
)
set_tests_properties(bench_csv_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
  RUN_SERIAL TRUE
)

add_test(NAME bench_csv_error_smoke
  COMMAND ${CMAKE_COMMAND}
    ${ftimer_bench_script_args}
    -DFTIMER_BENCH_CSV=${CMAKE_CURRENT_BINARY_DIR}/missing-dir/ftimer_bench_results.csv
    -DFTIMER_BENCH_MPI_NPROCS=1
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_bench_csv_error.cmake
)
set_tests_properties(bench_csv_error_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
  RUN_SERIAL TRUE
)
