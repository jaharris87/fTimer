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

function(ftimer_expect_configure_success label compiler)
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

  if(NOT configure_result EQUAL 0)
    message(FATAL_ERROR
      "Expected '${label}' configure to succeed, but it failed.\n${configure_output}"
    )
  endif()
endfunction()

function(ftimer_try_configure_success out_var label compiler)
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

  if(configure_result EQUAL 0)
    set(${out_var} TRUE PARENT_SCOPE)
  else()
    set(${out_var} FALSE PARENT_SCOPE)
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

file(READ "${REPO_ROOT}/src/ftimer_mpi.F90" ftimer_mpi_source)
if(ftimer_mpi_source MATCHES "MPI_(2DOUBLE_PRECISION|DOUBLE_PRECISION|INTEGER8)")
  message(FATAL_ERROR
    "MPI summary reductions must not hard-code MPI_DOUBLE_PRECISION, MPI_2DOUBLE_PRECISION, or MPI_INTEGER8; select datatypes from real(wp) and integer(int64) instead."
  )
endif()

file(READ "${REPO_ROOT}/CMakeLists.txt" ftimer_root_cmake)
if(NOT ftimer_root_cmake MATCHES "use mpi_f08")
  message(FATAL_ERROR
    "FTIMER_USE_MPI=ON configure coverage must compile-check mpi_f08 so the documented MPI interface contract stays explicit."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "MPI_Type_match_size")
  message(FATAL_ERROR
    "FTIMER_USE_MPI=ON configure coverage must compile-check MPI_Type_match_size so MPI reduction datatype validation stays explicit."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "MPI_ERRORS_RETURN")
  message(FATAL_ERROR
    "FTIMER_USE_MPI=ON configure coverage must compile-check MPI_ERRORS_RETURN around datatype validation so unsupported datatype paths can report errors."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "MPI_Errhandler_free")
  message(FATAL_ERROR
    "FTIMER_USE_MPI=ON configure coverage must compile-check releasing saved MPI error handlers after datatype validation."
  )
endif()

find_program(ftimer_mpifort_compiler NAMES mpifort mpif90 mpif77)
find_program(ftimer_gfortran_compiler NAMES gfortran)
find_program(ftimer_plain_nonmpi_compiler NAMES flang-new-19 flang-19 flang-new-18 flang-18 flang-new flang)
find_program(ftimer_flang_compiler NAMES flang-19 flang-new-19 flang-new flang)
find_program(ftimer_unvalidated_openmp_compiler NAMES nvfortran ifx ifort nagfor lfortran)

if(ftimer_plain_nonmpi_compiler AND ftimer_mpifort_compiler)
  ftimer_expect_configure_failure(
    mpi_requires_wrapper_compiler
    "${ftimer_plain_nonmpi_compiler}"
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

if(NOT ftimer_root_cmake MATCHES "FTIMER_VALIDATED_OPENMP_COMPILER_IDS[^\n]*GNU[^\n]*LLVMFlang")
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must keep the validated compiler-ID policy explicit for GNU and LLVMFlang."
  )
endif()
string(FIND
  "${ftimer_root_cmake}"
  "if(NOT CMAKE_Fortran_COMPILER_ID IN_LIST FTIMER_VALIDATED_OPENMP_COMPILER_IDS)"
  ftimer_openmp_compiler_gate_pos
)
string(FIND
  "${ftimer_root_cmake}"
  "find_package(OpenMP COMPONENTS Fortran)"
  ftimer_openmp_find_package_pos
)
if(ftimer_openmp_compiler_gate_pos EQUAL -1)
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must enforce the validated compiler-ID gate."
  )
endif()
if(ftimer_openmp_find_package_pos EQUAL -1)
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must still discover OpenMP::OpenMP_Fortran."
  )
endif()
if(ftimer_openmp_compiler_gate_pos GREATER ftimer_openmp_find_package_pos)
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON must reject unvalidated compiler IDs before OpenMP runtime discovery."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "ftimer_try_run_openmp_master_probe")
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must run fTimer's OpenMP master-thread capability probe."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "use omp_lib")
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must probe omp_lib availability."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "!\\$omp parallel")
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must probe an OpenMP parallel region."
  )
endif()
if(NOT ftimer_root_cmake MATCHES "!\\$omp master")
  message(FATAL_ERROR
    "FTIMER_USE_OPENMP=ON configure coverage must probe OpenMP master semantics."
  )
endif()

if(ftimer_gfortran_compiler)
  ftimer_expect_configure_success(
    openmp_allows_validated_gnu
    "${ftimer_gfortran_compiler}"
    -DFTIMER_USE_OPENMP=ON
  )
else()
  message(STATUS
    "Skipping GNU OpenMP configure success regression: gfortran is not available on PATH."
  )
endif()

if(ftimer_flang_compiler)
  set(ftimer_flang_openmp_args -DFTIMER_USE_OPENMP=ON)
  if(EXISTS "/opt/homebrew/opt/libomp")
    list(APPEND ftimer_flang_openmp_args -DOpenMP_ROOT=/opt/homebrew/opt/libomp)
  elseif(EXISTS "/usr/local/opt/libomp")
    list(APPEND ftimer_flang_openmp_args -DOpenMP_ROOT=/usr/local/opt/libomp)
  elseif(EXISTS "/usr/lib/llvm-19")
    list(APPEND ftimer_flang_openmp_args -DOpenMP_ROOT=/usr/lib/llvm-19)
  endif()

  ftimer_try_configure_success(
    flang_openmp_configure_ok
    openmp_allows_validated_flang
    "${ftimer_flang_compiler}"
    ${ftimer_flang_openmp_args}
  )

  if(NOT flang_openmp_configure_ok AND FTIMER_REQUIRE_FLANG_OPENMP_CONTRACT)
    message(FATAL_ERROR
      "Required LLVM Flang OpenMP configure success regression failed. Ensure the CI contract job installs libomp and passes a usable OpenMP_ROOT when needed."
    )
  elseif(NOT flang_openmp_configure_ok)
    message(STATUS
      "Skipping LLVM Flang OpenMP configure success regression: Flang is present, but CMake could not configure fTimer with the locally discoverable OpenMP runtime."
    )
  endif()
else()
  message(STATUS
    "Skipping LLVM Flang OpenMP configure success regression: flang-19/flang-new/flang is not available on PATH."
  )
endif()

if(ftimer_unvalidated_openmp_compiler)
  ftimer_expect_configure_failure(
    openmp_rejects_unvalidated_compiler
    "${ftimer_unvalidated_openmp_compiler}"
    "not currently validated for compiler ID"
    -DFTIMER_USE_OPENMP=ON
  )
else()
  message(STATUS
    "Skipping unvalidated OpenMP compiler rejection regression: no nvfortran/ifx/ifort/nagfor/lfortran compiler found on PATH."
  )
endif()
