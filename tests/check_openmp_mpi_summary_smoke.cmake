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
string(REGEX MATCHALL
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed:"
  append_diagnostics
  "${summary_stderr_normalized}"
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV header does not match format version 1"
  header_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
  active_diagnostic_pos
)
string(REGEX MATCHALL
  "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
  active_diagnostics
  "${summary_stderr_normalized}"
)
string(FIND "${summary_stderr_normalized}"
  "descriptor mismatch"
  descriptor_diagnostic_pos
)
string(REGEX MATCHALL "descriptor mismatch" descriptor_diagnostics "${summary_stderr_normalized}")
string(FIND "${summary_stderr_normalized}"
  "incomplete lane participation"
  participation_diagnostic_pos
)
string(REGEX MATCHALL "incomplete lane participation" participation_diagnostics "${summary_stderr_normalized}")
string(FIND "${summary_stderr_normalized}"
  "ftimer_openmp mpi_openmp_summary MPI reduction failed"
  worker_collective_diagnostic_pos
)
string(REGEX MATCHALL
  "ftimer_openmp mpi_openmp_summary MPI reduction failed"
  worker_collective_diagnostics
  "${summary_stderr_normalized}"
)
string(FIND "${summary_stderr_normalized}"
  "ftimer_openmp recorded 1 worker diagnostics"
  worker_diagnostic_pos
)
string(REGEX MATCHALL
  "ftimer_openmp recorded 1 worker diagnostics"
  worker_diagnostics
  "${summary_stderr_normalized}"
)
if(append_diagnostic_pos EQUAL -1 OR
   header_diagnostic_pos EQUAL -1 OR
   active_diagnostic_pos EQUAL -1 OR
   descriptor_diagnostic_pos EQUAL -1 OR
   participation_diagnostic_pos EQUAL -1 OR
   worker_collective_diagnostic_pos EQUAL -1 OR
   worker_diagnostic_pos EQUAL -1)
  message(FATAL_ERROR
    "Expected MPI+OpenMP summary omitted-ierr diagnostics were not written to stderr.\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()

list(LENGTH append_diagnostics append_diagnostic_count)
list(LENGTH active_diagnostics active_diagnostic_count)
list(LENGTH descriptor_diagnostics descriptor_diagnostic_count)
list(LENGTH participation_diagnostics participation_diagnostic_count)
list(LENGTH worker_collective_diagnostics worker_collective_diagnostic_count)
list(LENGTH worker_diagnostics worker_diagnostic_count)
if(NOT append_diagnostic_count EQUAL 1 OR
   NOT active_diagnostic_count EQUAL 3 OR
   NOT descriptor_diagnostic_count EQUAL 1 OR
   NOT participation_diagnostic_count EQUAL 1 OR
   NOT worker_collective_diagnostic_count EQUAL 1 OR
   NOT worker_diagnostic_count EQUAL 1)
  message(FATAL_ERROR
    "Unexpected MPI+OpenMP summary omitted-ierr diagnostic counts.\n"
    "append=${append_diagnostic_count}, active=${active_diagnostic_count}, "
    "descriptor=${descriptor_diagnostic_count}, participation=${participation_diagnostic_count}, "
    "worker_collective=${worker_collective_diagnostic_count}, worker=${worker_diagnostic_count}\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()
