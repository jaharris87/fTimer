add_executable(ftimer_bench ftimer_bench.F90)
target_link_libraries(ftimer_bench PRIVATE ftimer)

add_test(NAME bench_smoke COMMAND ftimer_bench)
set_tests_properties(bench_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
)

add_test(NAME bench_csv_smoke
  COMMAND ${CMAKE_COMMAND}
    -DFTIMER_BENCH_EXE=$<TARGET_FILE:ftimer_bench>
    -DFTIMER_BENCH_CSV=${CMAKE_CURRENT_BINARY_DIR}/ftimer_bench_results.csv
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_bench_csv_output.cmake
)
set_tests_properties(bench_csv_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
)

add_test(NAME bench_csv_error_smoke
  COMMAND ${CMAKE_COMMAND}
    -DFTIMER_BENCH_EXE=$<TARGET_FILE:ftimer_bench>
    -DFTIMER_BENCH_CSV=${CMAKE_CURRENT_BINARY_DIR}/missing-dir/ftimer_bench_results.csv
    -P ${CMAKE_CURRENT_SOURCE_DIR}/check_bench_csv_error.cmake
)
set_tests_properties(bench_csv_error_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
)
