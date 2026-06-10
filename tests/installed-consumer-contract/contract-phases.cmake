# Phase sentinels for the installed-consumer contract driver.

function(ftimer_reset_installed_consumer_contract_phases)
  set_property(GLOBAL PROPERTY FTIMER_INSTALLED_CONSUMER_CONTRACT_PHASES)
endfunction()

function(ftimer_record_installed_consumer_contract_phase phase)
  set_property(GLOBAL APPEND PROPERTY FTIMER_INSTALLED_CONSUMER_CONTRACT_PHASES "${phase}")
endfunction()

function(ftimer_assert_installed_consumer_contract_phases)
  set(expected_phases ${ARGN})
  get_property(actual_phases GLOBAL PROPERTY FTIMER_INSTALLED_CONSUMER_CONTRACT_PHASES)

  if(NOT actual_phases STREQUAL expected_phases)
    list(JOIN expected_phases ", " expected_phase_text)
    list(JOIN actual_phases ", " actual_phase_text)
    message(FATAL_ERROR
      "Installed-consumer contract phase list mismatch.\n"
      "Expected: ${expected_phase_text}\n"
      "Actual: ${actual_phase_text}"
    )
  endif()
endfunction()
