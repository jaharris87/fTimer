# Example programs
add_executable(basic_usage basic_usage.F90)
target_link_libraries(basic_usage PRIVATE ftimer)

add_executable(nested_timers nested_timers.F90)
target_link_libraries(nested_timers PRIVATE ftimer)

if(FTIMER_USE_MPI)
  add_executable(mpi_example mpi_example.F90)
  target_link_libraries(mpi_example PRIVATE ftimer)
endif()

if(FTIMER_USE_OPENMP)
  add_executable(openmp_example openmp_example.F90)
  target_link_libraries(openmp_example PRIVATE ftimer)
endif()
