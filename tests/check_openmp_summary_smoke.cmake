cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_EXECUTABLE OR TEST_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "TEST_EXECUTABLE must point to ftimer_openmp_summary_smoke.")
endif()

execute_process(
  COMMAND "${TEST_EXECUTABLE}"
  RESULT_VARIABLE summary_result
  OUTPUT_VARIABLE summary_stdout
  ERROR_VARIABLE summary_stderr
)

if(NOT summary_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_openmp_summary_smoke exited with a nonzero status.\n"
    "stdout:\n${summary_stdout}\n"
    "stderr:\n${summary_stderr}"
  )
endif()

string(REPLACE "\r\n" "\n" summary_stderr_normalized "${summary_stderr}")
string(CONCAT expected_stderr
  "ftimer_openmp write_openmp_summary_csv append validation failed: existing OpenMP summary CSV append target does not end with a newline\n"
  "ftimer_openmp write_openmp_summary_csv append validation failed: existing OpenMP summary CSV records contain malformed quoted fields\n"
  "ftimer_openmp write_openmp_summary_csv append validation failed: existing OpenMP summary CSV records contain a bare carriage return\n"
  "ftimer_openmp write_openmp_summary_csv append validation failed: existing OpenMP summary CSV header does not match format version 1\n"
  "ftimer_openmp recorded 1 worker diagnostics; first status 4, overflow 0\n"
  "ftimer_openmp recorded 1 worker diagnostics; first status 4, overflow 0\n"
)
if(NOT summary_stderr_normalized STREQUAL expected_stderr)
  message(FATAL_ERROR
    "Unexpected ftimer_openmp summary smoke stderr.\n"
    "Expected:\n${expected_stderr}\n"
    "Actual:\n${summary_stderr_normalized}"
  )
endif()
