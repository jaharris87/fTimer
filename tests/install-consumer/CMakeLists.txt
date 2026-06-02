cmake_minimum_required(VERSION 3.16)

project(ftimer_installed_consumer LANGUAGES Fortran)

option(FTIMER_CONSUMER_ENABLE_MPI "Build the MPI installed-package consumer" OFF)
option(FTIMER_CONSUMER_ENABLE_OPENMP "Build the OpenMP installed-package consumer" OFF)

find_package(fTimer CONFIG REQUIRED)

add_executable(ftimer_installed_consumer main.F90)
target_link_libraries(ftimer_installed_consumer PRIVATE fTimer::ftimer)

add_executable(ftimer_installed_oop_consumer oop_main.F90)
target_link_libraries(ftimer_installed_oop_consumer PRIVATE fTimer::ftimer)

add_executable(ftimer_installed_mixed_consumer mixed_main.F90)
target_link_libraries(ftimer_installed_mixed_consumer PRIVATE fTimer::ftimer)

if(FTIMER_CONSUMER_ENABLE_MPI)
  add_executable(ftimer_installed_mpi_consumer mpi_main.F90)
  target_link_libraries(ftimer_installed_mpi_consumer PRIVATE fTimer::ftimer)
endif()

if(FTIMER_CONSUMER_ENABLE_MPI AND FTIMER_CONSUMER_ENABLE_OPENMP)
  add_executable(ftimer_installed_mpi_openmp_consumer mpi_openmp_main.F90)
  target_link_libraries(ftimer_installed_mpi_openmp_consumer PRIVATE fTimer::ftimer)
endif()
