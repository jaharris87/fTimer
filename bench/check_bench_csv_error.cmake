if(NOT DEFINED FTIMER_BENCH_EXE)
  message(FATAL_ERROR "FTIMER_BENCH_EXE is required")
endif()

if(NOT DEFINED FTIMER_BENCH_CSV)
  message(FATAL_ERROR "FTIMER_BENCH_CSV is required")
endif()

if(NOT DEFINED FTIMER_BENCH_MPI_NPROCS OR FTIMER_BENCH_MPI_NPROCS STREQUAL "")
  set(FTIMER_BENCH_MPI_NPROCS 1)
endif()

set(ftimer_bench_command "${FTIMER_BENCH_EXE}")
if(FTIMER_BENCH_USE_MPI)
  if(DEFINED FTIMER_BENCH_MPIEXEC_EXECUTABLE AND NOT FTIMER_BENCH_MPIEXEC_EXECUTABLE STREQUAL "")
    set(ftimer_bench_mpiexec "${FTIMER_BENCH_MPIEXEC_EXECUTABLE}")
  else()
    find_program(ftimer_bench_mpiexec NAMES mpiexec mpirun)
  endif()
  if(NOT ftimer_bench_mpiexec)
    message(FATAL_ERROR "FTIMER_BENCH_USE_MPI=ON requires mpiexec/mpirun for bench CSV error smoke")
  endif()

  set(ftimer_bench_command "${ftimer_bench_mpiexec}")
  if(DEFINED FTIMER_BENCH_MPIEXEC_NUMPROC_FLAG AND
      NOT FTIMER_BENCH_MPIEXEC_NUMPROC_FLAG STREQUAL "")
    list(APPEND ftimer_bench_command
      "${FTIMER_BENCH_MPIEXEC_NUMPROC_FLAG}" "${FTIMER_BENCH_MPI_NPROCS}")
  else()
    list(APPEND ftimer_bench_command -n "${FTIMER_BENCH_MPI_NPROCS}")
  endif()
  if(DEFINED FTIMER_BENCH_MPIEXEC_PREFLAGS AND
      NOT FTIMER_BENCH_MPIEXEC_PREFLAGS STREQUAL "")
    list(APPEND ftimer_bench_command ${FTIMER_BENCH_MPIEXEC_PREFLAGS})
  endif()
  if(DEFINED FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_COUNT AND
      FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_COUNT GREATER 0)
    foreach(ftimer_bench_flag_index RANGE 1 ${FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_COUNT})
      if(DEFINED FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_${ftimer_bench_flag_index} AND
          NOT FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_${ftimer_bench_flag_index} STREQUAL "")
        list(APPEND ftimer_bench_command
          "${FTIMER_BENCH_MPIEXEC_OVERSUBSCRIBE_FLAG_${ftimer_bench_flag_index}}")
      endif()
    endforeach()
  endif()
  list(APPEND ftimer_bench_command "${FTIMER_BENCH_EXE}")
  if(DEFINED FTIMER_BENCH_MPIEXEC_POSTFLAGS AND
      NOT FTIMER_BENCH_MPIEXEC_POSTFLAGS STREQUAL "")
    list(APPEND ftimer_bench_command ${FTIMER_BENCH_MPIEXEC_POSTFLAGS})
  endif()
endif()

execute_process(
  COMMAND ${ftimer_bench_command} "${FTIMER_BENCH_CSV}"
  RESULT_VARIABLE bench_result
  OUTPUT_VARIABLE bench_stdout
  ERROR_VARIABLE bench_stderr
)

if(bench_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_bench unexpectedly succeeded for unwritable CSV path\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()

if(NOT bench_stderr MATCHES "unable to write CSV result file")
  message(FATAL_ERROR
    "ftimer_bench CSV error did not explain the write failure\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()
