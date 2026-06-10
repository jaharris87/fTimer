# Shared MPI+OpenMP installed-consumer diagnostic stderr checks.

function(ftimer_check_openmp_api_mpi_openmp_stderr stderr_text out_ok out_message)
  string(REPLACE "\r\n" "\n" stderr_normalized "${stderr_text}")
  string(REPLACE ";" "\\;" stderr_escaped "${stderr_normalized}")
  string(REPLACE "\n" ";" stderr_lines "${stderr_escaped}")

  set(diagnostic_line_count 0)
  set(rank0_line_count 0)
  set(rank1_line_count 0)
  set(unexpected_ftimer_line_count 0)
  set(unexpected_ftimer_lines "")
  foreach(stderr_line IN LISTS stderr_lines)
    string(STRIP "${stderr_line}" stderr_line_stripped)
    if(NOT stderr_line_stripped MATCHES "ftimer_openmp recorded")
      if(stderr_line_stripped MATCHES "[Ff]Timer|FTIMER|ftimer_")
        math(EXPR unexpected_ftimer_line_count "${unexpected_ftimer_line_count} + 1")
        string(APPEND unexpected_ftimer_lines "${stderr_line_stripped}\n")
      endif()
      continue()
    endif()

    math(EXPR diagnostic_line_count "${diagnostic_line_count} + 1")
    if((stderr_line_stripped MATCHES "ftimer_openmp recorded 1 worker diagnostics")
        AND (stderr_line_stripped MATCHES "first status 5, overflow 0"))
      math(EXPR rank0_line_count "${rank0_line_count} + 1")
    elseif((stderr_line_stripped MATCHES "ftimer_openmp recorded 2 worker diagnostics")
        AND (stderr_line_stripped MATCHES "first status 5, overflow 0"))
      math(EXPR rank1_line_count "${rank1_line_count} + 1")
    endif()
  endforeach()

  if((NOT "${diagnostic_line_count}" STREQUAL "2")
      OR (NOT "${rank0_line_count}" STREQUAL "1")
      OR (NOT "${rank1_line_count}" STREQUAL "1")
      OR (NOT "${unexpected_ftimer_line_count}" STREQUAL "0"))
    set(${out_ok} FALSE PARENT_SCOPE)
    string(CONCAT failure_message
      "Unexpected OpenMP API MPI+OpenMP diagnostic stderr.\n"
      "Expected one rank diagnostic with 1 retained worker diagnostic and "
      "one rank diagnostic with 2 retained worker diagnostics.\n"
      "Observed ftimer_openmp diagnostic line count: ${diagnostic_line_count}\n"
      "Observed rank-0-style diagnostic line count: ${rank0_line_count}\n"
      "Observed rank-1-style diagnostic line count: ${rank1_line_count}\n"
      "Observed unexpected fTimer diagnostic line count: ${unexpected_ftimer_line_count}\n"
      "Unexpected fTimer diagnostic lines:\n${unexpected_ftimer_lines}"
      "Actual:\n${stderr_normalized}"
    )
    set(${out_message} "${failure_message}" PARENT_SCOPE)
    return()
  endif()

  set(${out_ok} TRUE PARENT_SCOPE)
  set(${out_message} "" PARENT_SCOPE)
endfunction()

function(ftimer_assert_openmp_api_mpi_openmp_stderr stderr_text)
  ftimer_check_openmp_api_mpi_openmp_stderr("${stderr_text}" stderr_ok stderr_message)
  if(NOT stderr_ok)
    message(FATAL_ERROR "${stderr_message}")
  endif()
endfunction()
