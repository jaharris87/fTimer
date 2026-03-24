set(readme_path "${REPO_ROOT}/README.md")
set(design_path "${REPO_ROOT}/docs/design.md")

file(READ "${readme_path}" readme_text)
file(READ "${design_path}" design_text)

if(readme_text MATCHES "ftimer_init\\(ierr\\)")
  message(FATAL_ERROR "README still documents legacy positional ftimer_init(ierr).")
endif()

if(design_text MATCHES "call timer%init\\(\\[comm\\] \\[, mismatch_mode\\] \\[, ierr\\]\\)")
  message(FATAL_ERROR "docs/design.md still documents the ambiguous positional OOP init shape.")
endif()

if(design_text MATCHES "call ftimer_init\\(\\[ierr\\]\\)")
  message(FATAL_ERROR "docs/design.md still documents a positional integer procedural init form.")
endif()

if(NOT readme_text MATCHES "Pass `ierr`, `comm`, and `mismatch_mode` by keyword")
  message(FATAL_ERROR "README must state that integer init arguments are passed safely by keyword.")
endif()

if(NOT design_text MATCHES "Pass `ierr`, `comm`, and `mismatch_mode` by keyword")
  message(FATAL_ERROR "docs/design.md must state that integer init arguments are passed safely by keyword.")
endif()

if(NOT readme_text MATCHES "positional integer calls still compile but are ambiguous")
  message(FATAL_ERROR "README must warn that positional integer init calls still compile but are ambiguous.")
endif()

if(NOT design_text MATCHES "positional integer calls still compile but are ambiguous")
  message(FATAL_ERROR "docs/design.md must warn that positional integer init calls still compile but are ambiguous.")
endif()
