cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/contract-phases.cmake")
ftimer_reset_installed_consumer_contract_phases()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/setup.cmake")
if(ftimer_installed_consumer_contract_stop)
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/producer-install.cmake")
if(ftimer_installed_consumer_contract_stop)
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/installed-artifacts.cmake")

if(TEST_INSTALL_ONLY)
  ftimer_verify_installed_artifacts()
  ftimer_assert_installed_consumer_contract_phases(
    setup
    producer-install
    installed-artifacts
  )
  return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/package-version-probes.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/source-rejection-probes.cmake")

ftimer_verify_installed_artifacts()

ftimer_expect_installed_source_rejection_positive_control()
ftimer_expect_openmp_init_positional_rejected_cases()

if(TEST_ENABLE_MPI)
  ftimer_expect_integer_mpi_comm_rejected_cases()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/consumer-build.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/installed-consumer-contract/consumer-run.cmake")
if(ftimer_installed_consumer_contract_stop)
  return()
endif()

if(TEST_ENABLE_MPI)
  ftimer_assert_installed_consumer_contract_phases(
    setup
    producer-install
    package-version-probes
    installed-artifacts
    source-rejection-positive-control
    openmp-source-rejection-probes
    mpi-source-rejection-probes
    consumer-build
    consumer-run
  )
else()
  ftimer_assert_installed_consumer_contract_phases(
    setup
    producer-install
    package-version-probes
    installed-artifacts
    source-rejection-positive-control
    openmp-source-rejection-probes
    consumer-build
    consumer-run
  )
endif()
