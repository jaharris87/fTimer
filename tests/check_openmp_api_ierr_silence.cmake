cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED TEST_EXECUTABLE OR TEST_EXECUTABLE STREQUAL "")
  message(FATAL_ERROR "TEST_EXECUTABLE must point to ftimer_openmp_api_ierr_silence.")
endif()

execute_process(
  COMMAND "${TEST_EXECUTABLE}"
  RESULT_VARIABLE silence_result
  OUTPUT_VARIABLE silence_stdout
  ERROR_VARIABLE silence_stderr
)

if(NOT silence_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_openmp_api_ierr_silence exited with a nonzero status.\n"
    "stdout:\n${silence_stdout}\n"
    "stderr:\n${silence_stderr}"
  )
endif()

if(NOT silence_stderr STREQUAL "")
  message(FATAL_ERROR
    "Expected ierr-present ftimer_openmp failures to keep stderr silent.\n"
    "Actual stderr:\n${silence_stderr}"
  )
endif()
