cmake_minimum_required(VERSION 3.16)

set(allowlist_path "${REPO_ROOT}/tests/public_symbol_allowlist.txt")
set(installed_api_path "${REPO_ROOT}/docs/installed-api.md")

if(NOT EXISTS "${allowlist_path}")
  message(FATAL_ERROR "Missing public symbol allowlist: ${allowlist_path}")
endif()

file(STRINGS "${allowlist_path}" allowlist_lines)

set(expected_symbols)
set(stable_symbols)
set(unstable_symbols)
set(test_only_symbols)

foreach(line IN LISTS allowlist_lines)
  string(STRIP "${line}" line)
  if(line STREQUAL "" OR line MATCHES "^#")
    continue()
  endif()

  string(REPLACE "|" ";" fields "${line}")
  list(LENGTH fields field_count)
  if(NOT field_count EQUAL 3)
    message(FATAL_ERROR
      "Malformed public symbol allowlist line '${line}'. Expected module|symbol|stability."
    )
  endif()

  list(GET fields 0 module_name)
  list(GET fields 1 symbol_name)
  list(GET fields 2 stability)

  if(NOT stability STREQUAL "stable" AND
     NOT stability STREQUAL "unstable" AND
     NOT stability STREQUAL "test-only")
    message(FATAL_ERROR
      "Invalid stability '${stability}' for ${module_name}::${symbol_name}."
    )
  endif()

  list(APPEND expected_symbols "${module_name}::${symbol_name}")
  if(stability STREQUAL "stable")
    list(APPEND stable_symbols "${symbol_name}")
  elseif(stability STREQUAL "unstable")
    list(APPEND unstable_symbols "${symbol_name}")
  elseif(stability STREQUAL "test-only")
    list(APPEND test_only_symbols "${symbol_name}")
  endif()
endforeach()

set(module_sources
  "ftimer|src/ftimer.F90"
  "ftimer_core|src/ftimer_core.F90"
  "ftimer_types|src/ftimer_types.F90"
)

set(actual_symbols)

foreach(module_source IN LISTS module_sources)
  string(REPLACE "|" ";" source_fields "${module_source}")
  list(GET source_fields 0 module_name)
  list(GET source_fields 1 source_file)
  set(source_path "${REPO_ROOT}/${source_file}")

  file(STRINGS "${source_path}" source_lines)

  set(has_default_private FALSE)
  set(seen_public_declaration FALSE)
  set(in_ftimer_build_tests FALSE)
  set(in_derived_type FALSE)

  foreach(source_line IN LISTS source_lines)
    string(REGEX REPLACE "!.*$" "" declaration "${source_line}")
    string(STRIP "${declaration}" stripped_declaration)

    if(stripped_declaration MATCHES "^#ifdef[ \t]+FTIMER_BUILD_TESTS$" OR
       stripped_declaration MATCHES "^#if[ \t]+defined\\(FTIMER_BUILD_TESTS\\)$")
      set(in_ftimer_build_tests TRUE)
    elseif(stripped_declaration MATCHES "^#else$" OR
           stripped_declaration MATCHES "^#elif")
      set(in_ftimer_build_tests FALSE)
    elseif(stripped_declaration MATCHES "^#endif$")
      set(in_ftimer_build_tests FALSE)
    endif()

    if(stripped_declaration MATCHES "^[Ee][Nn][Dd][ \t]+[Tt][Yy][Pp][Ee]([ \t]+.*)?$")
      set(in_derived_type FALSE)
      continue()
    endif()

    if(stripped_declaration MATCHES "^[Pp][Rr][Ii][Vv][Aa][Tt][Ee]$")
      if(NOT seen_public_declaration)
        set(has_default_private TRUE)
      endif()
    endif()

    if(stripped_declaration MATCHES "^[Pp][Uu][Bb][Ll][Ii][Cc]$")
      message(FATAL_ERROR
        "${source_file} contains a bare public statement. Stable modules must keep default private and list public symbols explicitly."
      )
    endif()

    if(NOT in_derived_type AND
       stripped_declaration MATCHES "^[^!#]*,[ \t]*[Pp][Uu][Bb][Ll][Ii][Cc][ \t]*(,|::|$)")
      message(FATAL_ERROR
        "${source_file} contains a public declaration attribute. Stable modules must use standalone 'public :: name' declarations so the allowlist parser sees every module-level public symbol."
      )
    endif()

    if(NOT in_derived_type AND
       stripped_declaration MATCHES "^[Tt][Yy][Pp][Ee][ \t]*(,|::)")
      set(in_derived_type TRUE)
    endif()

    if(NOT stripped_declaration MATCHES "^[Pp][Uu][Bb][Ll][Ii][Cc][ \t]*::")
      continue()
    endif()

    set(seen_public_declaration TRUE)
    if(declaration MATCHES "&")
      message(FATAL_ERROR
        "Public symbol check does not accept continued public declarations yet: ${source_file}: ${source_line}"
      )
    endif()

    string(REGEX REPLACE "^[ \t]*[Pp][Uu][Bb][Ll][Ii][Cc][ \t]*::[ \t]*" "" symbol_list "${declaration}")
    string(REPLACE "," ";" symbols "${symbol_list}")

    foreach(symbol_name IN LISTS symbols)
      string(STRIP "${symbol_name}" symbol_name)
      if(symbol_name STREQUAL "")
        continue()
      endif()
      list(FIND test_only_symbols "${symbol_name}" test_only_index)
      if(NOT test_only_index EQUAL -1 AND NOT in_ftimer_build_tests)
        message(FATAL_ERROR
          "${module_name}::${symbol_name} is marked test-only but is not declared inside an FTIMER_BUILD_TESTS preprocessor guard."
        )
      endif()
      list(APPEND actual_symbols "${module_name}::${symbol_name}")
    endforeach()
  endforeach()

  if(NOT has_default_private)
    message(FATAL_ERROR
      "${source_file} must declare default private before any public symbol declarations so implicit public exports cannot bypass the allowlist."
    )
  endif()
endforeach()

list(SORT expected_symbols)
list(SORT actual_symbols)

set(missing_symbols)
foreach(expected_symbol IN LISTS expected_symbols)
  list(FIND actual_symbols "${expected_symbol}" found_index)
  if(found_index EQUAL -1)
    list(APPEND missing_symbols "${expected_symbol}")
  endif()
endforeach()

set(extra_symbols)
foreach(actual_symbol IN LISTS actual_symbols)
  list(FIND expected_symbols "${actual_symbol}" found_index)
  if(found_index EQUAL -1)
    list(APPEND extra_symbols "${actual_symbol}")
  endif()
endforeach()

if(missing_symbols OR extra_symbols)
  string(REPLACE ";" "\n  " missing_text "${missing_symbols}")
  string(REPLACE ";" "\n  " extra_text "${extra_symbols}")
  message(FATAL_ERROR
    "Stable-module public symbols differ from tests/public_symbol_allowlist.txt.\n"
    "Missing from source:\n  ${missing_text}\n"
    "Extra in source:\n  ${extra_text}\n"
    "Update the allowlist and installed API documentation intentionally when changing this boundary."
  )
endif()

file(READ "${installed_api_path}" installed_api_text)

if(NOT installed_api_text MATCHES "Unstable public-by-necessity symbols")
  message(FATAL_ERROR
    "docs/installed-api.md must include an explicit unstable public-by-necessity section."
  )
endif()

function(ftimer_extract_doc_section out_var heading next_heading)
  if(NOT installed_api_text MATCHES "${heading}\n(.*)\n${next_heading}")
    message(FATAL_ERROR
      "docs/installed-api.md must include a '${heading}' section followed by '${next_heading}'."
    )
  endif()
  set(${out_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

function(ftimer_require_doc_symbols section_name section_text symbols)
  foreach(symbol_name IN LISTS ${symbols})
    if(NOT section_text MATCHES "`${symbol_name}`")
      message(FATAL_ERROR
        "Symbol '${symbol_name}' must be documented in docs/installed-api.md section '${section_name}'."
      )
    endif()
  endforeach()
endfunction()

function(ftimer_reject_doc_symbols section_name section_text symbols)
  foreach(symbol_name IN LISTS ${symbols})
    if(section_text MATCHES "`${symbol_name}`")
      message(FATAL_ERROR
        "Symbol '${symbol_name}' is documented in docs/installed-api.md section '${section_name}', but its allowlist stability class does not belong there."
      )
    endif()
  endforeach()
endfunction()

ftimer_extract_doc_section(stable_doc "## Stable user API" "## Unstable public-by-necessity symbols")
ftimer_extract_doc_section(unstable_doc "## Unstable public-by-necessity symbols" "## Test-only public symbols")
ftimer_extract_doc_section(test_only_doc "## Test-only public symbols" "## Installed implementation artifacts")

ftimer_require_doc_symbols("Stable user API" "${stable_doc}" stable_symbols)
ftimer_reject_doc_symbols("Stable user API" "${stable_doc}" unstable_symbols)
ftimer_reject_doc_symbols("Stable user API" "${stable_doc}" test_only_symbols)

ftimer_require_doc_symbols("Unstable public-by-necessity symbols" "${unstable_doc}" unstable_symbols)
ftimer_reject_doc_symbols("Unstable public-by-necessity symbols" "${unstable_doc}" stable_symbols)
ftimer_reject_doc_symbols("Unstable public-by-necessity symbols" "${unstable_doc}" test_only_symbols)

ftimer_require_doc_symbols("Test-only public symbols" "${test_only_doc}" test_only_symbols)
ftimer_reject_doc_symbols("Test-only public symbols" "${test_only_doc}" stable_symbols)
ftimer_reject_doc_symbols("Test-only public symbols" "${test_only_doc}" unstable_symbols)
