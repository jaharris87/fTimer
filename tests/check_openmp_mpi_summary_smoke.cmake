cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_COMMAND OR TEST_COMMAND STREQUAL "")
  message(FATAL_ERROR "TEST_COMMAND must launch ftimer_openmp_mpi_summary_smoke.")
endif()

if(NOT DEFINED SMOKE_TIMEOUT_SECONDS OR SMOKE_TIMEOUT_SECONDS STREQUAL "")
  set(SMOKE_TIMEOUT_SECONDS 60)
endif()

execute_process(
  COMMAND ${TEST_COMMAND}
  TIMEOUT ${SMOKE_TIMEOUT_SECONDS}
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
string(REPLACE ";" "<semicolon>" summary_stderr_line_scan "${summary_stderr_normalized}")
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
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed:"
  union_append_diagnostic_pos
)
string(REGEX MATCHALL
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed:"
  union_append_diagnostics
  "${summary_stderr_normalized}"
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV header does not match format version 1"
  header_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV records do not match format version 1"
  records_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV append target does not end with a newline"
  newline_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV records contain an unterminated quoted field"
  unterminated_quote_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV records contain malformed quoted fields"
  malformed_quote_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing MPI+OpenMP summary CSV records contain a bare carriage return"
  bare_cr_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV header does not match format version 1"
  union_header_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV records do not match format version 1"
  union_records_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV append target does not end with a newline"
  union_newline_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV records contain an unterminated quoted field"
  union_unterminated_quote_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV records contain malformed quoted fields"
  union_malformed_quote_diagnostic_pos
)
string(FIND "${summary_stderr_normalized}"
  "existing sparse MPI+OpenMP union summary CSV records contain a bare carriage return"
  union_bare_cr_diagnostic_pos
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
string(REGEX MATCHALL
  "ftimer_openmp recorded 1 worker diagnostics"
  worker_diagnostics
  "${summary_stderr_normalized}"
)
if(append_diagnostic_pos EQUAL -1 OR
   header_diagnostic_pos EQUAL -1 OR
   records_diagnostic_pos EQUAL -1 OR
   newline_diagnostic_pos EQUAL -1 OR
   unterminated_quote_diagnostic_pos EQUAL -1 OR
   malformed_quote_diagnostic_pos EQUAL -1 OR
   bare_cr_diagnostic_pos EQUAL -1 OR
   union_append_diagnostic_pos EQUAL -1 OR
   union_header_diagnostic_pos EQUAL -1 OR
   union_records_diagnostic_pos EQUAL -1 OR
   union_newline_diagnostic_pos EQUAL -1 OR
   union_unterminated_quote_diagnostic_pos EQUAL -1 OR
   union_malformed_quote_diagnostic_pos EQUAL -1 OR
   union_bare_cr_diagnostic_pos EQUAL -1 OR
   active_diagnostic_pos EQUAL -1 OR
   descriptor_diagnostic_pos EQUAL -1 OR
   participation_diagnostic_pos EQUAL -1 OR
   worker_collective_diagnostic_pos EQUAL -1)
  message(FATAL_ERROR
    "Expected MPI+OpenMP summary omitted-ierr diagnostics were not written to stderr.\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()

list(LENGTH append_diagnostics append_diagnostic_count)
list(LENGTH union_append_diagnostics union_append_diagnostic_count)
list(LENGTH active_diagnostics active_diagnostic_count)
list(LENGTH descriptor_diagnostics descriptor_diagnostic_count)
list(LENGTH participation_diagnostics participation_diagnostic_count)
list(LENGTH worker_collective_diagnostics worker_collective_diagnostic_count)
list(LENGTH worker_diagnostics worker_diagnostic_count)
if(NOT append_diagnostic_count EQUAL 7 OR
   NOT union_append_diagnostic_count EQUAL 8 OR
   NOT active_diagnostic_count EQUAL 3 OR
   NOT descriptor_diagnostic_count EQUAL 1 OR
   NOT participation_diagnostic_count EQUAL 1 OR
   NOT worker_collective_diagnostic_count EQUAL 2 OR
   NOT worker_diagnostic_count EQUAL 0)
  message(FATAL_ERROR
    "Unexpected MPI+OpenMP summary omitted-ierr diagnostic counts.\n"
    "append=${append_diagnostic_count}, union_append=${union_append_diagnostic_count}, "
    "active=${active_diagnostic_count}, "
    "descriptor=${descriptor_diagnostic_count}, participation=${participation_diagnostic_count}, "
    "worker_collective=${worker_collective_diagnostic_count}, worker=${worker_diagnostic_count}\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()

string(REGEX MATCHALL "ftimer_[^\n]*" ftimer_diagnostic_lines "${summary_stderr_line_scan}")
list(LENGTH ftimer_diagnostic_lines ftimer_diagnostic_count)
if(NOT ftimer_diagnostic_count EQUAL 22)
  message(FATAL_ERROR
    "Unexpected number of fTimer diagnostics in stderr: ${ftimer_diagnostic_count}.\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()
string(CONCAT expected_append_header_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV header does not match format version 1"
)
string(CONCAT expected_append_record_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV records do not match format version 1"
)
string(CONCAT expected_append_newline_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV append target does not end with a newline"
)
string(CONCAT expected_append_unterminated_quote_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV records contain an unterminated quoted field"
)
string(CONCAT expected_append_malformed_quote_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV records contain malformed quoted fields"
)
string(CONCAT expected_append_bare_cr_diagnostic
  "ftimer_openmp write_mpi_openmp_summary_csv append validation failed: "
  "existing MPI+OpenMP summary CSV records contain a bare carriage return"
)
string(CONCAT expected_union_append_header_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV header does not match format version 1"
)
string(CONCAT expected_union_append_record_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV records do not match format version 1"
)
string(CONCAT expected_union_append_newline_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV append target does not end with a newline"
)
string(CONCAT expected_union_append_unterminated_quote_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV records contain an unterminated quoted field"
)
string(CONCAT expected_union_append_malformed_quote_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV records contain malformed quoted fields"
)
string(CONCAT expected_union_append_bare_cr_diagnostic
  "ftimer_openmp write_mpi_openmp_union_summary_csv append validation failed: "
  "existing sparse MPI+OpenMP union summary CSV records contain a bare carriage return"
)
string(CONCAT expected_descriptor_diagnostic
  "ftimer_openmp mpi_openmp_summary detected inconsistent strict hybrid descriptors "
  "(descriptor mismatch)<semicolon> disagreeing ranks 1"
)
string(CONCAT expected_participation_diagnostic
  "ftimer_openmp mpi_openmp_summary detected inconsistent strict hybrid descriptors "
  "(incomplete lane participation)<semicolon> disagreeing ranks 1"
)
set(expected_diagnostics
  "ftimer_openmp mpi_openmp_summary MPI reduction failed"
  "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
  "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
  "ftimer_openmp mpi_openmp_summary requires stopped OpenMP lanes on all ranks"
  "${expected_descriptor_diagnostic}"
  "${expected_participation_diagnostic}"
  "ftimer_openmp mpi_openmp_summary MPI reduction failed"
  "${expected_append_record_diagnostic}"
  "${expected_append_record_diagnostic}"
  "${expected_append_newline_diagnostic}"
  "${expected_append_unterminated_quote_diagnostic}"
  "${expected_append_malformed_quote_diagnostic}"
  "${expected_append_bare_cr_diagnostic}"
  "${expected_append_header_diagnostic}"
  "${expected_union_append_record_diagnostic}"
  "${expected_union_append_record_diagnostic}"
  "${expected_union_append_newline_diagnostic}"
  "${expected_union_append_unterminated_quote_diagnostic}"
  "${expected_union_append_malformed_quote_diagnostic}"
  "${expected_union_append_bare_cr_diagnostic}"
  "${expected_union_append_header_diagnostic}"
  "${expected_union_append_header_diagnostic}"
)
list(LENGTH expected_diagnostics expected_diagnostic_count)
if(NOT ftimer_diagnostic_count EQUAL expected_diagnostic_count)
  message(FATAL_ERROR
    "Unexpected number of expected fTimer diagnostics: ${expected_diagnostic_count}.\n"
    "stderr:\n${summary_stderr_normalized}"
  )
endif()
math(EXPR last_expected_diagnostic_index "${expected_diagnostic_count} - 1")
foreach(diagnostic_index RANGE 0 ${last_expected_diagnostic_index})
  list(GET ftimer_diagnostic_lines ${diagnostic_index} actual_diagnostic)
  list(GET expected_diagnostics ${diagnostic_index} expected_diagnostic)
  if(NOT actual_diagnostic STREQUAL expected_diagnostic)
    message(FATAL_ERROR
      "Unexpected fTimer diagnostic at index ${diagnostic_index}.\n"
      "Expected: ${expected_diagnostic}\n"
      "Actual: ${actual_diagnostic}\n"
      "stderr:\n${summary_stderr_normalized}"
    )
  endif()
endforeach()
