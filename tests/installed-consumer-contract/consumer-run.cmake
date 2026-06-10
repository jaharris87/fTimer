# Execute installed-package consumers and verify generated reports, CSV, and diagnostics.

include("${CMAKE_CURRENT_LIST_DIR}/mpi-openmp-diagnostics.cmake")

# Plain consumers do not call MPI_Init; MPI-enabled installed checks use the
# MPI-aware consumers below.
if(NOT TEST_ENABLE_MPI)
  execute_process(
    COMMAND "${consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE consumer_run_result
  )
  if(NOT consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package consumer executable exited with a nonzero status.")
  endif()

  execute_process(
    COMMAND "${oop_consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE oop_consumer_run_result
  )
  if(NOT oop_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package OOP consumer executable exited with a nonzero status.")
  endif()

  execute_process(
    COMMAND "${mixed_consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE mixed_consumer_run_result
  )
  if(NOT mixed_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package mixed-module consumer executable exited with a nonzero status.")
  endif()

  execute_process(
    COMMAND "${openmp_api_consumer_executable}"
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE openmp_api_consumer_run_result
  )
  if(NOT openmp_api_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package OpenMP API consumer executable exited with a nonzero status.")
  endif()

  if(TEST_ENABLE_OPENMP)
    execute_process(
      COMMAND "${openmp_api_openmp_consumer_executable}"
      WORKING_DIRECTORY "${consumer_build_dir}"
      RESULT_VARIABLE openmp_api_openmp_consumer_run_result
    )
    if(NOT openmp_api_openmp_consumer_run_result EQUAL 0)
      message(FATAL_ERROR
        "Installed-package OpenMP API OpenMP consumer executable exited with a nonzero status."
      )
    endif()
  endif()
endif()

if(TEST_ENABLE_MPI)
  set(mpi_consumer_executable "${consumer_build_dir}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}")
  set(openmp_api_mpi_consumer_executable
    "${consumer_build_dir}/ftimer_installed_openmp_api_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
    set(configured_mpi_consumer_executable
      "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    set(configured_openmp_api_mpi_consumer_executable
      "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_openmp_api_mpi_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    if(EXISTS "${configured_mpi_consumer_executable}")
      set(mpi_consumer_executable "${configured_mpi_consumer_executable}")
    endif()
    if(EXISTS "${configured_openmp_api_mpi_consumer_executable}")
      set(openmp_api_mpi_consumer_executable "${configured_openmp_api_mpi_consumer_executable}")
    endif()
  endif()

  if(DEFINED TEST_MPIEXEC_EXECUTABLE AND NOT TEST_MPIEXEC_EXECUTABLE STREQUAL "")
    set(ftimer_mpiexec "${TEST_MPIEXEC_EXECUTABLE}")
  else()
    find_program(ftimer_mpiexec NAMES mpiexec mpirun)
  endif()
  if(NOT ftimer_mpiexec)
    if(TEST_ENABLE_OPENMP)
      message(FATAL_ERROR
        "${test_name} requires mpiexec/mpirun so the MPI+OpenMP installed consumer is executed."
      )
    else()
      message(STATUS "Skipping ${test_name} MPI run: no mpiexec/mpirun found on PATH.")
      set(ftimer_installed_consumer_contract_stop TRUE)
      return()
    endif()
  endif()

  set(ftimer_mpi_launch_prefix "${ftimer_mpiexec}")
  if(DEFINED TEST_MPIEXEC_NUMPROC_FLAG AND NOT TEST_MPIEXEC_NUMPROC_FLAG STREQUAL "")
    list(APPEND ftimer_mpi_launch_prefix "${TEST_MPIEXEC_NUMPROC_FLAG}" 2)
  else()
    list(APPEND ftimer_mpi_launch_prefix -n 2)
  endif()
  if(DEFINED TEST_MPIEXEC_PREFLAGS AND NOT TEST_MPIEXEC_PREFLAGS STREQUAL "")
    list(APPEND ftimer_mpi_launch_prefix ${TEST_MPIEXEC_PREFLAGS})
  endif()
  execute_process(
    COMMAND "${ftimer_mpiexec}" --version
    OUTPUT_VARIABLE ftimer_mpiexec_version_stdout
    ERROR_VARIABLE ftimer_mpiexec_version_stderr
    RESULT_VARIABLE ftimer_mpiexec_version_result
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE
  )
  if(ftimer_mpiexec_version_result EQUAL 0)
    set(ftimer_mpiexec_version_text
      "${ftimer_mpiexec_version_stdout}\n${ftimer_mpiexec_version_stderr}")
    if(ftimer_mpiexec_version_text MATCHES "Open MPI|OpenRTE|PRTE|PRRTE")
      list(APPEND ftimer_mpi_launch_prefix --map-by slot:OVERSUBSCRIBE)
    endif()
  endif()

  set(ftimer_mpi_launch_command "${ftimer_mpi_launch_prefix}")
  list(APPEND ftimer_mpi_launch_command "${mpi_consumer_executable}")
  if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_mpi_launch_command ${TEST_MPIEXEC_POSTFLAGS})
  endif()

  execute_process(
    COMMAND ${ftimer_mpi_launch_command}
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE mpi_consumer_run_result
  )
  if(NOT mpi_consumer_run_result EQUAL 0)
    message(FATAL_ERROR "Installed-package MPI consumer executable exited with a nonzero status.")
  endif()

  set(ftimer_openmp_api_mpi_launch_command "${ftimer_mpi_launch_prefix}")
  list(APPEND ftimer_openmp_api_mpi_launch_command "${openmp_api_mpi_consumer_executable}")
  if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_openmp_api_mpi_launch_command ${TEST_MPIEXEC_POSTFLAGS})
  endif()

  execute_process(
    COMMAND ${ftimer_openmp_api_mpi_launch_command}
    WORKING_DIRECTORY "${consumer_build_dir}"
    RESULT_VARIABLE openmp_api_mpi_consumer_run_result
  )
  if(NOT openmp_api_mpi_consumer_run_result EQUAL 0)
    message(FATAL_ERROR
      "Installed-package OpenMP API MPI consumer executable exited with a nonzero status."
    )
  endif()

  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_summary.txt")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_summary.txt.")
  endif()
  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_union_summary.txt")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_union_summary.txt.")
  endif()
  if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_union_summary.csv")
    message(FATAL_ERROR "Installed-package MPI consumer did not write consumer_mpi_union_summary.csv.")
  endif()
  file(READ "${consumer_build_dir}/consumer_mpi_union_summary.csv" ftimer_consumer_union_csv_text)
  if(NOT ftimer_consumer_union_csv_text MATCHES "mpi_union")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the mpi_union summary kind.")
  endif()
  if(NOT ftimer_consumer_union_csv_text MATCHES "participating_rank_count")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the sparse participation schema.")
  endif()
  if(NOT ftimer_consumer_union_csv_text MATCHES "consumer_mpi_work")
    message(FATAL_ERROR "Installed-package MPI union CSV does not contain the expected consumer_mpi_work entry.")
  endif()

  if(TEST_ENABLE_OPENMP)
    set(mpi_openmp_consumer_executable
      "${consumer_build_dir}/ftimer_installed_mpi_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    set(openmp_api_mpi_openmp_consumer_executable
      "${consumer_build_dir}/ftimer_installed_openmp_api_mpi_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
    )
    if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
      set(configured_mpi_openmp_consumer_executable
        "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mpi_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
      )
      set(configured_openmp_api_mpi_openmp_consumer_executable
        "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_openmp_api_mpi_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
      )
      if(EXISTS "${configured_mpi_openmp_consumer_executable}")
        set(mpi_openmp_consumer_executable "${configured_mpi_openmp_consumer_executable}")
      endif()
      if(EXISTS "${configured_openmp_api_mpi_openmp_consumer_executable}")
        set(openmp_api_mpi_openmp_consumer_executable
          "${configured_openmp_api_mpi_openmp_consumer_executable}"
        )
      endif()
    endif()

    set(ftimer_mpi_openmp_launch_command "${ftimer_mpi_launch_prefix}")
    list(APPEND ftimer_mpi_openmp_launch_command "${mpi_openmp_consumer_executable}")
    if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
      list(APPEND ftimer_mpi_openmp_launch_command ${TEST_MPIEXEC_POSTFLAGS})
    endif()

    execute_process(
      COMMAND ${ftimer_mpi_openmp_launch_command}
      WORKING_DIRECTORY "${consumer_build_dir}"
      TIMEOUT ${TEST_EXECUTE_TIMEOUT_SECONDS}
      RESULT_VARIABLE mpi_openmp_consumer_run_result
    )
    if(NOT mpi_openmp_consumer_run_result EQUAL 0)
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP consumer executable exited with a nonzero status."
      )
    endif()

    set(ftimer_openmp_api_mpi_openmp_launch_command "${ftimer_mpi_launch_prefix}")
    list(APPEND ftimer_openmp_api_mpi_openmp_launch_command
      "${openmp_api_mpi_openmp_consumer_executable}"
    )
    if(DEFINED TEST_MPIEXEC_POSTFLAGS AND NOT TEST_MPIEXEC_POSTFLAGS STREQUAL "")
      list(APPEND ftimer_openmp_api_mpi_openmp_launch_command ${TEST_MPIEXEC_POSTFLAGS})
    endif()

    execute_process(
      COMMAND ${ftimer_openmp_api_mpi_openmp_launch_command}
      WORKING_DIRECTORY "${consumer_build_dir}"
      TIMEOUT ${TEST_EXECUTE_TIMEOUT_SECONDS}
      RESULT_VARIABLE openmp_api_mpi_openmp_consumer_run_result
      ERROR_VARIABLE openmp_api_mpi_openmp_consumer_stderr
    )
    if(NOT openmp_api_mpi_openmp_consumer_run_result EQUAL 0)
      message(FATAL_ERROR
        "Installed-package OpenMP API MPI+OpenMP consumer executable exited with a nonzero status.\n"
        "stderr:\n${openmp_api_mpi_openmp_consumer_stderr}"
      )
    endif()

    if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_openmp_summary.txt")
      message(FATAL_ERROR
        "Installed-package OpenMP API MPI+OpenMP consumer did not write consumer_mpi_openmp_summary.txt."
      )
    endif()
    if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_openmp_summary.csv")
      message(FATAL_ERROR
        "Installed-package OpenMP API MPI+OpenMP consumer did not write consumer_mpi_openmp_summary.csv."
      )
    endif()
    if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_openmp_union_summary.txt")
      message(FATAL_ERROR
        "Installed-package OpenMP API MPI+OpenMP consumer did not write consumer_mpi_openmp_union_summary.txt."
      )
    endif()
    if(NOT EXISTS "${consumer_build_dir}/consumer_mpi_openmp_union_summary.csv")
      message(FATAL_ERROR
        "Installed-package OpenMP API MPI+OpenMP consumer did not write consumer_mpi_openmp_union_summary.csv."
      )
    endif()
    file(READ "${consumer_build_dir}/consumer_mpi_openmp_summary.txt"
      ftimer_consumer_mpi_openmp_report_text)
    if(NOT ftimer_consumer_mpi_openmp_report_text MATCHES "MPI\\+OpenMP summary")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict report does not contain the strict hybrid heading."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_report_text MATCHES "Rank/lane samples")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict report does not contain rank/lane sample output."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_report_text MATCHES
        "consumer_hybrid_api[^\n]*openmp_level1_team[^\n]*2[^\n]*4[^\n]*0")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict report does not contain the expected consumer_hybrid_api row."
      )
    endif()
    file(READ "${consumer_build_dir}/consumer_mpi_openmp_summary.csv"
      ftimer_consumer_mpi_openmp_csv_text)
    if(NOT ftimer_consumer_mpi_openmp_csv_text MATCHES "mpi_openmp")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict CSV does not contain the mpi_openmp summary kind."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_csv_text MATCHES "consumer_hybrid_api")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict CSV does not contain the expected consumer_hybrid_api entry."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_csv_text MATCHES
        "\"consumer_hybrid_api\",\"openmp_level1_team\",\"2\",\"0\",\"4\",\"4\",\"0\",\"true\"")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP strict CSV does not contain the expected strict participation values."
      )
    endif()
    file(READ "${consumer_build_dir}/consumer_mpi_openmp_union_summary.txt"
      ftimer_consumer_mpi_openmp_union_report_text)
    if(NOT ftimer_consumer_mpi_openmp_union_report_text MATCHES
        "Sparse MPI\\+OpenMP union summary")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union report does not contain the sparse union heading."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_report_text MATCHES "Missing ranks")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union report does not contain missing-rank output."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_report_text MATCHES
        "consumer_sparse_hybrid_api[^\n]*openmp_level1_team[^\n]*1[^\n]*1[^\n]*1[^\n]*1")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union report does not contain the expected sparse hybrid row."
      )
    endif()
    file(READ "${consumer_build_dir}/consumer_mpi_openmp_union_summary.csv"
      ftimer_consumer_mpi_openmp_union_csv_text)
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES "mpi_openmp_union")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not contain the mpi_openmp_union summary kind."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES "consumer_sparse_hybrid_api")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not contain the expected sparse hybrid entry."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES "missing_rank_count")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not contain the sparse participation schema."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES
        "\"consumer_hybrid_api\",\"openmp_level1_team\",\"2\",\"0\",\"4\",\"4\",\"0\",\"true\"")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not contain the expected all-lane participation values."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES
        "\"consumer_sparse_hybrid_api\",\"openmp_level1_team\",\"1\",\"1\",\"2\",\"1\",\"1\",\"true\"")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not contain the expected sparse participation values."
      )
    endif()
    if(NOT ftimer_consumer_mpi_openmp_union_csv_text MATCHES "sparse_union")
      message(FATAL_ERROR
        "Installed-package MPI+OpenMP union CSV does not identify the sparse_union participation policy."
      )
    endif()

    ftimer_assert_openmp_api_mpi_openmp_stderr("${openmp_api_mpi_openmp_consumer_stderr}")
  endif()
endif()

ftimer_record_installed_consumer_contract_phase(consumer-run)
