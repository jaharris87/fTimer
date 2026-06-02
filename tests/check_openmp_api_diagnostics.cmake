cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_EXECUTABLE OR TEST_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "TEST_EXECUTABLE must point to ftimer_openmp_api_diagnostics.")
endif()

execute_process(
  COMMAND "${TEST_EXECUTABLE}"
  RESULT_VARIABLE diagnostic_result
  OUTPUT_VARIABLE diagnostic_stdout
  ERROR_VARIABLE diagnostic_stderr
)

if(NOT diagnostic_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_openmp_api_diagnostics exited with a nonzero status.\n"
    "stdout:\n${diagnostic_stdout}\n"
    "stderr:\n${diagnostic_stderr}"
  )
endif()

string(REPLACE "\r\n" "\n" diagnostic_stderr_normalized "${diagnostic_stderr}")
set(expected_stderr "ftimer_openmp recorded 1 worker diagnostics; first status 2, overflow 2\n")
if(NOT diagnostic_stderr_normalized STREQUAL expected_stderr)
  message(FATAL_ERROR
    "Unexpected ftimer_openmp worker diagnostic stderr.\n"
    "Expected:\n${expected_stderr}\n"
    "Actual:\n${diagnostic_stderr_normalized}"
  )
endif()
