> **When to read this:** When editing public docs, examples, maintainer docs,
> release evidence, or agent guidance and deciding what detail belongs where.

# Documentation Audience Guide

fTimer documentation should be human-first at the public entry points and
machine-checkable where exact contracts matter. Keep this guide short in spirit:
it exists to route detail to the right home, not to create another approval
layer.

## Document Roles

- `README.md`: the first user path. Lead with the task a user is trying to
  complete, show a working command or source shape, and link out for exact
  contracts.
- `examples/`: buildable demonstrations of supported source shapes. Keep
  caveats close to the example they affect, especially for MPI, OpenMP, hybrid
  timing, and installed-package consumption.
- `docs/troubleshooting.md`: symptom-oriented recovery steps for builds,
  package consumption, MPI, OpenMP, CSV, and summary/report failures. It should
  tell users what to try next before sending them to contract references.
- `docs/semantics.md`: the runtime contract. Put exhaustive behavior, edge
  cases, error-status rules, MPI/OpenMP boundaries, and source-of-truth
  precedence here instead of expanding the README.
- `docs/installed-api.md`: the installed source/API and package-consumption
  contract. Use it for stable imports, public-symbol boundaries, installed
  artifacts, schema or report surface changes, and compatibility notes.
- `docs/release-evidence.md`: the claim-evidence ledger. Keep release-facing
  support claims narrow here, with concrete CI jobs, tests, examples, and
  caveats.
- `docs/maintainer.md` and `docs/workflows/`: maintainer process. Keep PR
  routing, review labels, fallback review, findings disposition, release
  closeout, and repository bootstrap details out of ordinary user docs.
- `AGENTS.md` and `CLAUDE.md`: coding-agent operating context. Preserve
  machine-readable workflow detail and source-of-truth discipline here, but do
  not make normal users read these files to build or use fTimer.

## Practical Rules

- Lead with a user task, then give the smallest correct example or command.
- Keep exhaustive contracts in focused reference docs, and link to them from
  public entry points.
- Put caveats near the example, command, or claim they qualify.
- Avoid maintainer-process language in user docs unless the user needs it to
  choose a build, API, or support boundary.
- Preserve source-of-truth links for machine-readable detail instead of
  duplicating long rules in multiple places.
- When docs disagree, fix the disagreement in the highest-precedence source and
  route lower-precedence docs to it instead of paraphrasing a second contract.
