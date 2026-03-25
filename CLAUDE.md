# CLAUDE.md

This file provides Claude Code guidance for working in this repository.

Start with `docs/agent-context.md`.
That file is the shared baseline context for coding agents in this repo.

## Claude-Specific Guidance

- Keep the working set minimal and purpose-built for the task.
- Do not reread unchanged files without a specific reason.
- Prefer fresh, narrowly scoped review passes over inheriting a large implementation context.
- For review tasks, start from the diff and touched files first, then expand only if the review question requires it.
- After the initial discovery pass, switch into implementation mode.
- Batch progress updates by major phase rather than narrating each micro-step.

## When To Read Additional Docs

- Read `docs/semantics.md` only when runtime behavior or contract changes are changing or unclear.
- Read `README.md` only when user-facing behavior, examples, or documentation changes.
- Read `docs/design.md` only for architectural or future-facing questions.
- Read `docs/maintainer.md` only for issue/PR/review/disposition workflow tasks.

## Implementation Defaults

For most coding tasks, start with:

1. task or issue description
2. `docs/agent-context.md`
3. touched source files
4. touched tests

Expand only as needed.

## Review Prompt Library

The review prompt library lives under `.github/prompts/` and `.github/prompts/detailed/`.

Use those prompts for:
- automatic `@codex review` workflows
- fallback manual review
- targeted repo-health or audit reviews

Keep repository facts and coding context in `docs/agent-context.md`, not duplicated in prompt files unless the task specifically requires it.
