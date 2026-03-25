add_executable(ftimer_bench ftimer_bench.F90)
target_link_libraries(ftimer_bench PRIVATE ftimer)

add_test(NAME bench_smoke COMMAND ftimer_bench)
set_tests_properties(bench_smoke PROPERTIES
  TIMEOUT 120
  LABELS bench
)
