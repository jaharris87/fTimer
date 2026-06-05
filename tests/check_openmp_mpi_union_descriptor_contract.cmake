if(NOT DEFINED REPO_ROOT)
  message(FATAL_ERROR "REPO_ROOT is required")
endif()

set(source_path "${REPO_ROOT}/src/ftimer_openmp.F90")
file(READ "${source_path}" source_text)

string(FIND "${source_text}"
  "subroutine build_mpi_openmp_union_descriptor_list" descriptor_start)
string(FIND "${source_text}"
  "end subroutine build_mpi_openmp_union_descriptor_list" descriptor_end)
if(descriptor_start EQUAL -1 OR descriptor_end EQUAL -1)
  message(FATAL_ERROR
    "ftimer_openmp.F90 must define build_mpi_openmp_union_descriptor_list.")
endif()
math(EXPR descriptor_length "${descriptor_end} - ${descriptor_start}")
string(SUBSTRING "${source_text}" "${descriptor_start}" "${descriptor_length}"
  descriptor_body)

foreach(required_snippet IN ITEMS
    "local_pack_ready"
    "all_pack_ready"
    "MPI_Allreduce(local_pack_ready, all_pack_ready"
    "local_mapping_ready"
    "all_mapping_ready"
    "MPI_Allreduce(local_mapping_ready, all_mapping_ready")
  string(FIND "${descriptor_body}" "${required_snippet}" snippet_index)
  if(snippet_index EQUAL -1)
    message(FATAL_ERROR
      "Hybrid sparse union descriptor exchange must collectively validate ${required_snippet}.")
  endif()
endforeach()

string(FIND "${source_text}" "if (union_idx <= 0) cycle" silent_skip_index)
if(NOT silent_skip_index EQUAL -1)
  message(FATAL_ERROR
    "Hybrid sparse union summary must not silently skip local samples with unmapped union descriptors.")
endif()
