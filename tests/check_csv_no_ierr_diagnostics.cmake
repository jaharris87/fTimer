cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_EXECUTABLE OR TEST_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "TEST_EXECUTABLE must point to ftimer_csv_no_ierr_diagnostics.")
endif()

execute_process(
  COMMAND "${TEST_EXECUTABLE}"
  RESULT_VARIABLE csv_result
  OUTPUT_VARIABLE csv_stdout
  ERROR_VARIABLE csv_stderr
)

if(NOT csv_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_csv_no_ierr_diagnostics exited with a nonzero status.\n"
    "stdout:\n${csv_stdout}\n"
    "stderr:\n${csv_stderr}"
  )
endif()

string(REPLACE "\r\n" "\n" csv_stderr_normalized "${csv_stderr}")
set(expected_stderr
  "ftimer write_summary_csv append validation failed: existing CSV header does not match fTimer CSV format_version 2\n")
if(NOT csv_stderr_normalized STREQUAL expected_stderr)
  message(FATAL_ERROR
    "Unexpected ftimer CSV no-ierr diagnostics stderr.\n"
    "Expected:\n${expected_stderr}\n"
    "Actual:\n${csv_stderr_normalized}"
  )
endif()
