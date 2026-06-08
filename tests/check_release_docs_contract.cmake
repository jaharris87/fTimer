cmake_minimum_required(VERSION 3.16)

set(required_paths
  AGENTS.md
  CLAUDE.md
  README.md
  docs/design.md
  docs/installed-api.md
  docs/implementation-history.md
  docs/maintainer.md
  docs/openmp-timing-modes.md
  docs/release.md
  docs/semantics.md
  docs/troubleshooting.md
  CONTRIBUTING.md
  SECURITY.md
  SUPPORT.md
)

foreach(required_path IN LISTS required_paths)
  if(NOT EXISTS "${REPO_ROOT}/${required_path}")
    message(FATAL_ERROR "Release-facing documentation path is missing: ${required_path}")
  endif()
endforeach()

foreach(markdown_path IN LISTS required_paths)
  set(markdown_abs "${REPO_ROOT}/${markdown_path}")
  get_filename_component(markdown_dir "${markdown_abs}" DIRECTORY)
  file(STRINGS "${markdown_abs}" markdown_lines)

  foreach(markdown_line IN LISTS markdown_lines)
    set(remaining_line "${markdown_line}")
    while(remaining_line MATCHES "\\[[^]]*\\]\\(([^)]+)\\)")
      set(link_target "${CMAKE_MATCH_1}")
      string(REGEX REPLACE "^[ \t]*<([^>]+)>.*$" "\\1" link_target "${link_target}")
      string(REGEX REPLACE "^[ \t]*([^ \t\"']+).*$" "\\1" link_target "${link_target}")
      string(REGEX REPLACE "#.*$" "" link_path "${link_target}")

      if(link_path STREQUAL "" OR
         link_path MATCHES "^[A-Za-z][A-Za-z0-9+.-]*:" OR
         link_path MATCHES "^#")
        string(REGEX REPLACE "^[^[]*\\[[^]]*\\]\\([^)]+\\)" "" remaining_line "${remaining_line}")
        continue()
      endif()

      get_filename_component(link_abs "${markdown_dir}/${link_path}" ABSOLUTE)
      if(NOT EXISTS "${link_abs}")
        message(FATAL_ERROR
          "${markdown_path} links to '${link_target}', but '${link_abs}' does not exist."
        )
      endif()

      string(REGEX REPLACE "^[^[]*\\[[^]]*\\]\\([^)]+\\)" "" remaining_line "${remaining_line}")
    endwhile()
  endforeach()
endforeach()

file(READ "${REPO_ROOT}/src/ftimer_types.F90" ftimer_types_text)
file(STRINGS "${REPO_ROOT}/src/ftimer_types.F90" ftimer_types_lines)
file(STRINGS "${REPO_ROOT}/docs/semantics.md" semantics_lines)

set(public_status_constants)
foreach(source_line IN LISTS ftimer_types_lines)
  string(REGEX REPLACE "!.*$" "" source_line_no_comment "${source_line}")
  string(STRIP "${source_line_no_comment}" source_line_no_comment)
  if(NOT source_line_no_comment MATCHES "^[Pp][Uu][Bb][Ll][Ii][Cc][ \t]*::")
    continue()
  endif()

  string(REGEX REPLACE "^[Pp][Uu][Bb][Ll][Ii][Cc][ \t]*::[ \t]*" "" public_list "${source_line_no_comment}")
  string(REPLACE "," ";" public_symbols "${public_list}")
  foreach(public_symbol IN LISTS public_symbols)
    string(STRIP "${public_symbol}" public_symbol)
    if(public_symbol MATCHES "^FTIMER_(SUCCESS|ERR_[A-Za-z0-9_]+)$")
      list(APPEND public_status_constants "${public_symbol}")
    endif()
  endforeach()
endforeach()

if(NOT public_status_constants)
  message(FATAL_ERROR "No public fTimer status/error constants were extracted from src/ftimer_types.F90.")
endif()

list(SORT public_status_constants)

set(public_status_entries)
foreach(status_constant IN LISTS public_status_constants)
  if(NOT ftimer_types_text MATCHES "integer,[^\n]*parameter[^\n]*::[ \t]*${status_constant}[ \t]*=[ \t]*([0-9]+)")
    message(FATAL_ERROR "Could not find parameter value for ${status_constant}.")
  endif()
  set(status_value "${CMAKE_MATCH_1}")
  list(APPEND public_status_entries "${status_constant}|${status_value}")
endforeach()

set(documented_status_entries)
foreach(semantics_line IN LISTS semantics_lines)
  string(STRIP "${semantics_line}" semantics_line)
  if(semantics_line MATCHES "^\\|[ \t]*`(FTIMER_(SUCCESS|ERR_[A-Za-z0-9_]+))`[ \t]*\\|[ \t]*`([0-9]+)`[ \t]*\\|")
    list(APPEND documented_status_entries "${CMAKE_MATCH_1}|${CMAKE_MATCH_3}")
  endif()
endforeach()

if(NOT documented_status_entries)
  message(FATAL_ERROR "docs/semantics.md must include a public fTimer status/error-code table.")
endif()

list(SORT public_status_entries)
list(SORT documented_status_entries)

set(missing_status_entries)
foreach(public_status_entry IN LISTS public_status_entries)
  list(FIND documented_status_entries "${public_status_entry}" found_index)
  if(found_index EQUAL -1)
    list(APPEND missing_status_entries "${public_status_entry}")
  endif()
endforeach()

set(extra_status_entries)
foreach(documented_status_entry IN LISTS documented_status_entries)
  list(FIND public_status_entries "${documented_status_entry}" found_index)
  if(found_index EQUAL -1)
    list(APPEND extra_status_entries "${documented_status_entry}")
  endif()
endforeach()

if(missing_status_entries OR extra_status_entries)
  string(REPLACE ";" "\n  " missing_text "${missing_status_entries}")
  string(REPLACE ";" "\n  " extra_text "${extra_status_entries}")
  message(FATAL_ERROR
    "docs/semantics.md public status/error-code table must exactly match src/ftimer_types.F90.\n"
    "Missing or wrong in docs:\n  ${missing_text}\n"
    "Extra or stale in docs:\n  ${extra_text}"
  )
endif()

set(benchmark_docs
  README.md
  AGENTS.md
  CLAUDE.md
  docs/release.md
)

foreach(benchmark_doc IN LISTS benchmark_docs)
  file(READ "${REPO_ROOT}/${benchmark_doc}" benchmark_doc_text)
  string(REPLACE "\r\n" "\n" benchmark_doc_normalized "${benchmark_doc_text}")
  string(REGEX REPLACE "\\\\[ \t]*\n[ \t]*" " " benchmark_doc_flat "${benchmark_doc_normalized}")
  string(REGEX REPLACE "[ \t\n]+" " " benchmark_doc_flat "${benchmark_doc_flat}")

  if(NOT benchmark_doc_flat MATCHES "cmake -S \\. -B build-bench -DFTIMER_BUILD_BENCH=ON -DCMAKE_BUILD_TYPE=Release")
    message(FATAL_ERROR
      "${benchmark_doc} benchmark instructions must include the complete CMake 3.16-compatible configure command."
    )
  endif()

  string(FIND "${benchmark_doc_text}" "cmake --build build-bench --target ftimer_bench" benchmark_build_found)
  if(benchmark_build_found EQUAL -1)
    message(FATAL_ERROR
      "${benchmark_doc} benchmark instructions must include the ftimer_bench build target command."
    )
  endif()

  string(FIND "${benchmark_doc_text}" "./build-bench/bench/ftimer_bench" benchmark_run_found)
  if(benchmark_run_found EQUAL -1)
    message(FATAL_ERROR
      "${benchmark_doc} benchmark instructions must include the ftimer_bench executable command."
    )
  endif()

  file(STRINGS "${REPO_ROOT}/${benchmark_doc}" benchmark_doc_lines)
  foreach(benchmark_doc_line IN LISTS benchmark_doc_lines)
    if(benchmark_doc_line MATCHES "(^|[ \t`])cmake([ \t]+[^`[:space:]]+)*[ \t]+--fresh($|[ \t`])" AND
       NOT benchmark_doc_line MATCHES "CMake[ \t]+3\\.24")
      message(FATAL_ERROR
        "${benchmark_doc} must mark cmake --fresh as a CMake 3.24+ convenience on the same line and must not use it as a primary benchmark command."
      )
    endif()
  endforeach()
endforeach()

set(release_command_paths
  ${benchmark_docs}
  CONTRIBUTING.md
  docs/troubleshooting.md
  Makefile
)

foreach(command_path IN LISTS release_command_paths)
  file(READ "${REPO_ROOT}/${command_path}" command_text)
  if(command_text MATCHES "ctest[ \t]+--test-dir")
    message(FATAL_ERROR
      "${command_path} must use CTest 3.16-compatible test commands instead of ctest --test-dir."
    )
  endif()
endforeach()

set(current_contract_docs
  AGENTS.md
  CLAUDE.md
  README.md
  docs/design.md
  docs/maintainer.md
  docs/openmp-timing-modes.md
  docs/semantics.md
  docs/troubleshooting.md
)

set(forbidden_current_contract_phrases
  "Current `main` is in Phase"
  "Current `main` implements the Phase"
  "During Phase"
  "Phase 6"
  "Phase 1 exception"
  "Starting in Phase 2"
  "phase-bounded"
  "phase-specific"
  "per phase"
  "by phase"
  "Load only the phase you need"
  "this phase does not make"
  "Sparse/union hybrid participation reductions"
  "sparse/union hybrid participation reductions"
)

foreach(current_contract_doc IN LISTS current_contract_docs)
  file(READ "${REPO_ROOT}/${current_contract_doc}" current_contract_doc_text)
  foreach(forbidden_phrase IN LISTS forbidden_current_contract_phrases)
    string(FIND "${current_contract_doc_text}" "${forbidden_phrase}" forbidden_index)
    if(NOT forbidden_index EQUAL -1)
      message(FATAL_ERROR
        "${current_contract_doc} contains stale current-state wording: ${forbidden_phrase}"
      )
    endif()
  endforeach()
endforeach()

file(READ "${REPO_ROOT}/README.md" release_readme_text)
set(readme_troubleshooting_needles
  "see the symptom-oriented [`docs/troubleshooting.md`](docs/troubleshooting.md)"
  "For practical remedies to first-use build failures, MPI summary hangs, OpenMP"
  "- Troubleshooting guide: [`docs/troubleshooting.md`](docs/troubleshooting.md)"
)

foreach(readme_troubleshooting_needle IN LISTS readme_troubleshooting_needles)
  string(FIND "${release_readme_text}" "${readme_troubleshooting_needle}" troubleshooting_link_index)
  if(troubleshooting_link_index EQUAL -1)
    message(FATAL_ERROR
      "README.md must keep the troubleshooting guide discoverable: missing '${readme_troubleshooting_needle}'."
    )
  endif()
endforeach()

file(READ "${REPO_ROOT}/docs/troubleshooting.md" troubleshooting_doc_text)
file(READ "${REPO_ROOT}/tests/public_symbol_allowlist.txt" public_symbol_allowlist_text)

set(troubleshooting_public_api_tokens
  ftimer_mpi_union_summary
  ftimer_write_mpi_union_summary_csv
  ftimer_stop
  ftimer_mpi_summary
  ftimer_write_summary_csv
  ftimer_write_mpi_summary_csv
  ftimer_write_mpi_union_summary_csv
)

foreach(troubleshooting_public_api_token IN LISTS troubleshooting_public_api_tokens)
  string(FIND "${troubleshooting_doc_text}" "${troubleshooting_public_api_token}" token_doc_index)
  if(token_doc_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md must document public API token '${troubleshooting_public_api_token}'."
    )
  endif()

  if(NOT public_symbol_allowlist_text MATCHES "(^|\n)ftimer\\|${troubleshooting_public_api_token}\\|stable(\n|$)")
    message(FATAL_ERROR
      "docs/troubleshooting.md documents '${troubleshooting_public_api_token}', but tests/public_symbol_allowlist.txt does not mark it as a stable ftimer API."
    )
  endif()
endforeach()

set(troubleshooting_status_tokens
  FTIMER_ERR_MPI_INCON
  FTIMER_ERR_ACTIVE
  FTIMER_ERR_NOT_IMPLEMENTED
  FTIMER_ERR_IO
)

foreach(troubleshooting_status_token IN LISTS troubleshooting_status_tokens)
  string(FIND "${troubleshooting_doc_text}" "${troubleshooting_status_token}" status_doc_index)
  if(status_doc_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md must document status token '${troubleshooting_status_token}'."
    )
  endif()

  if(NOT public_symbol_allowlist_text MATCHES "(^|\n)ftimer_types\\|${troubleshooting_status_token}\\|stable(\n|$)")
    message(FATAL_ERROR
      "docs/troubleshooting.md documents '${troubleshooting_status_token}', but tests/public_symbol_allowlist.txt does not mark it as a stable ftimer_types API."
    )
  endif()
endforeach()

set(retired_planning_docs
  docs/openmp-hybrid-api-design.md
  docs/openmp-hybrid-mpi-reduction-design.md
  docs/openmp-hybrid-strategy-decision.md
  docs/openmp-hybrid-summary-design.md
  docs/openmp-hybrid-validation-plan.md
  docs/openmp-thread-lane-runtime-design.md
  docs/mpi-descriptor-preflight-decision.md
  docs/mpi-sparse-summary-decision.md
)

foreach(retired_planning_doc IN LISTS retired_planning_docs)
  if(EXISTS "${REPO_ROOT}/${retired_planning_doc}")
    message(FATAL_ERROR
      "${retired_planning_doc} is a historical planning artifact and must not remain in the top-level docs surface."
    )
  endif()
endforeach()

set(release_navigation_docs
  README.md
  docs/semantics.md
  docs/design.md
  docs/installed-api.md
  docs/release.md
  docs/openmp-timing-modes.md
  docs/troubleshooting.md
)

foreach(release_navigation_doc IN LISTS release_navigation_docs)
  file(READ "${REPO_ROOT}/${release_navigation_doc}" release_navigation_doc_text)
  foreach(retired_planning_doc IN LISTS retired_planning_docs)
    get_filename_component(retired_planning_name "${retired_planning_doc}" NAME)
    string(FIND "${release_navigation_doc_text}" "${retired_planning_name}" retired_link_index)
    if(NOT retired_link_index EQUAL -1)
      message(FATAL_ERROR
        "${release_navigation_doc} must not send users to historical planning artifact ${retired_planning_name}; move durable current-state details into live docs instead."
      )
    endif()
  endforeach()
endforeach()
