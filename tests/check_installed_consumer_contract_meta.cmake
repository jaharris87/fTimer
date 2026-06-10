cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED REPO_ROOT OR REPO_ROOT STREQUAL "")
  message(FATAL_ERROR "REPO_ROOT is required")
endif()

set(contract_dir "${REPO_ROOT}/tests/installed-consumer-contract")
set(driver_path "${REPO_ROOT}/tests/check_installed_package_consumer.cmake")
set(phase_helper_path "${contract_dir}/contract-phases.cmake")
set(stderr_helper_path "${contract_dir}/mpi-openmp-diagnostics.cmake")
set(source_rejection_path "${contract_dir}/source-rejection-probes.cmake")

if(NOT EXISTS "${phase_helper_path}")
  message(FATAL_ERROR
    "Installed-consumer contract phase helper is missing: ${phase_helper_path}"
  )
endif()
if(NOT EXISTS "${stderr_helper_path}")
  message(FATAL_ERROR
    "Installed-consumer MPI+OpenMP diagnostic helper is missing: ${stderr_helper_path}"
  )
endif()

file(READ "${driver_path}" driver_text)
if(NOT driver_text MATCHES "contract-phases\\.cmake")
  message(FATAL_ERROR
    "Installed-consumer driver must include the phase contract helper."
  )
endif()
if(NOT driver_text MATCHES "ftimer_assert_installed_consumer_contract_phases")
  message(FATAL_ERROR
    "Installed-consumer driver must assert the expected phase list."
  )
endif()

file(READ "${source_rejection_path}" source_rejection_text)
if(NOT source_rejection_text MATCHES "ftimer_expect_installed_source_accepted")
  message(FATAL_ERROR
    "Source rejection contract must include a positive-control installed-source probe."
  )
endif()
if(NOT source_rejection_text MATCHES "required_diagnostic")
  message(FATAL_ERROR
    "Source rejection probes must require stable diagnostic fragments, not only any build failure."
  )
endif()

include("${phase_helper_path}")
ftimer_record_installed_consumer_contract_phase(meta-setup)
ftimer_record_installed_consumer_contract_phase(meta-run)
ftimer_assert_installed_consumer_contract_phases(meta-setup meta-run)

include("${stderr_helper_path}")
string(CONCAT valid_stderr
  "ftimer_openmp recorded 1 worker diagnostics; first status 5, overflow 0\n"
  "ftimer_openmp recorded 2 worker diagnostics; first status 5, overflow 0\n"
)
ftimer_check_openmp_api_mpi_openmp_stderr(
  "${valid_stderr}"
  valid_stderr_ok
  valid_stderr_message
)
if(NOT valid_stderr_ok)
  message(FATAL_ERROR
    "Valid canned MPI+OpenMP diagnostic stderr was rejected:\n${valid_stderr_message}"
  )
endif()

string(CONCAT missing_rank_stderr
  "ftimer_openmp recorded 1 worker diagnostics; first status 5, overflow 0\n"
)
ftimer_check_openmp_api_mpi_openmp_stderr(
  "${missing_rank_stderr}"
  missing_rank_stderr_ok
  missing_rank_stderr_message
)
if(missing_rank_stderr_ok)
  message(FATAL_ERROR
    "Canned MPI+OpenMP diagnostic parser accepted stderr missing the rank-1-style diagnostic."
  )
endif()

string(CONCAT unexpected_stderr
  "ftimer_openmp recorded 1 worker diagnostics; first status 5, overflow 0\n"
  "ftimer_unexpected extra diagnostic\n"
  "ftimer_openmp recorded 2 worker diagnostics; first status 5, overflow 0\n"
)
ftimer_check_openmp_api_mpi_openmp_stderr(
  "${unexpected_stderr}"
  unexpected_stderr_ok
  unexpected_stderr_message
)
if(unexpected_stderr_ok)
  message(FATAL_ERROR
    "Canned MPI+OpenMP diagnostic parser accepted unexpected fTimer stderr."
  )
endif()
