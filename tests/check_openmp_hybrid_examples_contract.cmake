cmake_minimum_required(VERSION 3.16)

set(required_example_paths
  examples/openmp_worker_example.F90
  examples/mpi_openmp_example.F90
)

foreach(required_example_path IN LISTS required_example_paths)
  if(NOT EXISTS "${REPO_ROOT}/${required_example_path}")
    message(FATAL_ERROR "Documented OpenMP/hybrid example is missing: ${required_example_path}")
  endif()
endforeach()

file(READ "${REPO_ROOT}/examples/CMakeLists.txt" examples_cmake)

set(required_examples_cmake_phrases
  "add_executable(openmp_worker_example openmp_worker_example.F90)"
  "target_link_libraries(openmp_worker_example PRIVATE ftimer)"
  "add_test(NAME ftimer_openmp_worker_example_smoke COMMAND openmp_worker_example)"
  "add_executable(mpi_openmp_example mpi_openmp_example.F90)"
  "target_link_libraries(mpi_openmp_example PRIVATE ftimer)"
  "add_test(NAME ftimer_mpi_openmp_example_smoke"
  "set_tests_properties(ftimer_mpi_openmp_example_smoke"
  "PROPERTIES LABELS \"mpi;openmp\""
)

foreach(required_phrase IN LISTS required_examples_cmake_phrases)
  string(FIND "${examples_cmake}" "${required_phrase}" phrase_index)
  if(phrase_index EQUAL -1)
    message(FATAL_ERROR "examples/CMakeLists.txt is missing OpenMP/hybrid example contract text: ${required_phrase}")
  endif()
endforeach()

set(required_doc_mentions
  "README.md|examples/openmp_worker_example.F90"
  "README.md|examples/mpi_openmp_example.F90"
  "docs/openmp-timing-modes.md|examples/openmp_worker_example.F90"
  "docs/openmp-timing-modes.md|examples/mpi_openmp_example.F90"
  "docs/release.md|examples/openmp_worker_example.F90"
  "docs/release.md|examples/mpi_openmp_example.F90"
)

foreach(required_doc_mention IN LISTS required_doc_mentions)
  string(REPLACE "|" ";" mention_parts "${required_doc_mention}")
  list(GET mention_parts 0 doc_path)
  list(GET mention_parts 1 required_text)
  file(READ "${REPO_ROOT}/${doc_path}" doc_text)
  string(FIND "${doc_text}" "${required_text}" doc_index)
  if(doc_index EQUAL -1)
    message(FATAL_ERROR "${doc_path} must mention ${required_text}.")
  endif()
endforeach()
