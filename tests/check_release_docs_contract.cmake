cmake_minimum_required(VERSION 3.16)

set(required_paths
  AGENTS.md
  CLAUDE.md
  README.md
  docs/design.md
  docs/implementation-history.md
  docs/release.md
  docs/semantics.md
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
file(READ "${REPO_ROOT}/docs/semantics.md" semantics_text)

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

list(SORT public_status_constants)

foreach(status_constant IN LISTS public_status_constants)
  if(NOT ftimer_types_text MATCHES "integer,[^\n]*parameter[^\n]*::[ \t]*${status_constant}[ \t]*=[ \t]*([0-9]+)")
    message(FATAL_ERROR "Could not find parameter value for ${status_constant}.")
  endif()
  set(status_value "${CMAKE_MATCH_1}")
  string(FIND
    "${semantics_text}"
    "| `${status_constant}` | `${status_value}` |"
    documented_status
  )
  if(documented_status EQUAL -1)
    message(FATAL_ERROR
      "docs/semantics.md must list public status/error constant ${status_constant} with code ${status_value}."
    )
  endif()
endforeach()

file(READ "${REPO_ROOT}/README.md" readme_text)
string(FIND "${readme_text}" "cmake -S . -B build-bench" benchmark_configure_found)
if(benchmark_configure_found EQUAL -1)
  message(FATAL_ERROR
    "README.md benchmark instructions must include a CMake 3.16-compatible configure command."
  )
endif()

string(FIND "${readme_text}" "CMake 3.24" cmake_fresh_note_found)
if(cmake_fresh_note_found EQUAL -1 AND readme_text MATCHES "cmake[ \t]+--fresh")
  message(FATAL_ERROR
    "README.md must mark cmake --fresh as a CMake 3.24+ convenience when mentioning it."
  )
endif()
