if(NOT DEFINED REPO_ROOT)
  message(FATAL_ERROR "REPO_ROOT is required")
endif()

set(consumer_source
  "${REPO_ROOT}/tests/install-consumer/openmp_api_mpi_openmp_main.F90"
)
file(READ "${consumer_source}" consumer_text)

foreach(required_snippet IN ITEMS
    "ftimer_mpi_openmp_summary_t"
    "ftimer_mpi_openmp_union_summary_t"
    "call timer%mpi_openmp_summary("
    "call timer%write_mpi_openmp_summary("
    "call timer%write_mpi_openmp_summary_csv("
    "call timer%mpi_openmp_union_summary("
    "call timer%write_mpi_openmp_union_summary("
    "call timer%write_mpi_openmp_union_summary_csv(")
  string(FIND "${consumer_text}" "${required_snippet}" snippet_index)
  if(snippet_index EQUAL -1)
    message(FATAL_ERROR
      "MPI+OpenMP installed OpenMP API consumer must compile-call ${required_snippet}."
    )
  endif()
endforeach()
