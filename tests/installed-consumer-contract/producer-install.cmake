# Configure, build, and install the producer tree consumed by package-contract checks.

set(configure_args
  -S "${REPO_ROOT}"
  -B "${TEST_BINARY_DIR}/producer-build"
  -G "${CMAKE_GENERATOR}"
  -DCMAKE_INSTALL_PREFIX=${install_prefix}
  -DCMAKE_INSTALL_INCLUDEDIR=${test_install_includedir}
  -DFTIMER_BUILD_SMOKE_TESTS=OFF
  -DFTIMER_BUILD_TESTS=OFF
  -DFTIMER_BUILD_EXAMPLES=OFF
  -DFTIMER_BUILD_BENCH=OFF
)

if(TEST_ENABLE_MPI)
  list(APPEND configure_args -DFTIMER_USE_MPI=ON)
endif()

if(TEST_ENABLE_OPENMP)
  list(APPEND configure_args -DFTIMER_USE_OPENMP=ON)
endif()

if(DEFINED TEST_OPENMP_ROOT AND NOT TEST_OPENMP_ROOT STREQUAL "")
  list(APPEND configure_args -DOpenMP_ROOT=${TEST_OPENMP_ROOT})
endif()

if(DEFINED CMAKE_MAKE_PROGRAM AND NOT CMAKE_MAKE_PROGRAM STREQUAL "")
  list(APPEND configure_args -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

if(DEFINED test_fortran_compiler AND NOT test_fortran_compiler STREQUAL "")
  list(APPEND configure_args -DCMAKE_Fortran_COMPILER=${test_fortran_compiler})
endif()

if(DEFINED TEST_BUILD_TYPE AND NOT TEST_BUILD_TYPE STREQUAL "")
  list(APPEND configure_args -DCMAKE_BUILD_TYPE=${TEST_BUILD_TYPE})
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${configure_args}
  RESULT_VARIABLE producer_configure_result
)
if(NOT producer_configure_result EQUAL 0)
  if(TEST_ALLOW_CONFIGURE_SKIP)
    message(STATUS
      "Skipping ${test_name}: producer configure failed for the optional compiler/runtime path."
    )
    set(ftimer_installed_consumer_contract_stop TRUE)
    return()
  endif()
  message(FATAL_ERROR "Failed to configure the producer install tree.")
endif()

set(producer_build_args
  --build "${TEST_BINARY_DIR}/producer-build"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_build_args --config "${TEST_CONFIG}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" ${producer_build_args}
  RESULT_VARIABLE producer_build_result
)
if(NOT producer_build_result EQUAL 0)
  message(FATAL_ERROR "Failed to build the producer install tree.")
endif()

set(producer_install_args
  --install "${TEST_BINARY_DIR}/producer-build"
)
if(DEFINED TEST_CONFIG AND NOT TEST_CONFIG STREQUAL "")
  list(APPEND producer_install_args --config "${TEST_CONFIG}")
endif()

if(TEST_USE_DESTDIR)
  set(producer_install_command
    "${CMAKE_COMMAND}" -E env "DESTDIR=${test_destdir}" "${CMAKE_COMMAND}" ${producer_install_args}
  )
else()
  set(producer_install_command "${CMAKE_COMMAND}" ${producer_install_args})
endif()

execute_process(
  COMMAND ${producer_install_command}
  RESULT_VARIABLE producer_install_result
)
if(NOT producer_install_result EQUAL 0)
  message(FATAL_ERROR "Failed to install the producer package.")
endif()

ftimer_record_installed_consumer_contract_phase(producer-install)
