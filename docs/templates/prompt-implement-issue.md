Implement issue #<NN>: <short title>.

Goal:
- Complete the scoped implementation for this issue only.

Start with this minimal working set:
1. the issue
2. docs/agent-context.md
3. the directly touched source files
4. the directly touched tests

Read additional files only if required:
- docs/semantics.md only if runtime behavior or contract is changing or unclear
- README.md only if user-facing docs/examples/install guidance may need updates
- docs/design.md only if architecture or future-design alignment is part of the task
- workflow docs only if this session reaches the PR/review phase

Working rules:
- Read each file once per phase unless it changed or a specific ambiguity remains.
- Do not do a broad repo sweep by default.
- After the initial discovery pass, switch to implementation mode.
- Batch updates by major phase, not by file or micro-step.

Deliverables:
- code changes
- test changes as needed
- doc changes only if required by the scope
- concise summary of behavior changed vs unchanged
- session handoff using docs/templates/session-handoff.md

Stop condition:
- Stop after implementation, validation, and the handoff note.
- Do not continue into heavy review monitoring or next-task planning.