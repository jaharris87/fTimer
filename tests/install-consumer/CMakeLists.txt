cmake_minimum_required(VERSION 3.16)

project(ftimer_installed_consumer LANGUAGES Fortran)

find_package(fTimer CONFIG REQUIRED)

add_executable(ftimer_installed_consumer main.F90)
target_link_libraries(ftimer_installed_consumer PRIVATE fTimer::ftimer)
