cmake_minimum_required(VERSION 3.16)

set(required_paths
  AGENTS.md
  CLAUDE.md
  README.md
  docs/design.md
  docs/csv-schema.md
  docs/fault-model-traceability.md
  docs/installed-api.md
  docs/implementation-history.md
  docs/maintainer.md
  docs/openmp-timing-modes.md
  docs/package-manager-readiness.md
  docs/release-evidence.md
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

file(READ "${REPO_ROOT}/docs/semantics.md" semantics_text)
file(READ "${REPO_ROOT}/docs/csv-schema.md" csv_schema_text)
string(FIND "${semantics_text}"
  "[`docs/fault-model-traceability.md`](fault-model-traceability.md)"
  fault_model_semantics_link_index)
if(fault_model_semantics_link_index EQUAL -1)
  message(FATAL_ERROR
    "docs/semantics.md must Markdown-link to docs/fault-model-traceability.md."
  )
endif()

string(FIND "${semantics_text}"
  "[`docs/csv-schema.md`](csv-schema.md)"
  csv_schema_semantics_link_index)
if(csv_schema_semantics_link_index EQUAL -1)
  message(FATAL_ERROR
    "docs/semantics.md must Markdown-link to docs/csv-schema.md."
  )
endif()

set(csv_schema_required_terms
  "Issue #303 validates that fTimer needs this compact field dictionary plus tiny"
  "It does not need generated golden CSV fixtures"
  "missing sparse contributors are not zero-filled"
  "Field type"
  "Schema Families"
  "Append validation is a schema-shape"
  "Local summaries are live snapshots"
  "The denominator for participating averages is `participating_rank_count`"
  "`missing_lane_count_known=false`"
  "`missing_rank_lane_sample_count_known=false`"
  "The no-behavior append-validation consolidation question is"
)

foreach(csv_schema_required_term IN LISTS csv_schema_required_terms)
  string(FIND "${csv_schema_text}" "${csv_schema_required_term}" csv_schema_term_index)
  if(csv_schema_term_index EQUAL -1)
    message(FATAL_ERROR
      "docs/csv-schema.md must retain CSV schema decision/field term: ${csv_schema_required_term}"
    )
  endif()
endforeach()

file(READ "${REPO_ROOT}/docs/fault-model-traceability.md" fault_model_text)
file(STRINGS "${REPO_ROOT}/docs/fault-model-traceability.md" fault_model_lines)

function(require_fault_model_contains needle)
  string(FIND "${fault_model_text}" "${needle}" fault_model_needle_index)
  if(fault_model_needle_index EQUAL -1)
    message(FATAL_ERROR
      "docs/fault-model-traceability.md must retain the #309 traceability checkpoint: ${needle}"
    )
  endif()
endfunction()

set(fault_model_required_rows
  "Strict nesting and repair"
  "Callback suppression during repair"
  "Active local snapshots versus stopped-run reductions"
  "Nonmonotonic custom or backend clocks"
  "MPI descriptor mismatch"
  "MPI communicator lifetime and agreement"
  "Sparse participation semantics"
  "Legacy OpenMP worker no-op compatibility"
  "Strict versus sparse hybrid lane/rank mismatches"
  "Scoped-guard ownership versus public ids"
  "Worker diagnostic draining paths"
)

set(fault_model_required_needles
  "#317 owns mixed OpenMP epoch / eligible-lane interpretation evidence"
  "#314 and #316"
)

foreach(fault_model_required_needle IN LISTS fault_model_required_needles)
  require_fault_model_contains("${fault_model_required_needle}")
endforeach()

set(fault_model_matrix_rows)
foreach(fault_model_line IN LISTS fault_model_lines)
  if(NOT fault_model_line MATCHES "^\\|")
    continue()
  endif()
  if(fault_model_line MATCHES "^\\|[ \t]*---")
    continue()
  endif()
  if(fault_model_line MATCHES "^\\|[ \t]*Fault category[ \t]*\\|")
    continue()
  endif()

  if(NOT fault_model_line MATCHES "^\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|([^|]*)\\|[ \t]*$")
    message(FATAL_ERROR
      "docs/fault-model-traceability.md matrix rows must have exactly six columns: ${fault_model_line}"
    )
  endif()

  set(fault_model_category_cell "${CMAKE_MATCH_1}")
  set(fault_model_evidence_cell "${CMAKE_MATCH_5}")
  string(STRIP "${fault_model_category_cell}" fault_model_category_cell)
  string(STRIP "${fault_model_evidence_cell}" fault_model_evidence_cell)
  list(APPEND fault_model_matrix_rows "${fault_model_category_cell}")

  set(fault_model_evidence_remaining "${fault_model_evidence_cell}")
  while(fault_model_evidence_remaining MATCHES "`([^`]+)`")
    set(fault_model_evidence_token "${CMAKE_MATCH_1}")
    if(fault_model_evidence_token MATCHES "^(AGENTS|CLAUDE|README|CONTRIBUTING|SECURITY|SUPPORT|Makefile)(\\.md)?$|^(docs|src|tests|examples|bench)/")
      get_filename_component(fault_model_evidence_abs
        "${REPO_ROOT}/${fault_model_evidence_token}" ABSOLUTE)
      if(NOT EXISTS "${fault_model_evidence_abs}")
        message(FATAL_ERROR
          "docs/fault-model-traceability.md cites missing evidence path: ${fault_model_evidence_token}"
        )
      endif()
    endif()
    string(REGEX REPLACE "^[^`]*`[^`]+`" "" fault_model_evidence_remaining
      "${fault_model_evidence_remaining}")
  endwhile()
endforeach()

foreach(fault_model_required_row IN LISTS fault_model_required_rows)
  set(fault_model_required_row_count 0)
  foreach(fault_model_matrix_row IN LISTS fault_model_matrix_rows)
    if(fault_model_matrix_row STREQUAL fault_model_required_row)
      math(EXPR fault_model_required_row_count "${fault_model_required_row_count} + 1")
    endif()
  endforeach()
  if(NOT fault_model_required_row_count EQUAL 1)
    message(FATAL_ERROR
      "docs/fault-model-traceability.md must contain exactly one matrix row named '${fault_model_required_row}', found ${fault_model_required_row_count}."
    )
  endif()
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

function(extract_markdown_section text header out_var)
  string(FIND "${text}" "## ${header}" section_start_index)
  if(section_start_index EQUAL -1)
    message(FATAL_ERROR "README.md must keep the '## ${header}' section.")
  endif()

  string(SUBSTRING "${text}" "${section_start_index}" -1 section_tail)
  string(FIND "${section_tail}" "\n## " next_section_index)
  if(next_section_index EQUAL -1)
    set(section_text "${section_tail}")
  else()
    string(SUBSTRING "${section_tail}" 0 "${next_section_index}" section_text)
  endif()

  set(${out_var} "${section_text}" PARENT_SCOPE)
endfunction()

extract_markdown_section("${release_readme_text}" "Where To Go Next" readme_where_to_go_next_text)

set(readme_role_routes
  "- First-time user: stay in this README for `First Success`, `Quick Start`, and `Install And Use From Another Project`, then see the symptom-oriented [`docs/troubleshooting.md`](docs/troubleshooting.md) guide if first use goes sideways."
  "- Advanced user: use [Supported Workflows](#supported-workflows) to choose a mode, then jump to [`docs/semantics.md`](docs/semantics.md), [`docs/openmp-timing-modes.md`](docs/openmp-timing-modes.md), [`docs/csv-schema.md`](docs/csv-schema.md), or [`docs/installed-api.md`](docs/installed-api.md) for the exact contract."
  "- Maintainer or release reviewer: use [`docs/release-evidence.md`](docs/release-evidence.md), [`docs/release.md`](docs/release.md), and [`docs/maintainer.md`](docs/maintainer.md)."
  "- Coding agent: use [`AGENTS.md`](AGENTS.md) or [`CLAUDE.md`](CLAUDE.md) for repo workflow and source-of-truth rules, then read [`docs/semantics.md`](docs/semantics.md) and [`docs/maintainer.md`](docs/maintainer.md) as needed."
)

foreach(readme_role_route IN LISTS readme_role_routes)
  string(FIND "${readme_where_to_go_next_text}" "${readme_role_route}" role_route_index)
  if(role_route_index EQUAL -1)
    message(FATAL_ERROR
      "README.md must keep the explicit #336 audience routing in '## Where To Go Next': missing '${readme_role_route}'."
    )
  endif()
endforeach()

set(readme_route_destination_headings
  "## First Success"
  "## Quick Start"
  "## Install And Use From Another Project"
  "## Supported Workflows"
)

foreach(readme_route_destination_heading IN LISTS readme_route_destination_headings)
  string(FIND "${release_readme_text}" "${readme_route_destination_heading}" destination_heading_index)
  if(destination_heading_index EQUAL -1)
    message(FATAL_ERROR
      "README.md must keep the in-README destination heading required by the #336 audience routing: missing '${readme_route_destination_heading}'."
    )
  endif()
endforeach()

file(READ "${REPO_ROOT}/docs/troubleshooting.md" troubleshooting_doc_text)
file(READ "${REPO_ROOT}/tests/public_symbol_allowlist.txt" public_symbol_allowlist_text)
file(READ "${REPO_ROOT}/CMakeLists.txt" root_cmakelists_text)

function(require_troubleshooting_contains needle)
  string(FIND "${troubleshooting_doc_text}" "${needle}" troubleshooting_needle_index)
  if(troubleshooting_needle_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md must keep troubleshooting contract text: missing '${needle}'."
    )
  endif()
endfunction()

function(require_troubleshooting_section_contains section_title needle)
  set(section_header "## ${section_title}")
  string(FIND "${troubleshooting_doc_text}" "${section_header}" troubleshooting_section_index)
  if(troubleshooting_section_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md must keep troubleshooting section '${section_header}'."
    )
  endif()

  string(SUBSTRING "${troubleshooting_doc_text}" "${troubleshooting_section_index}" -1 troubleshooting_section_tail)
  string(FIND "${troubleshooting_section_tail}" "\n## " troubleshooting_next_section_index)
  if(troubleshooting_next_section_index EQUAL -1)
    set(troubleshooting_section_text "${troubleshooting_section_tail}")
  else()
    string(SUBSTRING "${troubleshooting_section_tail}" 0 "${troubleshooting_next_section_index}" troubleshooting_section_text)
  endif()

  string(FIND "${troubleshooting_section_text}" "${needle}" troubleshooting_section_needle_index)
  if(troubleshooting_section_needle_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md section '${section_header}' must keep troubleshooting contract text: missing '${needle}'."
    )
  endif()
endfunction()

require_troubleshooting_contains("cmake -B build-smoke")
require_troubleshooting_contains("cmake --build build-smoke")
require_troubleshooting_contains("cmake -E chdir build-smoke ctest --output-on-failure")
require_troubleshooting_contains("cmake --build build-smoke --target basic_usage")
require_troubleshooting_contains("./build-smoke/examples/basic_usage")

require_troubleshooting_section_contains("Configure Fails With pFUnit Enabled"
  "FC=gfortran cmake -B build -DFTIMER_BUILD_TESTS=ON -DPFUNIT_DIR=/path/to/pfunit"
)
require_troubleshooting_section_contains("Configure Fails With pFUnit Enabled"
  "If you only want the smoke path and examples, leave `FTIMER_BUILD_TESTS=OFF`."
)
require_troubleshooting_section_contains("Downstream Configure Cannot Find fTimer"
  "find_package(fTimer CONFIG REQUIRED)"
)
require_troubleshooting_section_contains("Downstream Configure Cannot Find fTimer"
  "CMAKE_PREFIX_PATH=/path/to/ftimer-install"
)
require_troubleshooting_section_contains("Downstream Configure Cannot Find fTimer"
  "cmake -E chdir build-smoke ctest --output-on-failure -R ftimer_installed_package_consumer$"
)
require_troubleshooting_section_contains("Configure Fails With MPI Enabled"
  "FC=mpifort cmake -B build-mpi-smoke -DFTIMER_USE_MPI=ON -DFTIMER_BUILD_TESTS=OFF"
)
require_troubleshooting_section_contains("Configure Fails With MPI Enabled"
  "Configure runs a small `mpi_f08` probe and fails early"
)
require_troubleshooting_section_contains("Configure Fails With OpenMP Enabled"
  "FC=gfortran cmake -B build-openmp -DFTIMER_USE_OPENMP=ON"
)
require_troubleshooting_section_contains("Configure Fails With OpenMP Enabled"
  "FC=flang-19 cmake -B build-openmp-flang -DFTIMER_USE_OPENMP=ON -DOpenMP_ROOT=/path/to/libomp"
)
require_troubleshooting_section_contains("OpenMP Worker Calls Do Not Appear In The Summary"
  "Worker-thread calls made inside an"
)
require_troubleshooting_section_contains("OpenMP Worker Calls Do Not Appear In The Summary"
  "Global compiler flags such as `-fopenmp` do not enable fTimer's guards when the"
)
require_troubleshooting_section_contains("OpenMP Worker Calls Do Not Appear In The Summary"
  "library was configured with `FTIMER_USE_OPENMP=OFF`"
)

require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_MPI_INCON`"
  "Strict MPI summaries and reports require identical timer descriptor trees"
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_MPI_INCON`"
  "cause `FTIMER_ERR_MPI_INCON`"
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_MPI_INCON`"
  "Sparse union entries report explicit participation counts."
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_ACTIVE`"
  "MPI summaries and MPI report/CSV writers require a fully stopped timer set."
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_ACTIVE`"
  "returns `FTIMER_ERR_ACTIVE`"
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_ACTIVE`"
  "For local debugging snapshots, use `ftimer_get_summary()` separately."
)
require_troubleshooting_section_contains("MPI Summary Returns `FTIMER_ERR_ACTIVE`"
  "MPI summary APIs intentionally do not."
)
require_troubleshooting_section_contains("MPI Summary Hangs"
  "divergent communicators or missing collective"
)
require_troubleshooting_section_contains("MPI Summary Hangs"
  "Rank-conditional code does not skip the collective itself."
)
require_troubleshooting_section_contains("MPI APIs Return `FTIMER_ERR_NOT_IMPLEMENTED`"
  "They do not fall back to local summaries"
)
require_troubleshooting_section_contains("MPI APIs Return `FTIMER_ERR_NOT_IMPLEMENTED`"
  "not create or replace MPI report files."
)
require_troubleshooting_section_contains("CSV Columns Look Different Between Files"
  "Local and strict MPI CSV use `format_version=2`."
)
require_troubleshooting_section_contains("CSV Columns Look Different Between Files"
  "Do not append sparse union rows to a local/strict MPI CSV file or the reverse."
)
require_troubleshooting_section_contains("CSV Append Returns `FTIMER_ERR_IO`"
  "With `append=.true.`, fTimer validates the existing non-empty file before adding"
)
require_troubleshooting_section_contains("CSV Append Returns `FTIMER_ERR_IO`"
  "a final record that is not newline-terminated"
)
require_troubleshooting_section_contains("CSV Append Returns `FTIMER_ERR_IO`"
  "The existing file is left unchanged on validation failure."
)
require_troubleshooting_section_contains("Reports Look Incomplete"
  "Strict MPI text reports are abbreviated human reports."
)
require_troubleshooting_section_contains("Reports Look Incomplete"
  "The complete"
)
require_troubleshooting_section_contains("Reports Look Incomplete"
  "machine-facing data is in `ftimer_mpi_summary_t` or the strict MPI CSV output."
)
require_troubleshooting_section_contains("Reports Look Incomplete"
  "For sparse/rank-conditional work, use `ftimer_mpi_union_summary_t` or sparse"
)
require_troubleshooting_section_contains("Timings Do Not Include Device Or Synchronized MPI Time"
  "does not synchronize GPU/device queues"
)
require_troubleshooting_section_contains("Timings Do Not Include Device Or Synchronized MPI Time"
  "does not insert MPI barriers"
)

set(troubleshooting_routing_docs
  AGENTS.md
  CLAUDE.md
  docs/design.md
)

foreach(troubleshooting_routing_doc IN LISTS troubleshooting_routing_docs)
  file(READ "${REPO_ROOT}/${troubleshooting_routing_doc}" troubleshooting_routing_doc_text)
  string(FIND "${troubleshooting_routing_doc_text}" "docs/troubleshooting.md" troubleshooting_routing_index)
  if(troubleshooting_routing_index EQUAL -1)
    message(FATAL_ERROR
      "${troubleshooting_routing_doc} must route practical first-use, MPI, OpenMP, CSV, and summary/report failures to docs/troubleshooting.md."
    )
  endif()
endforeach()

set(troubleshooting_cmake_option_tokens
  FTIMER_USE_MPI
  FTIMER_USE_OPENMP
  FTIMER_OPENMP_ASSUME_MASTER_PROBE_OK
  FTIMER_BUILD_TESTS
  FTIMER_BUILD_SMOKE_TESTS
  FTIMER_BUILD_EXAMPLES
  FTIMER_BUILD_BENCH
)

set(troubleshooting_public_aliases
  finalize=ftimer_finalize
  get_summary=ftimer_get_summary
  init=ftimer_init
  print_mpi_summary=ftimer_print_mpi_summary
  print_mpi_union_summary=ftimer_print_mpi_union_summary
  print_summary=ftimer_print_summary
  start=ftimer_start
  stop=ftimer_stop
  write_mpi_summary=ftimer_write_mpi_summary
  write_mpi_union_summary=ftimer_write_mpi_union_summary
  write_summary=ftimer_write_summary
)

set(troubleshooting_ignored_identifier_tokens
  ftimer
  ftimer_core
  ftimer_installed_package_consumer
)

string(REGEX MATCHALL "[A-Za-z][A-Za-z0-9_]*" troubleshooting_identifier_tokens "${troubleshooting_doc_text}")
list(REMOVE_DUPLICATES troubleshooting_identifier_tokens)

set(troubleshooting_documented_public_tokens)
set(troubleshooting_documented_cmake_options)

foreach(troubleshooting_identifier IN LISTS troubleshooting_identifier_tokens)
  if(troubleshooting_identifier IN_LIST troubleshooting_ignored_identifier_tokens)
    continue()
  endif()

  if(troubleshooting_identifier IN_LIST troubleshooting_cmake_option_tokens)
    list(APPEND troubleshooting_documented_cmake_options "${troubleshooting_identifier}")
    continue()
  endif()

  set(troubleshooting_canonical_symbol "")
  foreach(troubleshooting_public_alias IN LISTS troubleshooting_public_aliases)
    string(REPLACE "=" ";" troubleshooting_public_alias_parts "${troubleshooting_public_alias}")
    list(GET troubleshooting_public_alias_parts 0 troubleshooting_public_alias_name)
    list(GET troubleshooting_public_alias_parts 1 troubleshooting_public_alias_symbol)
    if(troubleshooting_identifier STREQUAL troubleshooting_public_alias_name)
      set(troubleshooting_canonical_symbol "${troubleshooting_public_alias_symbol}")
    endif()
  endforeach()

  if(troubleshooting_canonical_symbol)
    list(APPEND troubleshooting_documented_public_tokens "${troubleshooting_canonical_symbol}")
    continue()
  endif()

  if(troubleshooting_identifier MATCHES "^(ftimer_[A-Za-z0-9_]+|FTIMER_[A-Za-z0-9_]+)$")
    list(APPEND troubleshooting_documented_public_tokens "${troubleshooting_identifier}")
    continue()
  endif()

  if(troubleshooting_identifier MATCHES "^(print_|write_)[A-Za-z0-9_]+$")
    message(FATAL_ERROR
      "docs/troubleshooting.md documents shorthand public API alias '${troubleshooting_identifier}', but tests/check_release_docs_contract.cmake does not map it to a stable public symbol."
    )
  endif()
endforeach()

list(REMOVE_DUPLICATES troubleshooting_documented_public_tokens)
list(REMOVE_DUPLICATES troubleshooting_documented_cmake_options)

foreach(troubleshooting_cmake_option IN LISTS troubleshooting_documented_cmake_options)
  if(NOT root_cmakelists_text MATCHES "option\\([ \t\r\n]*${troubleshooting_cmake_option}([ \t\r\n]|\\))")
    message(FATAL_ERROR
      "docs/troubleshooting.md documents CMake option '${troubleshooting_cmake_option}', but CMakeLists.txt does not define it as an option."
    )
  endif()
endforeach()

foreach(troubleshooting_public_token IN LISTS troubleshooting_documented_public_tokens)
  if(NOT public_symbol_allowlist_text MATCHES "(^|\n)[^|\n]+\\|${troubleshooting_public_token}\\|stable(\n|$)")
    message(FATAL_ERROR
      "docs/troubleshooting.md documents '${troubleshooting_public_token}', but tests/public_symbol_allowlist.txt does not mark it as a stable public symbol."
    )
  endif()
endforeach()

set(required_troubleshooting_public_tokens
  FTIMER_ERR_MPI_INCON
  FTIMER_ERR_ACTIVE
  FTIMER_ERR_NOT_IMPLEMENTED
  FTIMER_ERR_IO
  ftimer_get_summary
  ftimer_mpi_summary
  ftimer_mpi_union_summary
  ftimer_openmp_t
  ftimer_mpi_summary_t
  ftimer_mpi_union_summary_t
  ftimer_write_summary_csv
  ftimer_write_mpi_summary_csv
  ftimer_write_mpi_union_summary_csv
)

foreach(required_troubleshooting_public_token IN LISTS required_troubleshooting_public_tokens)
  list(FIND troubleshooting_documented_public_tokens "${required_troubleshooting_public_token}" required_troubleshooting_public_token_index)
  if(required_troubleshooting_public_token_index EQUAL -1)
    message(FATAL_ERROR
      "docs/troubleshooting.md must continue to document public troubleshooting token '${required_troubleshooting_public_token}'."
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
  docs/release-evidence.md
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

file(STRINGS "${REPO_ROOT}/docs/release.md" release_doc_lines)
get_filename_component(release_doc_dir "${REPO_ROOT}/docs/release.md" DIRECTORY)
get_filename_component(release_evidence_abs "${REPO_ROOT}/docs/release-evidence.md" ABSOLUTE)
set(release_links_to_evidence FALSE)

foreach(release_doc_line IN LISTS release_doc_lines)
  set(remaining_line "${release_doc_line}")
  while(remaining_line MATCHES "\\[[^]]*\\]\\(([^)]+)\\)")
    set(link_target "${CMAKE_MATCH_1}")
    string(REGEX REPLACE "^[ \t]*<([^>]+)>.*$" "\\1" link_target "${link_target}")
    string(REGEX REPLACE "^[ \t]*([^ \t\"']+).*$" "\\1" link_target "${link_target}")
    string(REGEX REPLACE "#.*$" "" link_path "${link_target}")

    if(NOT link_path STREQUAL "" AND
       NOT link_path MATCHES "^[A-Za-z][A-Za-z0-9+.-]*:" AND
       NOT link_path MATCHES "^#")
      get_filename_component(link_abs "${release_doc_dir}/${link_path}" ABSOLUTE)
      if(link_abs STREQUAL release_evidence_abs)
        set(release_links_to_evidence TRUE)
      endif()
    endif()

    string(REGEX REPLACE "^[^[]*\\[[^]]*\\]\\([^)]+\\)" "" remaining_line "${remaining_line}")
  endwhile()
endforeach()

if(NOT release_links_to_evidence)
  message(FATAL_ERROR
    "docs/release.md must link to docs/release-evidence.md for release claim-evidence review."
  )
endif()

file(READ "${REPO_ROOT}/docs/release-evidence.md" release_evidence_text)
set(required_release_evidence_terms
  "Serial timing"
  "Pure MPI"
  "OpenMP compatibility"
  "`ftimer_openmp_t`"
  "Strict/sparse hybrid output"
  "Stable CSV/export claims"
  "Installed CMake package behavior"
  "Spack/EasyBuild readiness"
  "Public symbols"
  "Benchmark evidence"
  "Plausible but unvalidated"
  "Release-validated"
)

foreach(required_release_evidence_term IN LISTS required_release_evidence_terms)
  string(FIND "${release_evidence_text}" "${required_release_evidence_term}" release_evidence_term_index)
  if(release_evidence_term_index EQUAL -1)
    message(FATAL_ERROR
      "docs/release-evidence.md must keep release ledger term '${required_release_evidence_term}'."
    )
  endif()
endforeach()

file(STRINGS "${REPO_ROOT}/docs/release-evidence.md" release_evidence_lines)
set(required_release_evidence_rows
  "Serial timing"
  "Pure MPI"
  "OpenMP compatibility"
  "`ftimer_openmp_t`"
  "Strict/sparse hybrid output"
  "Stable CSV/export claims"
  "Installed CMake package behavior"
  "Spack/EasyBuild readiness"
  "Public symbols"
  "Benchmark evidence"
)

foreach(required_release_evidence_row IN LISTS required_release_evidence_rows)
  set(release_evidence_row_found FALSE)
  set(release_evidence_row_count 0)

  foreach(release_evidence_line IN LISTS release_evidence_lines)
    if(release_evidence_line MATCHES
       "^\\|[ \t]*${required_release_evidence_row}[ \t]*\\|[ \t]*([^|]+)[ \t]*\\|[ \t]*([^|]+)[ \t]*\\|[ \t]*([^|]+)[ \t]*\\|[ \t]*$")
      math(EXPR release_evidence_row_count "${release_evidence_row_count} + 1")
      set(release_evidence_row_found TRUE)
      set(release_evidence_status_cell "${CMAKE_MATCH_1}")
      set(release_evidence_evidence_cell "${CMAKE_MATCH_2}")
      set(release_evidence_caveat_cell "${CMAKE_MATCH_3}")
      string(STRIP "${release_evidence_status_cell}" release_evidence_status_cell)
      string(STRIP "${release_evidence_evidence_cell}" release_evidence_evidence_cell)
      string(STRIP "${release_evidence_caveat_cell}" release_evidence_caveat_cell)

      if(release_evidence_status_cell STREQUAL "" OR
         release_evidence_evidence_cell STREQUAL "" OR
         release_evidence_caveat_cell STREQUAL "")
        message(FATAL_ERROR
          "docs/release-evidence.md claim row '${required_release_evidence_row}' must keep non-empty status, evidence, and caveat cells."
        )
      endif()

      if(NOT release_evidence_evidence_cell MATCHES
         "(build-[A-Za-z0-9_-]+|test-[A-Za-z0-9_-]+|[A-Za-z0-9_]+_smoke|tests/|examples/|docs/|README\\.md|CMakeLists\\.txt|CI job|CTest)")
        message(FATAL_ERROR
          "docs/release-evidence.md claim row '${required_release_evidence_row}' must cite concrete evidence such as CI jobs, CTest names, tests, examples, or docs."
        )
      endif()
    endif()
  endforeach()

  if(NOT release_evidence_row_found)
    message(FATAL_ERROR
      "docs/release-evidence.md must keep a claim ledger table row for '${required_release_evidence_row}'."
    )
  endif()

  if(release_evidence_row_count GREATER 1)
    message(FATAL_ERROR
      "docs/release-evidence.md must keep exactly one claim ledger table row for '${required_release_evidence_row}'."
    )
  endif()
endforeach()

file(READ "${REPO_ROOT}/docs/package-manager-readiness.md" package_manager_readiness_text)
set(package_manager_required_terms
  "spack"
  "eb"
  "Serial | Package-manager friendly"
  "MPI | Package-manager friendly"
  "OpenMP | Package-manager friendly"
  "MPI+OpenMP | Package-manager friendly"
  "Cross-compiling or execution-restricted OpenMP"
  "No fTimer source patches were identified"
  "Local package-manager execution was not available during this spike"
  "Do not add maintained in-repository Spack or EasyBuild recipe files now"
  "Recommended action: docs clarification plus future upstream recipe"
  "depends_on(\"cmake@3.24:\", when=\"+openmp\", type=\"build\")"
  "LLVM Flang OpenMP packages have the compiler-id support fTimer requires"
  "wrapper-, and feature-mode-specific"
)

foreach(package_manager_required_term IN LISTS package_manager_required_terms)
  string(FIND "${package_manager_readiness_text}" "${package_manager_required_term}"
    package_manager_term_index)
  if(package_manager_term_index EQUAL -1)
    message(FATAL_ERROR
      "docs/package-manager-readiness.md must keep package-manager readiness acceptance term: ${package_manager_required_term}"
    )
  endif()
endforeach()
