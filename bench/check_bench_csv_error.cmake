if(NOT DEFINED FTIMER_BENCH_EXE)
  message(FATAL_ERROR "FTIMER_BENCH_EXE is required")
endif()

if(NOT DEFINED FTIMER_BENCH_CSV)
  message(FATAL_ERROR "FTIMER_BENCH_CSV is required")
endif()

execute_process(
  COMMAND "${FTIMER_BENCH_EXE}" "${FTIMER_BENCH_CSV}"
  RESULT_VARIABLE bench_result
  OUTPUT_VARIABLE bench_stdout
  ERROR_VARIABLE bench_stderr
)

if(bench_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_bench unexpectedly succeeded for unwritable CSV path\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()

if(NOT bench_stderr MATCHES "unable to write CSV result file")
  message(FATAL_ERROR
    "ftimer_bench CSV error did not explain the write failure\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()
