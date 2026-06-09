# Installed-package source rejection probes for unsupported public calls.

function(ftimer_expect_installed_source_rejected probe_name probe_source)
  set(probe_source_dir "${TEST_BINARY_DIR}/source-rejection-src-${probe_name}")
  set(probe_build_dir "${TEST_BINARY_DIR}/source-rejection-build-${probe_name}")

  file(REMOVE_RECURSE "${probe_source_dir}" "${probe_build_dir}")
  file(MAKE_DIRECTORY "${probe_source_dir}")
  file(WRITE "${probe_source_dir}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.16)
project(ftimer_integer_mpi_comm_rejection LANGUAGES Fortran)

find_package(fTimer CONFIG REQUIRED)

add_executable(ftimer_integer_mpi_comm_rejection main.F90)
target_link_libraries(ftimer_integer_mpi_comm_rejection PRIVATE fTimer::ftimer)
]=])
  file(WRITE "${probe_source_dir}/main.F90" "${probe_source}")

  set(probe_configure_args
    -S "${probe_source_dir}"
    -B "${probe_build_dir}"
    -G "${CMAKE_GENERATOR}"
    -DCMAKE_PREFIX_PATH=${install_prefix}
  )
  if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
    list(APPEND probe_configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
  endif()
  if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
  endif()
  if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
  endif()
  if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
    list(APPEND probe_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${probe_configure_args}
    RESULT_VARIABLE probe_configure_result
    OUTPUT_VARIABLE probe_configure_output
    ERROR_VARIABLE probe_configure_error
  )
  if(NOT probe_configure_result EQUAL 0)
    message(FATAL_ERROR
      "Failed to configure the installed source rejection probe '${probe_name}'.\n"
      "stdout:\n${probe_configure_output}\n"
      "stderr:\n${probe_configure_error}"
    )
  endif()

  set(probe_build_args --build "${probe_build_dir}")
  if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
    list(APPEND probe_build_args --config "${TEST_CONFIG}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${probe_build_args}
    RESULT_VARIABLE probe_build_result
    OUTPUT_VARIABLE probe_build_output
    ERROR_VARIABLE probe_build_error
  )
  if(probe_build_result EQUAL 0)
    message(FATAL_ERROR
      "Installed package accepted rejected source probe '${probe_name}'; expected the build to fail."
    )
  endif()
endfunction()

function(ftimer_expect_integer_mpi_comm_rejected probe_name probe_source)
  ftimer_expect_installed_source_rejected("${probe_name}" "${probe_source}")
endfunction()

function(ftimer_expect_openmp_init_positional_rejected_cases)
  ftimer_expect_installed_source_rejected(openmp-positional-config [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer

   call timer%init(config)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_installed_source_rejected(openmp-positional-config-ierr [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: ierr

   call timer%init(config, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])
endfunction()

function(ftimer_expect_integer_mpi_comm_rejected_cases)
  ftimer_expect_integer_mpi_comm_rejected(oop-keyword [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(comm=legacy_comm, ierr=ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-keyword [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(comm=legacy_comm, ierr=ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(oop-positional-single [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(legacy_comm)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-positional-single [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(legacy_comm)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(oop-positional-two-arg [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_core, only: ftimer_t
   implicit none

   type(ftimer_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(legacy_comm, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(procedural-positional-two-arg [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer, only: ftimer_init
   implicit none

   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call ftimer_init(legacy_comm, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(openmp-keyword [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(config=config, comm=legacy_comm, ierr=ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(openmp-positional-config-and-int [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(config, legacy_comm)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(openmp-positional-config-int-ierr [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: ierr
   integer :: legacy_comm

   legacy_comm = 2
   call timer%init(config, legacy_comm, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(openmp-positional-config-mpi-comm [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use mpi_f08, only: MPI_COMM_WORLD
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer

   call timer%init(config, MPI_COMM_WORLD)
end program ftimer_integer_mpi_comm_rejection
]=])

  ftimer_expect_integer_mpi_comm_rejected(openmp-positional-config-mpi-comm-ierr [=[
program ftimer_integer_mpi_comm_rejection
   use ftimer_openmp, only: ftimer_openmp_config_t, ftimer_openmp_t
   use mpi_f08, only: MPI_COMM_WORLD
   implicit none

   type(ftimer_openmp_config_t) :: config
   type(ftimer_openmp_t) :: timer
   integer :: ierr

   call timer%init(config, MPI_COMM_WORLD, ierr)
end program ftimer_integer_mpi_comm_rejection
]=])
endfunction()
