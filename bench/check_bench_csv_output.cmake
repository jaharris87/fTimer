if(NOT DEFINED FTIMER_BENCH_EXE)
  message(FATAL_ERROR "FTIMER_BENCH_EXE is required")
endif()

if(NOT DEFINED FTIMER_BENCH_CSV)
  message(FATAL_ERROR "FTIMER_BENCH_CSV is required")
endif()

if(NOT DEFINED FTIMER_BENCH_MPI_NPROCS OR FTIMER_BENCH_MPI_NPROCS STREQUAL "")
  set(FTIMER_BENCH_MPI_NPROCS 2)
endif()

set(ftimer_bench_smoke_only OFF)
if(FTIMER_BENCH_SMOKE_ONLY)
  set(ftimer_bench_smoke_only ON)
endif()
set(ftimer_bench_smoke_env_value 0)
if(ftimer_bench_smoke_only)
  set(ftimer_bench_smoke_env_value 1)
endif()

set(ftimer_bench_command "${FTIMER_BENCH_EXE}")
if(FTIMER_BENCH_USE_MPI)
  if(DEFINED FTIMER_BENCH_MPIEXEC_EXECUTABLE AND NOT FTIMER_BENCH_MPIEXEC_EXECUTABLE STREQUAL "")
    set(ftimer_bench_mpiexec "${FTIMER_BENCH_MPIEXEC_EXECUTABLE}")
  else()
    find_program(ftimer_bench_mpiexec NAMES mpiexec mpirun)
  endif()
  if(NOT ftimer_bench_mpiexec)
    message(FATAL_ERROR "FTIMER_BENCH_USE_MPI=ON requires mpiexec/mpirun for bench CSV smoke")
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

file(REMOVE "${FTIMER_BENCH_CSV}")

execute_process(
  COMMAND ${CMAKE_COMMAND} -E env
    "FTIMER_BENCH_CSV_SMOKE_ONLY=${ftimer_bench_smoke_env_value}"
    ${ftimer_bench_command} "${FTIMER_BENCH_CSV}"
  RESULT_VARIABLE bench_result
  OUTPUT_VARIABLE bench_stdout
  ERROR_VARIABLE bench_stderr
)

if(NOT bench_result EQUAL 0)
  message(FATAL_ERROR
    "ftimer_bench CSV run failed with ${bench_result}\n"
    "stdout:\n${bench_stdout}\n"
    "stderr:\n${bench_stderr}"
  )
endif()

if(NOT EXISTS "${FTIMER_BENCH_CSV}")
  message(FATAL_ERROR "ftimer_bench did not create ${FTIMER_BENCH_CSV}")
endif()

file(READ "${FTIMER_BENCH_CSV}" bench_csv)

if(NOT bench_csv MATCHES "^benchmark,reps,total_ms,per_op_ns")
  message(FATAL_ERROR "ftimer_bench CSV output is missing the expected header")
endif()

if(NOT ftimer_bench_smoke_only)
  set(required_rows
    "\"format local text N=100 entries\""
    "\"write local CSV N=100 entries\""
    "\"format local text N=100 long L=256\""
    "\"format local text metadata M=200\""
    "\"write local CSV metadata M=200\""
    "\"format sparse union text N=100\""
  )

  foreach(required_row IN LISTS required_rows)
    if(NOT bench_csv MATCHES "${required_row}")
      message(FATAL_ERROR "ftimer_bench CSV output is missing ${required_row}")
    endif()
  endforeach()

  if(FTIMER_BENCH_EXPECT_OPENMP_ROW)
    if(NOT bench_csv MATCHES "\"ftimer_openmp summary merge N=100 entries\"")
      message(FATAL_ERROR "ftimer_bench CSV output is missing the OpenMP summary merge row")
    endif()
  endif()

  if(FTIMER_BENCH_EXPECT_MPI_STRICT_ROW)
    if(NOT bench_csv MATCHES "\"write strict MPI CSV N=100 entries\"")
      message(FATAL_ERROR "ftimer_bench CSV output is missing the strict MPI CSV row")
    endif()
  endif()
endif()

if(FTIMER_BENCH_EXPECT_MPI_OPENMP_ROWS)
  if(NOT bench_csv MATCHES "\"write strict MPI\\+OpenMP CSV N=1 entries\"")
    message(FATAL_ERROR "ftimer_bench CSV output is missing the strict MPI+OpenMP CSV row")
  endif()
  if(NOT bench_csv MATCHES "\"write sparse MPI\\+OpenMP union CSV N=2 entries\"")
    message(FATAL_ERROR "ftimer_bench CSV output is missing the sparse MPI+OpenMP union CSV row")
  endif()
endif()
