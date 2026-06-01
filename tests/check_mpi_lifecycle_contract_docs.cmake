set(readme_path "${REPO_ROOT}/README.md")
set(semantics_path "${REPO_ROOT}/docs/semantics.md")
set(installed_api_path "${REPO_ROOT}/docs/installed-api.md")
set(design_path "${REPO_ROOT}/docs/design.md")
set(agents_path "${REPO_ROOT}/AGENTS.md")
set(claude_path "${REPO_ROOT}/CLAUDE.md")
set(mpi_example_path "${REPO_ROOT}/examples/mpi_example.F90")
set(mpi_consumer_path "${REPO_ROOT}/tests/install-consumer/mpi_main.F90")

function(require_contains path needle message_text)
  file(READ "${path}" text)
  string(FIND "${text}" "${needle}" found_at)
  if(found_at EQUAL -1)
    message(FATAL_ERROR "${message_text}")
  endif()
endfunction()

set(lifecycle_sentence "MPI-enabled fTimer must be used after `MPI_Init` and before `MPI_Finalize`")
set(non_owning_sentence "fTimer stores that communicator as a non-owning handle")

require_contains("${readme_path}" "${lifecycle_sentence}"
  "README must document the MPI_Init/MPI_Finalize lifetime for MPI-enabled fTimer.")
require_contains("${semantics_path}" "${lifecycle_sentence}"
  "docs/semantics.md must document the MPI_Init/MPI_Finalize lifetime for MPI-enabled fTimer.")
require_contains("${installed_api_path}" "${lifecycle_sentence}"
  "docs/installed-api.md must document the MPI_Init/MPI_Finalize lifetime for installed MPI consumers.")
require_contains("${agents_path}" "${lifecycle_sentence}"
  "AGENTS.md must keep the MPI lifecycle contract visible to coding agents.")
require_contains("${claude_path}" "${lifecycle_sentence}"
  "CLAUDE.md must keep the MPI lifecycle contract visible to coding agents.")

require_contains("${readme_path}" "${non_owning_sentence}"
  "README must document that init(comm=...) stores a non-owning communicator handle.")
require_contains("${semantics_path}" "stores a non-owning communicator handle"
  "docs/semantics.md must document that init(comm=...) stores a non-owning communicator handle.")
require_contains("${installed_api_path}" "stores the selected communicator as a non-owning handle"
  "docs/installed-api.md must document that installed MPI consumers retain communicator ownership.")
require_contains("${design_path}" "non-owning handle"
  "docs/design.md must not imply fTimer owns or duplicates MPI communicators.")
require_contains("${agents_path}" "communicator handles are non-owning"
  "AGENTS.md must not imply fTimer owns or duplicates MPI communicators.")
require_contains("${claude_path}" "communicator handles are non-owning"
  "CLAUDE.md must not imply fTimer owns or duplicates MPI communicators.")

require_contains("${mpi_example_path}" "non-owning handle"
  "examples/mpi_example.F90 must make the borrowed communicator lifetime visible.")
require_contains("${mpi_consumer_path}" "non-owning handle"
  "tests/install-consumer/mpi_main.F90 must make the borrowed communicator lifetime visible.")
require_contains("${mpi_consumer_path}" "MPI_Comm_free"
  "tests/install-consumer/mpi_main.F90 must keep a caller-owned subcommunicator valid through fTimer finalization.")
