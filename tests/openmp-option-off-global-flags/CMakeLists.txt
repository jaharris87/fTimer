cmake_minimum_required(VERSION 3.16)

project(ftimer_openmp_option_off_global_flags LANGUAGES Fortran)

find_package(fTimer REQUIRED CONFIG)
find_package(OpenMP REQUIRED COMPONENTS Fortran)

add_executable(ftimer_openmp_option_off_global_flags main.F90)
target_link_libraries(ftimer_openmp_option_off_global_flags
  PRIVATE
    fTimer::ftimer
    OpenMP::OpenMP_Fortran
)
