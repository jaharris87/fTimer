cmake_minimum_required(VERSION 3.16)

set(allowlist_path "${REPO_ROOT}/tests/public_symbol_allowlist.txt")
set(installed_api_path "${REPO_ROOT}/docs/installed-api.md")

if(NOT EXISTS "${allowlist_path}")
  message(FATAL_ERROR "Missing public symbol allowlist: ${allowlist_path}")
endif()

file(STRINGS "${allowlist_path}" allowlist_lines)

set(expected_symbols)
set(documented_unstable_symbols)

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
  if(stability STREQUAL "unstable" OR stability STREQUAL "test-only")
    list(APPEND documented_unstable_symbols "${symbol_name}")
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

  file(STRINGS "${source_path}" public_lines REGEX "^[ \t]*public[ \t]*::")

  foreach(public_line IN LISTS public_lines)
    string(REGEX REPLACE "!.*$" "" declaration "${public_line}")

    if(declaration MATCHES "&")
      message(FATAL_ERROR
        "Public symbol check does not accept continued public declarations yet: ${source_file}: ${public_line}"
      )
    endif()

    string(REGEX REPLACE "^[ \t]*public[ \t]*::[ \t]*" "" symbol_list "${declaration}")
    string(REPLACE "," ";" symbols "${symbol_list}")

    foreach(symbol_name IN LISTS symbols)
      string(STRIP "${symbol_name}" symbol_name)
      if(symbol_name STREQUAL "")
        continue()
      endif()
      list(APPEND actual_symbols "${module_name}::${symbol_name}")
    endforeach()
  endforeach()
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

foreach(symbol_name IN LISTS documented_unstable_symbols)
  if(NOT installed_api_text MATCHES "`${symbol_name}`")
    message(FATAL_ERROR
      "Unstable public symbol '${symbol_name}' must be explicitly documented in docs/installed-api.md."
    )
  endif()
endforeach()
