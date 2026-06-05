cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_COMMAND OR TEST_COMMAND STREQUAL "")
  message(FATAL_ERROR "TEST_COMMAND must be provided.")
endif()

if(NOT DEFINED TEST_NAME OR TEST_NAME STREQUAL "")
  set(TEST_NAME "example smoke")
endif()

if(NOT DEFINED SMOKE_TIMEOUT_SECONDS OR SMOKE_TIMEOUT_SECONDS STREQUAL "")
  set(SMOKE_TIMEOUT_SECONDS 60)
endif()

execute_process(
  COMMAND ${TEST_COMMAND}
  TIMEOUT ${SMOKE_TIMEOUT_SECONDS}
  RESULT_VARIABLE example_result
  OUTPUT_VARIABLE example_stdout
  ERROR_VARIABLE example_stderr
)

if(NOT example_result EQUAL 0)
  message(FATAL_ERROR
    "${TEST_NAME} exited with a nonzero status.\n"
    "stdout:\n${example_stdout}\n"
    "stderr:\n${example_stderr}"
  )
endif()

foreach(required_stdout IN LISTS TEST_REQUIRED_STDOUT)
  string(FIND "${example_stdout}" "${required_stdout}" required_stdout_index)
  if(required_stdout_index EQUAL -1)
    message(FATAL_ERROR
      "${TEST_NAME} stdout did not contain expected text: ${required_stdout}\n"
      "stdout:\n${example_stdout}\n"
      "stderr:\n${example_stderr}"
    )
  endif()
endforeach()
