if(NOT DEFINED FTIMER_BENCH_EXE)
  message(FATAL_ERROR "FTIMER_BENCH_EXE is required")
endif()

if(NOT DEFINED FTIMER_BENCH_CSV)
  message(FATAL_ERROR "FTIMER_BENCH_CSV is required")
endif()

file(REMOVE "${FTIMER_BENCH_CSV}")

execute_process(
  COMMAND "${FTIMER_BENCH_EXE}" "${FTIMER_BENCH_CSV}"
  RESULT_VARIABLE bench_result
  OUTPUT_VARIABLE bench_stdout
  ERROR_VARIABLE bench_stderr
)

if(NOT bench_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_bench CSV run failed with ${bench_result}\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()

if(NOT EXISTS "${FTIMER_BENCH_CSV}")
  message(FATAL_ERROR "ftimer_bench did not create ${FTIMER_BENCH_CSV}")
endif()

file(READ "${FTIMER_BENCH_CSV}" bench_csv)

if(NOT bench_csv MATCHES "^benchmark,reps,total_ms,per_op_ns")
  message(FATAL_ERROR "ftimer_bench CSV output is missing the expected header")
endif()

set(required_rows
  "\"format local text N=100 entries\""
  "\"write local CSV N=100 entries\""
  "\"format local text N=100 long L=256\""
  "\"format local text metadata M=200\""
  "\"write local CSV metadata M=200\""
  "\"format sparse union text N=100\""
)

foreach(required_row IN LISTS required_rows)
  if(NOT bench_csv MATCHES "${required_row}")
    message(FATAL_ERROR "ftimer_bench CSV output is missing ${required_row}")
  endif()
endforeach()
