cmake_minimum_required(VERSION 3.16)

function(ftimer_copy_tracked_repo repo_root destination)
  find_program(ftimer_git_executable NAMES git)
  if(NOT ftimer_git_executable)
    message(STATUS
      "Skipping Makefile wrapper regression: git is not available to materialize an isolated worktree copy."
    )
    set(FTIMER_MAKE_WRAPPER_SKIP TRUE PARENT_SCOPE)
    return()
  endif()

  if(NOT EXISTS "${repo_root}/.git")
    message(STATUS
      "Skipping Makefile wrapper regression: repository metadata is unavailable outside a Git checkout."
    )
    set(FTIMER_MAKE_WRAPPER_SKIP TRUE PARENT_SCOPE)
    return()
  endif()

  execute_process(
    COMMAND "${ftimer_git_executable}" -C "${repo_root}" ls-files
    RESULT_VARIABLE ls_files_result
    OUTPUT_VARIABLE tracked_files_output
    ERROR_VARIABLE ls_files_error
  )
  if(NOT ls_files_result EQUAL 0)
    message(STATUS
      "Skipping Makefile wrapper regression: could not enumerate tracked files.\n${ls_files_error}"
    )
    set(FTIMER_MAKE_WRAPPER_SKIP TRUE PARENT_SCOPE)
    return()
  endif()

  string(REPLACE "\n" ";" tracked_files "${tracked_files_output}")

  foreach(tracked_file IN LISTS tracked_files)
    if(tracked_file STREQUAL "")
      continue()
    endif()

    get_filename_component(parent_dir "${tracked_file}" DIRECTORY)
    if(parent_dir)
      file(MAKE_DIRECTORY "${destination}/${parent_dir}")
    endif()

    file(COPY "${repo_root}/${tracked_file}" DESTINATION "${destination}/${parent_dir}")
  endforeach()
endfunction()

function(ftimer_extract_cache_value cache_path cache_key out_var)
  file(STRINGS "${cache_path}" cache_line REGEX "^${cache_key}:")
  if(NOT cache_line)
    message(FATAL_ERROR "Missing '${cache_key}' in '${cache_path}'.")
  endif()

  string(REGEX REPLACE "^[^=]*=" "" cache_value "${cache_line}")
  set(${out_var} "${cache_value}" PARENT_SCOPE)
endfunction()

function(ftimer_run_make_target worktree target)
  set(extra_env ${ARGN})

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${extra_env} "${ftimer_make_executable}" ${target}
    WORKING_DIRECTORY "${worktree}"
    RESULT_VARIABLE make_result
    OUTPUT_VARIABLE make_stdout
    ERROR_VARIABLE make_stderr
  )

  if(NOT make_result EQUAL 0)
    string(CONCAT make_output "${make_stdout}" "\n" "${make_stderr}")
    message(FATAL_ERROR "make ${target} failed.\n${make_output}")
  endif()
endfunction()

file(REMOVE_RECURSE "${TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${TEST_BINARY_DIR}")

find_program(ftimer_make_executable NAMES gmake make)
if(NOT ftimer_make_executable)
  message(STATUS
    "Skipping Makefile wrapper regression: no make-compatible executable is available on PATH."
  )
  return()
endif()

find_program(ftimer_gfortran_compiler NAMES gfortran)
find_program(ftimer_mpifort_compiler NAMES mpifort mpif90 mpif77)

if(NOT ftimer_gfortran_compiler OR NOT ftimer_mpifort_compiler)
  message(STATUS
    "Skipping Makefile wrapper regression: requires both gfortran and an MPI wrapper compiler on PATH."
  )
  return()
endif()

set(worktree "${TEST_BINARY_DIR}/repo")
ftimer_copy_tracked_repo("${REPO_ROOT}" "${worktree}")
if(FTIMER_MAKE_WRAPPER_SKIP)
  return()
endif()

set(common_flags "-DFTIMER_BUILD_SMOKE_TESTS=OFF -DFTIMER_BUILD_TESTS=OFF -DFTIMER_BUILD_EXAMPLES=OFF -DFTIMER_BUILD_BENCH=OFF")

ftimer_run_make_target(
  "${worktree}"
  all
  FC=
  CMAKE_FLAGS=${common_flags}
)

ftimer_run_make_target(
  "${worktree}"
  mpi
  FC=
  CMAKE_FLAGS=${common_flags}
)

ftimer_run_make_target(
  "${worktree}"
  openmp
  FC=
  CMAKE_FLAGS=${common_flags}
)

set(serial_cache "${worktree}/build/CMakeCache.txt")
set(mpi_cache "${worktree}/build-mpi/CMakeCache.txt")
set(openmp_cache "${worktree}/build-openmp/CMakeCache.txt")

foreach(required_cache IN ITEMS "${serial_cache}" "${mpi_cache}" "${openmp_cache}")
  if(NOT EXISTS "${required_cache}")
    message(FATAL_ERROR "Expected cache '${required_cache}' was not created.")
  endif()
endforeach()

ftimer_extract_cache_value("${mpi_cache}" "CMAKE_Fortran_COMPILER" mpi_compiler)
ftimer_extract_cache_value("${mpi_cache}" "FTIMER_USE_MPI" mpi_enabled)
ftimer_extract_cache_value("${openmp_cache}" "CMAKE_Fortran_COMPILER" openmp_compiler)
ftimer_extract_cache_value("${openmp_cache}" "FTIMER_USE_OPENMP" openmp_enabled)

file(REAL_PATH "${ftimer_gfortran_compiler}" expected_gfortran)
file(REAL_PATH "${ftimer_mpifort_compiler}" expected_mpifort)
file(REAL_PATH "${mpi_compiler}" actual_mpi_compiler)
file(REAL_PATH "${openmp_compiler}" actual_openmp_compiler)

if(serial_cache STREQUAL mpi_cache OR serial_cache STREQUAL openmp_cache OR mpi_cache STREQUAL openmp_cache)
  message(FATAL_ERROR "The wrapper regression test expects separate build directories for serial, MPI, and OpenMP targets.")
endif()

if(NOT actual_mpi_compiler STREQUAL expected_mpifort)
  message(FATAL_ERROR
    "make mpi should default to the MPI wrapper compiler.\n"
    "Expected: ${expected_mpifort}\n"
    "Actual:   ${actual_mpi_compiler}"
  )
endif()

if(NOT mpi_enabled STREQUAL "ON")
  message(FATAL_ERROR "make mpi did not configure FTIMER_USE_MPI=ON.")
endif()

if(NOT actual_openmp_compiler STREQUAL expected_gfortran)
  message(FATAL_ERROR
    "make openmp should default to gfortran.\n"
    "Expected: ${expected_gfortran}\n"
    "Actual:   ${actual_openmp_compiler}"
  )
endif()

if(NOT openmp_enabled STREQUAL "ON")
  message(FATAL_ERROR "make openmp did not configure FTIMER_USE_OPENMP=ON.")
endif()
