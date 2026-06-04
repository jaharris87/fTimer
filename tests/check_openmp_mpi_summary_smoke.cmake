cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_COMMAND OR TEST_COMMAND STREQUAL "")
  message(FATAL_ERROR "TEST_COMMAND must launch ftimer_openmp_mpi_summary_smoke.")
endif()

execute_process(
  COMMAND ${TEST_COMMAND}
  RESULT_VARIABLE summary_result
  OUTPUT_VARIABLE summary_stdout
  ERROR_VARIABLE summary_stderr
)

if(NOT summary_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_openmp_mpi_summary_smoke exited with a nonzero status.\n"
    "stdout:\n${summary_stdout}\n"
    "stderr:\n${summary_stderr}"
  )
endif()

string(REPLACE "\r\n" "\n" summary_stderr_normalized "${summary_stderr}")
string(FIND "${summary_stderr_normalized}"
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed:"
  append_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV header does not match format version 1"
  header_diagnostic_pos
)
if(append_diagnostic_pos EQUAL -1 OR header_diagnostic_pos EQUAL -1)
  message(FATAL_ERROR
    "Expected MPI+OpenMP summary CSV append diagnostic was not written to stderr.\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()
