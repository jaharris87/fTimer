# Source files in dependency order
set(FTIMER_SOURCES
  ftimer_types.F90
  ftimer_clock.F90
  ftimer_core.F90
  ftimer_summary.F90
  ftimer_mpi.F90
  ftimer.F90
)

add_library(ftimer ${FTIMER_SOURCES})
add_library(fTimer::ftimer ALIAS ftimer)

target_include_directories(ftimer
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_Fortran_MODULE_DIRECTORY}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/ftimer>
)

if(FTIMER_USE_MPI)
  target_compile_definitions(ftimer PUBLIC FTIMER_USE_MPI)
  target_link_libraries(ftimer PUBLIC MPI::MPI_Fortran)
endif()

if(FTIMER_BUILD_TESTS)
  target_compile_definitions(ftimer PRIVATE FTIMER_BUILD_TESTS)
endif()
