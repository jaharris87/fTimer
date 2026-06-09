cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/setup.cmake")
if(ftimer_installed_consumer_contract_stop)
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/producer-install.cmake")
if(ftimer_installed_consumer_contract_stop)
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/installed-artifacts.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/source-rejection-probes.cmake")

if(TEST_INSTALL_ONLY)
  ftimer_verify_installed_artifacts()
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/package-version-probes.cmake")

ftimer_verify_installed_artifacts()

ftimer_expect_openmp_init_positional_rejected_cases()

if(TEST_ENABLE_MPI)
  ftimer_expect_integer_mpi_comm_rejected_cases()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/consumer-build.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/consumer-run.cmake")
