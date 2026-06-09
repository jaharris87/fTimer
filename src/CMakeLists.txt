# Source files in dependency order
set(FTIMER_SOURCES
  ftimer_types.F90
  ftimer_csv_validation.F90
  ftimer_clock.F90
  ftimer_core.F90
  ftimer_summary.F90
  ftimer_mpi.F90
  ftimer_core_summary_bindings.F90
  ftimer_openmp.F90
  ftimer_openmp_reports.F90
  ftimer.F90
)

function(ftimer_apply_feature_dependencies target_name)
  if(FTIMER_USE_MPI)
    target_compile_definitions(${target_name} PUBLIC FTIMER_USE_MPI)
    target_link_libraries(${target_name} PUBLIC MPI::MPI_Fortran)
  endif()

  if(FTIMER_USE_OPENMP)
    target_compile_definitions(${target_name} PUBLIC FTIMER_USE_OPENMP)
    target_link_libraries(${target_name} PUBLIC OpenMP::OpenMP_Fortran)
  endif()
endfunction()

function(ftimer_add_internal_library target_name module_dir build_definition)
  add_library(${target_name} ${FTIMER_SOURCES})

  set_target_properties(${target_name} PROPERTIES
    Fortran_MODULE_DIRECTORY "${module_dir}"
    OUTPUT_NAME ${target_name}
  )

  target_include_directories(${target_name}
    PUBLIC
      $<BUILD_INTERFACE:${module_dir}>
  )

  ftimer_apply_feature_dependencies(${target_name})
  target_compile_definitions(${target_name} PRIVATE ${build_definition})
endfunction()

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

ftimer_apply_feature_dependencies(ftimer)

if(FTIMER_BUILD_TESTS)
  ftimer_add_internal_library(
    ftimer_test
    "${FTIMER_TEST_LIBRARY_MODULE_DIR}"
    FTIMER_BUILD_TESTS
  )
endif()

if(FTIMER_BUILD_SMOKE_TESTS)
  ftimer_add_internal_library(
    ftimer_smoke_test
    "${FTIMER_SMOKE_TEST_LIBRARY_MODULE_DIR}"
    FTIMER_BUILD_SMOKE_TESTS
  )
endif()
