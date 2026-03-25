set(readme_path "${REPO_ROOT}/README.md")
set(design_path "${REPO_ROOT}/docs/design.md")

file(READ "${readme_path}" readme_text)
file(READ "${design_path}" design_text)

# Reject the old dangerous signature where ierr came first.
if(readme_text MATCHES "ftimer_init\\(ierr\\)")
  message(FATAL_ERROR "README still documents legacy positional ftimer_init(ierr).")
endif()

if(design_text MATCHES "call ftimer_init\\(\\[ierr\\]\\)")
  message(FATAL_ERROR "docs/design.md still documents a positional integer procedural init form.")
endif()

# Require documentation of the ierr-last reorder and its safety rationale.
if(NOT readme_text MATCHES "`ierr` is now the last optional argument")
  message(FATAL_ERROR "README must document that ierr is last in the init signature.")
endif()

if(NOT design_text MATCHES "`ierr` is now the last optional argument")
  message(FATAL_ERROR "docs/design.md must document that ierr is last in the init signature.")
endif()

# Require keyword recommendation.
if(NOT readme_text MATCHES "Keywords are recommended for readability")
  message(FATAL_ERROR "README must recommend keyword arguments for readability.")
endif()

if(NOT design_text MATCHES "Keywords are recommended for readability")
  message(FATAL_ERROR "docs/design.md must recommend keyword arguments for readability.")
endif()
