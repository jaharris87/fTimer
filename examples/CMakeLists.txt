# Example programs
add_executable(basic_usage basic_usage.F90)
target_link_libraries(basic_usage PRIVATE ftimer)

if(FTIMER_BUILD_SMOKE_TESTS)
  add_test(NAME ftimer_basic_usage_smoke COMMAND basic_usage)
endif()

add_executable(nested_timers nested_timers.F90)
target_link_libraries(nested_timers PRIVATE ftimer)

add_executable(instrumentation_facade_enabled
  instrumentation_facade_enabled.F90
  instrumentation_facade_example.F90
)
set_target_properties(instrumentation_facade_enabled PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mod/instrumentation_facade_enabled"
)
target_link_libraries(instrumentation_facade_enabled PRIVATE ftimer)

add_executable(instrumentation_facade_disabled
  instrumentation_facade_disabled.F90
  instrumentation_facade_example.F90
)
set_target_properties(instrumentation_facade_disabled PROPERTIES
  Fortran_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mod/instrumentation_facade_disabled"
)

if(FTIMER_BUILD_SMOKE_TESTS)
  add_test(NAME ftimer_instrumentation_facade_enabled_smoke COMMAND instrumentation_facade_enabled)
  add_test(NAME ftimer_instrumentation_facade_disabled_smoke COMMAND instrumentation_facade_disabled)
endif()

if(FTIMER_USE_MPI)
  set(ftimer_examples_mpiexec_oversubscribe_flags)
  if(DEFINED MPIEXEC_EXECUTABLE AND NOT MPIEXEC_EXECUTABLE STREQUAL "")
    execute_process(
      COMMAND "${MPIEXEC_EXECUTABLE}" --version
      OUTPUT_VARIABLE ftimer_examples_mpiexec_version_stdout
      ERROR_VARIABLE ftimer_examples_mpiexec_version_stderr
      RESULT_VARIABLE ftimer_examples_mpiexec_version_result
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(ftimer_examples_mpiexec_version_result EQUAL 0)
      set(ftimer_examples_mpiexec_version_text
        "${ftimer_examples_mpiexec_version_stdout}\n${ftimer_examples_mpiexec_version_stderr}")
      if(ftimer_examples_mpiexec_version_text MATCHES "Open MPI|OpenRTE|PRTE|PRRTE")
        set(ftimer_examples_mpiexec_oversubscribe_flags --map-by slot:OVERSUBSCRIBE)
      endif()
    endif()
  endif()

  add_executable(mpi_example mpi_example.F90)
  target_link_libraries(mpi_example PRIVATE ftimer)

  if(FTIMER_BUILD_SMOKE_TESTS)
    set(ftimer_mpi_example_command "${MPIEXEC_EXECUTABLE}")
    if(DEFINED MPIEXEC_NUMPROC_FLAG AND NOT MPIEXEC_NUMPROC_FLAG STREQUAL "")
      list(APPEND ftimer_mpi_example_command "${MPIEXEC_NUMPROC_FLAG}" 2)
    else()
      list(APPEND ftimer_mpi_example_command -n 2)
    endif()
    if(DEFINED MPIEXEC_PREFLAGS AND NOT MPIEXEC_PREFLAGS STREQUAL "")
      list(APPEND ftimer_mpi_example_command ${MPIEXEC_PREFLAGS})
    endif()
    if(ftimer_examples_mpiexec_oversubscribe_flags)
      list(APPEND ftimer_mpi_example_command ${ftimer_examples_mpiexec_oversubscribe_flags})
    endif()
    list(APPEND ftimer_mpi_example_command "$<TARGET_FILE:mpi_example>")
    if(DEFINED MPIEXEC_POSTFLAGS AND NOT MPIEXEC_POSTFLAGS STREQUAL "")
      list(APPEND ftimer_mpi_example_command ${MPIEXEC_POSTFLAGS})
    endif()

    add_test(NAME ftimer_mpi_example_smoke COMMAND ${ftimer_mpi_example_command})
    set_tests_properties(ftimer_mpi_example_smoke PROPERTIES LABELS mpi)
  endif()
endif()

if(FTIMER_USE_OPENMP)
  add_executable(openmp_example openmp_example.F90)
  target_link_libraries(openmp_example PRIVATE ftimer)

  add_executable(openmp_worker_example openmp_worker_example.F90)
  target_link_libraries(openmp_worker_example PRIVATE ftimer)

  if(FTIMER_BUILD_SMOKE_TESTS)
    add_test(NAME ftimer_openmp_example_smoke COMMAND openmp_example)
    add_test(NAME ftimer_openmp_worker_example_smoke COMMAND openmp_worker_example)
  endif()
endif()

if(FTIMER_USE_MPI AND FTIMER_USE_OPENMP)
  add_executable(mpi_openmp_example mpi_openmp_example.F90)
  target_link_libraries(mpi_openmp_example PRIVATE ftimer)

  if(FTIMER_BUILD_SMOKE_TESTS)
    set(ftimer_mpi_openmp_example_command "${MPIEXEC_EXECUTABLE}")
    if(DEFINED MPIEXEC_NUMPROC_FLAG AND NOT MPIEXEC_NUMPROC_FLAG STREQUAL "")
      list(APPEND ftimer_mpi_openmp_example_command "${MPIEXEC_NUMPROC_FLAG}" 2)
    else()
      list(APPEND ftimer_mpi_openmp_example_command -n 2)
    endif()
    if(DEFINED MPIEXEC_PREFLAGS AND NOT MPIEXEC_PREFLAGS STREQUAL "")
      list(APPEND ftimer_mpi_openmp_example_command ${MPIEXEC_PREFLAGS})
    endif()
    if(ftimer_examples_mpiexec_oversubscribe_flags)
      list(APPEND ftimer_mpi_openmp_example_command ${ftimer_examples_mpiexec_oversubscribe_flags})
    endif()
    list(APPEND ftimer_mpi_openmp_example_command "$<TARGET_FILE:mpi_openmp_example>")
    if(DEFINED MPIEXEC_POSTFLAGS AND NOT MPIEXEC_POSTFLAGS STREQUAL "")
      list(APPEND ftimer_mpi_openmp_example_command ${MPIEXEC_POSTFLAGS})
    endif()

    add_test(NAME ftimer_mpi_openmp_example_smoke
      COMMAND ${CMAKE_COMMAND}
        "-DTEST_COMMAND=${ftimer_mpi_openmp_example_command}"
        -DTEST_NAME=ftimer_mpi_openmp_example_smoke
        "-DTEST_REQUIRED_STDOUT=Strict MPI+OpenMP;Sparse MPI+OpenMP"
        -P ${CMAKE_SOURCE_DIR}/tests/check_example_smoke.cmake
    )
    set_tests_properties(ftimer_mpi_openmp_example_smoke
      PROPERTIES LABELS "mpi;openmp")
  endif()
endif()
