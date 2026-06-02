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

  if(FTIMER_BUILD_SMOKE_TESTS)
    add_test(NAME ftimer_openmp_example_smoke COMMAND openmp_example)
  endif()
endif()
