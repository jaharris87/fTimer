cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED REPO_ROOT OR REPO_ROOT STREQUAL "")
  message(FATAL_ERROR "REPO_ROOT is required")
endif()

set(contract_dir "${REPO_ROOT}/tests/installed-consumer-contract")
set(driver_path "${REPO_ROOT}/tests/check_installed_package_consumer.cmake")
set(phase_helper_path "${contract_dir}/contract-phases.cmake")
set(stderr_helper_path "${contract_dir}/mpi-openmp-diagnostics.cmake")
set(source_rejection_path "${contract_dir}/source-rejection-probes.cmake")
set(package_version_path "${contract_dir}/package-version-probes.cmake")

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
if(NOT driver_text MATCHES "ftimer_assert_installed_consumer_contract_mpi_run_skip_phases")
  message(FATAL_ERROR
    "Installed-consumer driver must assert the MPI-only no-launcher phase prefix before skipping."
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
if(NOT source_rejection_text MATCHES "interface_diagnostic_regex")
  message(FATAL_ERROR
    "Source rejection probes must require interface-rejection compiler diagnostics."
  )
endif()

file(READ "${package_version_path}" package_version_text)
foreach(required_package_probe_text IN ITEMS
    "SameMajorVersion"
    "same-major-newer-minor-package"
    "too-new-minor-request"
    "too-new-patch-request"
    "pre-v1-request"
    "future-major")
  if(NOT package_version_text MATCHES "${required_package_probe_text}")
    message(FATAL_ERROR
      "Package-version probes must retain v1 SameMajorVersion coverage term: ${required_package_probe_text}"
    )
  endif()
endforeach()

include("${phase_helper_path}")
ftimer_record_installed_consumer_contract_phase(meta-setup)
ftimer_record_installed_consumer_contract_phase(meta-run)
ftimer_assert_installed_consumer_contract_phases(meta-setup meta-run)
ftimer_reset_installed_consumer_contract_phases()
ftimer_record_installed_consumer_contract_phase(setup)
ftimer_record_installed_consumer_contract_phase(producer-install)
ftimer_record_installed_consumer_contract_phase(package-version-probes)
ftimer_record_installed_consumer_contract_phase(installed-artifacts)
ftimer_record_installed_consumer_contract_phase(source-rejection-positive-control)
ftimer_record_installed_consumer_contract_phase(openmp-source-rejection-probes)
ftimer_record_installed_consumer_contract_phase(mpi-source-rejection-probes)
ftimer_record_installed_consumer_contract_phase(consumer-build)
ftimer_assert_installed_consumer_contract_mpi_run_skip_phases()

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

string(CONCAT wrong_status_stderr
  "ftimer_openmp recorded 1 worker diagnostics; first status 4, overflow 0\n"
  "ftimer_openmp recorded 2 worker diagnostics; first status 5, overflow 0\n"
)
ftimer_check_openmp_api_mpi_openmp_stderr(
  "${wrong_status_stderr}"
  wrong_status_stderr_ok
  wrong_status_stderr_message
)
if(wrong_status_stderr_ok)
  message(FATAL_ERROR
    "Canned MPI+OpenMP diagnostic parser accepted stderr with the wrong worker status."
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

string(CONCAT same_line_unexpected_stderr
  "ftimer_openmp recorded 1 worker diagnostics; first status 5, overflow 0 ftimer_unexpected\n"
  "ftimer_openmp recorded 2 worker diagnostics; first status 5, overflow 0\n"
)
ftimer_check_openmp_api_mpi_openmp_stderr(
  "${same_line_unexpected_stderr}"
  same_line_unexpected_stderr_ok
  same_line_unexpected_stderr_message
)
if(same_line_unexpected_stderr_ok)
  message(FATAL_ERROR
    "Canned MPI+OpenMP diagnostic parser accepted an unexpected fTimer token on a diagnostic line."
  )
endif()
