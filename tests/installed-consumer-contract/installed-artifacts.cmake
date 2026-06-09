# Installed artifact and documentation verification helpers.

function(ftimer_verify_installed_artifacts)
  set(expected_installed_module_artifacts
    ftimer.mod
    ftimer_clock.mod
    ftimer_core.mod
    ftimer_csv_validation.mod
    ftimer_mpi.mod
    ftimer_openmp.mod
    ftimer_summary.mod
    ftimer_types.mod
  )

  file(GLOB installed_module_artifact_paths LIST_DIRECTORIES FALSE "${installed_module_dir}/*")
  set(installed_module_artifact_names)
  foreach(installed_module_artifact_path IN LISTS installed_module_artifact_paths)
    get_filename_component(installed_module_artifact_name "${installed_module_artifact_path}" NAME)
    list(APPEND installed_module_artifact_names "${installed_module_artifact_name}")
  endforeach()

  list(SORT expected_installed_module_artifacts)
  list(SORT installed_module_artifact_names)

  if(NOT installed_module_artifact_names STREQUAL expected_installed_module_artifacts)
    list(JOIN expected_installed_module_artifacts ", " expected_installed_module_artifacts_text)
    list(JOIN installed_module_artifact_names ", " installed_module_artifact_names_text)
    message(FATAL_ERROR
      "Installed module artifact set mismatch.\n"
      "Expected: ${expected_installed_module_artifacts_text}\n"
      "Actual: ${installed_module_artifact_names_text}"
    )
  endif()

  foreach(misinstalled_module_dir IN LISTS misinstalled_module_dirs)
    if(EXISTS "${misinstalled_module_dir}")
      file(GLOB misinstalled_module_artifact_paths
        LIST_DIRECTORIES FALSE
        "${misinstalled_module_dir}/*.mod"
      )
      if(misinstalled_module_artifact_paths)
        message(FATAL_ERROR
          "Absolute CMAKE_INSTALL_INCLUDEDIR module artifacts were installed under an unexpected path '${misinstalled_module_dir}'."
        )
      endif()
    endif()
  endforeach()

  if(NOT EXISTS "${installed_api_note_path}")
    message(FATAL_ERROR
      "Installed API stability note was not found at '${installed_api_note_path}'."
    )
  endif()

  file(READ "${REPO_ROOT}/docs/installed-api.md" expected_installed_api_note)
  file(READ "${installed_api_note_path}" installed_api_note)
  if(NOT installed_api_note STREQUAL expected_installed_api_note)
    message(FATAL_ERROR
      "Installed API stability note does not match docs/installed-api.md."
    )
  endif()

  if(NOT EXISTS "${installed_license_path}")
    message(FATAL_ERROR
      "Installed BSD license was not found at '${installed_license_path}'."
    )
  endif()

  file(READ "${REPO_ROOT}/LICENSE" expected_license)
  file(READ "${installed_license_path}" installed_license)
  if(NOT installed_license STREQUAL expected_license)
    message(FATAL_ERROR
      "Installed BSD license does not match LICENSE."
    )
  endif()
endfunction()
