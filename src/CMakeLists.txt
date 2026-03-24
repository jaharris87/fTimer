# Source files in dependency order
set(FTIMER_SOURCES
  ftimer_types.F90
  ftimer_clock.F90
  ftimer_core.F90
  ftimer_summary.F90
  ftimer_mpi.F90
  ftimer_core_summary_bindings.F90
  ftimer.F90
)

add_library(ftimer ${FTIMER_SOURCES})
add_library(fTimer::ftimer ALIAS ftimer)

set_target_properties(ftimer PROPERTIES
  Fortran_MODULE_DIRECTORY "${FTIMER_PUBLIC_MODULE_DIR}"
)

target_include_directories(ftimer
  PUBLIC
    $<BUILD_INTERFACE:${FTIMER_PUBLIC_MODULE_DIR}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/ftimer>
)

if(FTIMER_USE_MPI)
  target_compile_definitions(ftimer PUBLIC FTIMER_USE_MPI)
  target_link_libraries(ftimer PUBLIC MPI::MPI_Fortran)
endif()

if(FTIMER_USE_OPENMP)
  target_link_libraries(ftimer PUBLIC OpenMP::OpenMP_Fortran)
endif()

if(FTIMER_BUILD_TESTS)
  add_library(ftimer_test ${FTIMER_SOURCES})

  set_target_properties(ftimer_test PROPERTIES
    Fortran_MODULE_DIRECTORY "${FTIMER_TEST_LIBRARY_MODULE_DIR}"
    OUTPUT_NAME ftimer_test
  )

  target_include_directories(ftimer_test
    PUBLIC
      $<BUILD_INTERFACE:${FTIMER_TEST_LIBRARY_MODULE_DIR}>
  )

  if(FTIMER_USE_MPI)
    target_compile_definitions(ftimer_test PUBLIC FTIMER_USE_MPI)
    target_link_libraries(ftimer_test PUBLIC MPI::MPI_Fortran)
  endif()

  if(FTIMER_USE_OPENMP)
    target_link_libraries(ftimer_test PUBLIC OpenMP::OpenMP_Fortran)
  endif()

  target_compile_definitions(ftimer_test PRIVATE FTIMER_BUILD_TESTS)
endif()
