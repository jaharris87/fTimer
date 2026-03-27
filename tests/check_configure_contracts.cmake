cmake_minimum_required(VERSION 3.16)

function(ftimer_append_common_configure_args out_var)
  set(args
    -S "${REPO_ROOT}"
    -DFTIMER_BUILD_SMOKE_TESTS=OFF
    -DFTIMER_BUILD_TESTS=OFF
    -DFTIMER_BUILD_EXAMPLES=OFF
    -DFTIMER_BUILD_BENCH=OFF
  )

  if(DEFINED CMAKE_GENERATOR AND NOT CMAKE_GENERATOR STREQUAL "")
    list(APPEND args -G "${CMAKE_GENERATOR}")
  endif()

  if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
    list(APPEND args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
  endif()

  set(${out_var} "${args}" PARENT_SCOPE)
endfunction()

function(ftimer_expect_configure_failure label compiler required_text)
  set(extra_args ${ARGN})
  set(build_dir "${TEST_BINARY_DIR}/${label}")

  file(REMOVE_RECURSE "${build_dir}")

  ftimer_append_common_configure_args(configure_args)
  list(APPEND configure_args
    -B "${build_dir}"
    -DCMAKE_Fortran_COMPILER=${compiler}
  )
  list(APPEND configure_args ${extra_args})

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${configure_args}
    RESULT_VARIABLE configure_result
    OUTPUT_VARIABLE configure_stdout
    ERROR_VARIABLE configure_stderr
  )

  string(CONCAT configure_output "${configure_stdout}" "\n" "${configure_stderr}")

  if(configure_result EQUAL 0)
    message(FATAL_ERROR
      "Expected '${label}' configure to fail, but it succeeded.\n${configure_output}"
    )
  endif()

  if(NOT configure_output MATCHES "${required_text}")
    message(FATAL_ERROR
      "Expected '${label}' failure output to match '${required_text}', but it did not.\n${configure_output}"
    )
  endif()
endfunction()

function(ftimer_try_configure_failure out_var label compiler required_text)
  set(extra_args ${ARGN})
  set(build_dir "${TEST_BINARY_DIR}/${label}")

  file(REMOVE_RECURSE "${build_dir}")

  ftimer_append_common_configure_args(configure_args)
  list(APPEND configure_args
    -B "${build_dir}"
    -DCMAKE_Fortran_COMPILER=${compiler}
  )
  list(APPEND configure_args ${extra_args})

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${configure_args}
    RESULT_VARIABLE configure_result
    OUTPUT_VARIABLE configure_stdout
    ERROR_VARIABLE configure_stderr
  )

  string(CONCAT configure_output "${configure_stdout}" "\n" "${configure_stderr}")

  if((NOT configure_result EQUAL 0) AND configure_output MATCHES "${required_text}")
    set(${out_var} TRUE PARENT_SCOPE)
    return()
  endif()

  set(${out_var} FALSE PARENT_SCOPE)
endfunction()

file(REMOVE_RECURSE "${TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")

find_program(ftimer_mpifort_compiler NAMES mpifort mpif90 mpif77)
find_program(ftimer_gfortran_compiler NAMES gfortran)
find_program(ftimer_unsupported_compiler NAMES flang-new-19 flang-19 flang-new-18 flang-18 flang-new flang)

if(ftimer_unsupported_compiler AND ftimer_mpifort_compiler)
  ftimer_expect_configure_failure(
    mpi_requires_wrapper_compiler
    "${ftimer_unsupported_compiler}"
    "failed a configure-time MPI probe"
    -DFTIMER_USE_MPI=ON
  )
elseif(ftimer_gfortran_compiler AND ftimer_mpifort_compiler)
  ftimer_try_configure_failure(
    mpi_gate_failed
    mpi_requires_wrapper_compiler
    "${ftimer_gfortran_compiler}"
    "failed a configure-time MPI probe"
    -DFTIMER_USE_MPI=ON
  )

  if(NOT mpi_gate_failed)
    message(STATUS
      "Skipping MPI configure gate regression: no known unsupported plain compiler found, and gfortran succeeded the MPI probe on this platform."
    )
  endif()
else()
  message(STATUS
    "Skipping MPI configure gate regression: requires an MPI wrapper compiler plus a usable plain-compiler probe candidate on PATH."
  )
endif()

if(ftimer_unsupported_compiler)
  ftimer_expect_configure_failure(
    openmp_requires_gnu
    "${ftimer_unsupported_compiler}"
    "FTIMER_USE_OPENMP=ON is currently supported only with GNU Fortran"
    -DFTIMER_USE_OPENMP=ON
  )
else()
  message(STATUS
    "Skipping OpenMP configure gate regression: no unsupported non-GNU Fortran compiler found on PATH."
  )
endif()
