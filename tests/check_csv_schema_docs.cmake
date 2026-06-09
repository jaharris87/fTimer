cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED REPO_ROOT)
  message(FATAL_ERROR "REPO_ROOT is required")
endif()

set(csv_quote "\"")

function(require_text_contains path needle)
  file(READ "${path}" text)
  string(FIND "${text}" "${needle}" found_index)
  if(found_index EQUAL -1)
    message(FATAL_ERROR
      "${path} must contain required CSV schema text: ${needle}"
    )
  endif()
endfunction()

function(csv_field_count record out_var)
  string(LENGTH "${record}" record_len)
  set(count 1)
  set(in_quotes FALSE)
  set(i 0)

  while(i LESS record_len)
    string(SUBSTRING "${record}" ${i} 1 ch)
    if(ch STREQUAL "${csv_quote}")
      if(in_quotes)
        math(EXPR next_i "${i} + 1")
        if(next_i LESS record_len)
          string(SUBSTRING "${record}" ${next_i} 1 next_ch)
          if(next_ch STREQUAL "${csv_quote}")
            math(EXPR i "${i} + 1")
          else()
            set(in_quotes FALSE)
          endif()
        else()
          set(in_quotes FALSE)
        endif()
      else()
        set(in_quotes TRUE)
      endif()
    elseif(ch STREQUAL "," AND NOT in_quotes)
      math(EXPR count "${count} + 1")
    endif()
    math(EXPR i "${i} + 1")
  endwhile()

  if(in_quotes)
    message(FATAL_ERROR "Unterminated quoted field in CSV record: ${record}")
  endif()

  set(${out_var} "${count}" PARENT_SCOPE)
endfunction()

function(csv_field_value record target_index out_var)
  string(LENGTH "${record}" record_len)
  set(field_index 1)
  set(value "")
  set(in_quotes FALSE)
  set(i 0)

  while(i LESS record_len)
    string(SUBSTRING "${record}" ${i} 1 ch)
    if(in_quotes)
      if(ch STREQUAL "${csv_quote}")
        math(EXPR next_i "${i} + 1")
        if(next_i LESS record_len)
          string(SUBSTRING "${record}" ${next_i} 1 next_ch)
          if(next_ch STREQUAL "${csv_quote}")
            set(value "${value}${csv_quote}")
            math(EXPR i "${i} + 1")
          else()
            set(in_quotes FALSE)
          endif()
        else()
          set(in_quotes FALSE)
        endif()
      else()
        set(value "${value}${ch}")
      endif()
    else()
      if(ch STREQUAL "${csv_quote}" AND value STREQUAL "")
        set(in_quotes TRUE)
      elseif(ch STREQUAL ",")
        if(field_index EQUAL target_index)
          set(${out_var} "${value}" PARENT_SCOPE)
          return()
        endif()
        math(EXPR field_index "${field_index} + 1")
        set(value "")
      else()
        set(value "${value}${ch}")
      endif()
    endif()
    math(EXPR i "${i} + 1")
  endwhile()

  if(in_quotes)
    message(FATAL_ERROR "Unterminated quoted field in CSV record: ${record}")
  endif()

  if(field_index EQUAL target_index)
    set(${out_var} "${value}" PARENT_SCOPE)
  else()
    set(${out_var} "" PARENT_SCOPE)
  endif()
endfunction()

function(csv_column_index_or_zero header column out_var)
  csv_field_count("${header}" field_count)
  foreach(column_index RANGE 1 ${field_count})
    csv_field_value("${header}" ${column_index} field_name)
    if(field_name STREQUAL "${column}")
      set(${out_var} "${column_index}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
  set(${out_var} 0 PARENT_SCOPE)
endfunction()

function(csv_column_index header column out_var)
  csv_column_index_or_zero("${header}" "${column}" column_index)
  if(column_index EQUAL 0)
    message(FATAL_ERROR "CSV header is missing required column '${column}': ${header}")
  endif()
  set(${out_var} "${column_index}" PARENT_SCOPE)
endfunction()

function(csv_value_by_column header record column out_var)
  csv_column_index("${header}" "${column}" column_index)
  csv_field_value("${record}" ${column_index} value)
  set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

function(require_csv_value header record column expected)
  csv_value_by_column("${header}" "${record}" "${column}" actual)
  if(NOT actual STREQUAL "${expected}")
    message(FATAL_ERROR
      "Expected CSV column '${column}' to be '${expected}', got '${actual}' in record: ${record}"
    )
  endif()
endfunction()

function(require_csv_index_value record field_index expected)
  csv_field_value("${record}" ${field_index} actual)
  if(NOT actual STREQUAL "${expected}")
    message(FATAL_ERROR
      "Expected CSV field ${field_index} to be '${expected}', got '${actual}' in record: ${record}"
    )
  endif()
endfunction()

function(require_csv_column header column)
  csv_column_index("${header}" "${column}" column_index)
endfunction()

function(require_no_csv_column header column)
  csv_column_index_or_zero("${header}" "${column}" column_index)
  if(NOT column_index EQUAL 0)
    message(FATAL_ERROR "CSV header must not contain column '${column}': ${header}")
  endif()
endfunction()

function(load_fixture path expected_kind expected_version out_header out_summary out_entry)
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "CSV parser fixture is missing: ${path}")
  endif()

  file(STRINGS "${path}" records)
  list(LENGTH records record_count)
  if(record_count LESS 3)
    message(FATAL_ERROR "CSV parser fixture must contain header, summary, and entry records: ${path}")
  endif()

  list(GET records 0 header)
  csv_field_count("${header}" expected_field_count)
  set(summary_record "")
  set(entry_record "")

  foreach(record IN LISTS records)
    csv_field_count("${record}" record_field_count)
    if(NOT record_field_count EQUAL expected_field_count)
      message(FATAL_ERROR
        "CSV parser fixture '${path}' has ${record_field_count} fields, expected ${expected_field_count}: ${record}"
      )
    endif()
  endforeach()

  foreach(record IN LISTS records)
    if(record STREQUAL "${header}")
      continue()
    endif()

    require_csv_value("${header}" "${record}" "format_version" "${expected_version}")
    require_csv_value("${header}" "${record}" "summary_kind" "${expected_kind}")

    csv_value_by_column("${header}" "${record}" "record_type" record_type)
    if(record_type STREQUAL "summary")
      set(summary_record "${record}")
    elseif(record_type STREQUAL "entry")
      set(entry_record "${record}")
    endif()
  endforeach()

  if(summary_record STREQUAL "")
    message(FATAL_ERROR "CSV parser fixture has no summary record: ${path}")
  endif()
  if(entry_record STREQUAL "")
    message(FATAL_ERROR "CSV parser fixture has no entry record: ${path}")
  endif()

  set(${out_header} "${header}" PARENT_SCOPE)
  set(${out_summary} "${summary_record}" PARENT_SCOPE)
  set(${out_entry} "${entry_record}" PARENT_SCOPE)
endfunction()

function(find_fixture_record path record_type out_header out_record)
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "CSV parser fixture is missing: ${path}")
  endif()

  file(STRINGS "${path}" records)
  list(GET records 0 header)
  set(found_record "")
  foreach(record IN LISTS records)
    if(record STREQUAL "${header}")
      continue()
    endif()
    csv_value_by_column("${header}" "${record}" "record_type" actual_record_type)
    if(actual_record_type STREQUAL "${record_type}")
      set(found_record "${record}")
      break()
    endif()
  endforeach()

  if(found_record STREQUAL "")
    message(FATAL_ERROR "CSV parser fixture '${path}' has no '${record_type}' record")
  endif()

  set(${out_header} "${header}" PARENT_SCOPE)
  set(${out_record} "${found_record}" PARENT_SCOPE)
endfunction()

set(csv_schema_doc "${REPO_ROOT}/docs/csv-schema.md")
require_text_contains("${csv_schema_doc}" "Issue #303 validates that fTimer needs this compact field dictionary plus tiny")
require_text_contains("${csv_schema_doc}" "It does not need generated golden CSV fixtures")
require_text_contains("${csv_schema_doc}" "missing sparse contributors are not zero-filled")
require_text_contains("${csv_schema_doc}" "Append validation is a schema-shape")
require_text_contains("${csv_schema_doc}" "`missing_lane_count_known=false`")
require_text_contains("${csv_schema_doc}" "`missing_rank_lane_sample_count_known=false`")

set(fixture_dir "${REPO_ROOT}/tests/fixtures/csv-schema")

load_fixture(
  "${fixture_dir}/local-active-reader-aid.csv"
  "local"
  "2"
  local_header
  local_summary
  local_entry
)
require_csv_value("${local_header}" "${local_summary}" "has_active_timers" "true")
require_csv_value("${local_header}" "${local_entry}" "is_active" "true")
require_csv_value("${local_header}" "${local_entry}" "name" "active_root")
require_csv_column("${local_header}" "pct_time")

set(strict_mpi_fixture "${fixture_dir}/strict-mpi-reader-aid.csv")
load_fixture(
  "${strict_mpi_fixture}"
  "mpi"
  "2"
  strict_mpi_header
  strict_mpi_summary
  strict_mpi_entry
)
find_fixture_record("${strict_mpi_fixture}" "metadata" strict_mpi_metadata_header strict_mpi_metadata)
require_csv_value("${strict_mpi_header}" "${strict_mpi_summary}" "num_ranks" "2")
require_csv_value("${strict_mpi_header}" "${strict_mpi_entry}" "name" "strict_root")
require_csv_value("${strict_mpi_header}" "${strict_mpi_entry}" "avg_pct_time" "4.00000000000000000E+0001")
require_csv_value("${strict_mpi_metadata_header}" "${strict_mpi_metadata}" "key" "case")
require_csv_value("${strict_mpi_metadata_header}" "${strict_mpi_metadata}" "value" "strict mpi")

load_fixture(
  "${fixture_dir}/mpi-union-sparse-reader-aid.csv"
  "mpi_union"
  "1"
  mpi_union_header
  mpi_union_summary
  mpi_union_entry
)
require_csv_value("${mpi_union_header}" "${mpi_union_summary}" "num_ranks" "2")
require_csv_value("${mpi_union_header}" "${mpi_union_entry}" "participating_rank_count" "1")
require_csv_value("${mpi_union_header}" "${mpi_union_entry}" "missing_rank_count" "1")
require_csv_column("${mpi_union_header}" "avg_participating_inclusive_time")
require_csv_column("${mpi_union_header}" "avg_participating_pct_time")
require_no_csv_column("${mpi_union_header}" "avg_all_rank_inclusive_time")
require_no_csv_column("${mpi_union_header}" "avg_amortized_inclusive_time")

load_fixture(
  "${fixture_dir}/openmp-mixed-epoch-reader-aid.csv"
  "openmp"
  "1"
  openmp_header
  openmp_summary
  openmp_entry
)
require_csv_value("${openmp_header}" "${openmp_summary}" "configured_lane_capacity" "4")
require_csv_value("${openmp_header}" "${openmp_summary}" "observed_participating_lane_count" "2")
require_csv_value("${openmp_header}" "${openmp_entry}" "eligible_lane_count" "4")
require_csv_value("${openmp_header}" "${openmp_entry}" "participating_lane_count" "2")
require_csv_value("${openmp_header}" "${openmp_entry}" "missing_lane_count" "2")
require_csv_value("${openmp_header}" "${openmp_entry}" "missing_lane_count_known" "false")
require_csv_column("${openmp_header}" "avg_lane_inclusive_time")
require_csv_index_value("${openmp_summary}" 24 "")
require_csv_index_value("${openmp_entry}" 11 "")
require_csv_index_value("${openmp_entry}" 24 "1.20000000000000000E+0000")

set(strict_hybrid_fixture "${fixture_dir}/mpi-openmp-strict-reader-aid.csv")
load_fixture(
  "${strict_hybrid_fixture}"
  "mpi_openmp"
  "1"
  strict_hybrid_header
  strict_hybrid_summary
  strict_hybrid_entry
)
find_fixture_record("${strict_hybrid_fixture}" "metadata" strict_hybrid_metadata_header strict_hybrid_metadata)
find_fixture_record("${strict_hybrid_fixture}" "rank" strict_hybrid_rank_header strict_hybrid_rank)
require_csv_value("${strict_hybrid_header}" "${strict_hybrid_summary}" "num_ranks" "2")
require_csv_value("${strict_hybrid_header}" "${strict_hybrid_entry}" "name" "strict_rank_lane")
require_csv_value("${strict_hybrid_header}" "${strict_hybrid_entry}" "missing_rank_lane_sample_count" "0")
require_csv_value("${strict_hybrid_header}" "${strict_hybrid_entry}" "missing_rank_lane_sample_count_known" "true")
require_csv_value("${strict_hybrid_metadata_header}" "${strict_hybrid_metadata}" "key" "case")
require_csv_value("${strict_hybrid_metadata_header}" "${strict_hybrid_metadata}" "value" "strict hybrid")
require_csv_value("${strict_hybrid_rank_header}" "${strict_hybrid_rank}" "rank" "1")
require_csv_value("${strict_hybrid_rank_header}" "${strict_hybrid_rank}" "configured_lane_capacity" "4")
require_csv_value("${strict_hybrid_rank_header}" "${strict_hybrid_rank}" "observed_participating_lane_count" "2")

load_fixture(
  "${fixture_dir}/mpi-openmp-union-mixed-epoch-reader-aid.csv"
  "mpi_openmp_union"
  "1"
  hybrid_union_header
  hybrid_union_summary
  hybrid_union_entry
)
require_csv_value("${hybrid_union_header}" "${hybrid_union_summary}" "participation_policy" "sparse_union")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "participation_policy" "sparse_union")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "participating_rank_count" "1")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "missing_rank_count" "1")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "eligible_rank_lane_sample_count" "4")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "participating_rank_lane_sample_count" "2")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "missing_rank_lane_sample_count" "0")
require_csv_value("${hybrid_union_header}" "${hybrid_union_entry}" "missing_rank_lane_sample_count_known" "false")
require_csv_column("${hybrid_union_header}" "avg_participating_lane_inclusive_time")
require_csv_column("${hybrid_union_header}" "avg_participating_lane_pct_time")
require_no_csv_column("${hybrid_union_header}" "avg_all_rank_lane_inclusive_time")
require_no_csv_column("${hybrid_union_header}" "avg_amortized_lane_inclusive_time")
