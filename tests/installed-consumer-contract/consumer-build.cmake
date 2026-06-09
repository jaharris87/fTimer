# Configure, build, and locate installed-package consumer executables.

set(consumer_configure_args
  -S "${consumer_source_dir}"
  -B "${consumer_build_dir}"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_PREFIX_PATH=${install_prefix}
  -DFTIMER_CONSUMER_ENABLE_MPI=${TEST_ENABLE_MPI}
  -DFTIMER_CONSUMER_ENABLE_OPENMP=${TEST_ENABLE_OPENMP}
)

if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
  list(APPEND consumer_configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
endif()

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND consumer_configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_configure_args}
  RESULT_VARIABLE consumer_configure_result
)
if(NOT consumer_configure_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure the installed-package consumer.")
endif()

set(consumer_build_args
  --build "${consumer_build_dir}"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND consumer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${consumer_build_args}
  RESULT_VARIABLE consumer_build_result
)
if(NOT consumer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the installed-package consumer.")
endif()

set(consumer_executable "${consumer_build_dir}/ftimer_installed_consumer${TEST_EXECUTABLE_SUFFIX}")
set(oop_consumer_executable "${consumer_build_dir}/ftimer_installed_oop_consumer${TEST_EXECUTABLE_SUFFIX}")
set(mixed_consumer_executable "${consumer_build_dir}/ftimer_installed_mixed_consumer${TEST_EXECUTABLE_SUFFIX}")
set(openmp_api_consumer_executable
  "${consumer_build_dir}/ftimer_installed_openmp_api_consumer${TEST_EXECUTABLE_SUFFIX}"
)
set(openmp_api_openmp_consumer_executable
  "${consumer_build_dir}/ftimer_installed_openmp_api_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  set(configured_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_oop_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_oop_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_mixed_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_mixed_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_openmp_api_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_openmp_api_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  set(configured_openmp_api_openmp_consumer_executable
    "${consumer_build_dir}/${TEST_CONFIG}/ftimer_installed_openmp_api_openmp_consumer${TEST_EXECUTABLE_SUFFIX}"
  )
  if(EXISTS "${configured_consumer_executable}")
    set(consumer_executable "${configured_consumer_executable}")
  endif()
  if(EXISTS "${configured_oop_consumer_executable}")
    set(oop_consumer_executable "${configured_oop_consumer_executable}")
  endif()
  if(EXISTS "${configured_mixed_consumer_executable}")
    set(mixed_consumer_executable "${configured_mixed_consumer_executable}")
  endif()
  if(EXISTS "${configured_openmp_api_consumer_executable}")
    set(openmp_api_consumer_executable "${configured_openmp_api_consumer_executable}")
  endif()
  if(EXISTS "${configured_openmp_api_openmp_consumer_executable}")
    set(openmp_api_openmp_consumer_executable "${configured_openmp_api_openmp_consumer_executable}")
  endif()
endif()
