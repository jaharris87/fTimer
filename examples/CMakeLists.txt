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
    add_test(NAME ftimer_mpi_example_smoke
      COMMAND
        ${MPIEXEC_EXECUTABLE}
        ${MPIEXEC_NUMPROC_FLAG} 2
        ${MPIEXEC_PREFLAGS}
        $<TARGET_FILE:mpi_example>
        ${MPIEXEC_POSTFLAGS}
    )
  endif()
endif()

if(FTIMER_USE_OPENMP)
  add_executable(openmp_example openmp_example.F90)
  target_link_libraries(openmp_example PRIVATE ftimer)
endif()
