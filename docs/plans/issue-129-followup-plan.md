# Issue #129 Follow-Up Plan

This document is the shared decision record and execution plan for the adversarial-assessment follow-up umbrella in [#129](https://github.com/jaharris87/fTimer/issues/129).

Every new Codex thread opened for this follow-up set should read this file first, along with `AGENTS.md` and the specific issue it is addressing.

## Purpose

This plan exists to keep the follow-up queue coherent across multiple scoped PRs. It locks the strategic decisions that were still open in #115-#118, sets the required execution order, and records the expected workflow for each task.

The near-term goal is to improve product maturity and credibility for the adopter niche that current `main` already serves best: disciplined serial and pure-MPI wall-clock timing.

## Locked Strategic Decisions

These decisions are fixed for this follow-up wave unless a later maintainer decision record supersedes them explicitly.

- Primary audience: disciplined serial and pure-MPI users.
- OpenMP product position: keep the current master-thread-only guard model explicit and narrow; do not imply real hybrid-thread timing support.
- Data-first summary contract: keep `get_summary()` local, but strengthen the public summary data so downstream consumers get explicit tree structure through per-summary node ids and parent ids.
- Summary identity scope: summary node identity only needs to be stable within one produced summary object. This wave does not promise stability across runs.
- External-profiler integration: defer any serious profiler-backend contract. Callbacks remain lightweight intra-run hooks in this wave.
- MPI reporting direction: replace the current hybrid local-plus-reduced MPI summary contract with a distinct global result whose populated fields are globally meaningful on every participating rank.
- API evolution stance: API-breaking changes are acceptable where needed in the MPI and API-hardening tasks, provided docs, examples, install-consumer coverage, and tests move in the same PR.

## Required Task Order

Tasks 3-8 must stay serial because they all change the same core runtime contracts and public documentation.

1. Task 1: #115, #116, #117, #118, #127, #129
2. Task 2: #120 plus the docs/disposition portion of #121
3. Task 3: #122
4. Task 4: #119, after Task 3
5. Task 5: #124, after Task 4
6. Task 6: #126
7. Task 7: #125, after Task 6
8. Task 8: #123, after Task 7
9. Task 9: revisit #121 after Tasks 2, 3, and 7

## Workflow Rules

- Use one issue-linked feature branch and one ready-for-review PR per task.
- Update umbrella issue #129 after each merge with `fixed`, `deferred`, or `superseded`.
- Do not close #115, #116, #117, #118, or #127 until the Task 1 PR merges.
- Let automatic review labels land first.
- Add `codex-adoptability-review` on Tasks 1-2.
- Add `codex-pragmatic-design-review` on Tasks 3-7.
- Add `codex-performance-overhead-review` on Task 8.
- Do not open workflow-only or automation-only PRs outside Task 1 until the product-facing queue through Task 7 is complete.

## Task Cards

### Task 1: Decision Record and Umbrella Hygiene

- Issues: #115, #116, #117, #118, #127, #129
- Goal: record the strategic decisions, save this plan, reflect the task order in the umbrella, and leave the strategic issues ready to close once merged.
- Repo scope: `docs/plans/issue-129-followup-plan.md` plus any minimal issue-hygiene docs/comments needed to point at this plan.
- Expected issue disposition after merge:
  - close #115, #116, #117, #118, and #127 as decided/planned
  - keep #129 open as the umbrella
- Initial thread prompt:

```text
Read AGENTS.md and issue #129 plus #115-#118 and #127. Create /Users/hrh/claude_projects/fTimer/docs/plans/issue-129-followup-plan.md and record these decisions exactly: primary audience = disciplined serial + pure-MPI users; data-first summary = explicit tree with per-summary node ids and parent ids; external-profiler integration = deferred; MPI reporting = distinct global result. Update the strategic issues and umbrella issue to reflect the decision record and execution order. Keep this PR to plan/docs/issue hygiene only.
```

### Task 2: Product-Position Narrowing

- Issues: #120 and the docs/disposition portion of #121
- Goal: narrow user-facing claims around OpenMP and callbacks so the repo clearly presents serial and pure-MPI timing as the core supported story.
- Expected changes: README, `docs/semantics.md`, `docs/design.md`, examples, and issue cross-links.
- Non-goal: no behavior changes in this PR.
- Initial thread prompt:

```text
Read /Users/hrh/claude_projects/fTimer/docs/plans/issue-129-followup-plan.md first, then implement issue #120. Narrow the product position to serial and pure-MPI first, make the OpenMP carve-out impossible to miss, and soften callback claims so they are clearly lightweight intra-run hooks rather than a serious profiler integration contract. Keep behavior unchanged in this PR; this is a docs/examples/contract-alignment pass, and it should also update issue #121's near-term disposition.
```

### Task 3: Local Summary Tree Contract

- Issue: #122
- Goal: strengthen `ftimer_summary_t` so local summaries are explicit tree data rather than formatter-oriented flat rows alone.
- Required outcome:
  - retain `name` and `depth`
  - add stable per-summary node ids
  - add parent ids
  - preserve preorder formatter compatibility
  - avoid any cross-run identity promise
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #122. Keep local summaries as the main data-first API, but make them explicit-tree data: retain name/depth, add stable per-summary node identity and parent linkage, preserve preorder formatting compatibility, and do not promise cross-run stability. Update unit tests, MPI-adjacent assumptions, README/docs, and any install-consumer expectations touched by the public type.
```

### Task 4: Distinct Global MPI Result

- Issue: #119
- Depends on: Task 3
- Goal: replace the hybrid MPI summary contract with a distinct global MPI result shape and add first-class MPI reporting.
- Required outcome:
  - successful MPI reporting should produce globally meaningful fields on every participating rank
  - add MPI-aware print/write support
  - migrate examples, tests, and install-consumer coverage together
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #119 on top of the explicit-tree summary work. Replace the current hybrid local-plus-reduced mpi_summary contract with a distinct global MPI summary/result shape whose populated fields are globally meaningful on every participating rank. Add first-class MPI print/write support, migrate examples/tests/install-consumer coverage in the same PR, and treat repo-wide API migration as acceptable if needed.
```

### Task 5: MPI Credibility Pass

- Issue: #124
- Depends on: Task 4
- Goal: narrow unsupported MPI interface claims unless the repo adds real validation, and make MPI reductions more actionable for debugging.
- Default decision for this wave: narrow docs to the validated `use mpi` path unless real new automation lands in the same PR.
- Desired additions: rank-of-min / rank-of-max style data and better descriptor mismatch diagnostics.
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #124 after the new MPI result lands. Default to narrowing docs to the validated use-mpi path unless you also add real automation for mpif.h or mpi_f08. Extend the global MPI result with rank-of-min/rank-of-max style data, and make descriptor-preflight failures report the disagreeing ranks or an equivalent actionable diagnostic.
```

### Task 6: Omitted-`ierr` Lifecycle Hardening

- Issue: #126
- Goal: stop producing synthetic recovery behavior when lifecycle calls encounter active timers and `ierr` is omitted.
- Required outcome:
  - `init`, `reset`, and `finalize` warn and return without mutating state in those cases
  - warn/repair mismatch handling remains explicit opt-in behavior
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #126. Make omitted-ierr lifecycle errors correctness-first: no force-stop, no synthetic summary data, and no hidden cleanup. The ierr-present path should still return explicit codes; the ierr-absent path should warn and leave state unchanged. Update tests and docs so the contract is precise.
```

### Task 7: API Surface Hardening

- Issue: #125
- Depends on: Task 6
- Goal: reduce exposure of mutable runtime internals and tighten the supported surface.
- Required outcome:
  - make `clock`, `on_event`, and `user_data` private
  - replace direct mutation with setter/clearer APIs and lifecycle checks
  - narrow the documented supported-module surface
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #125. Move raw mutable runtime internals behind explicit setter APIs, enforce sensible lifecycle rules for clock and callback configuration, and tighten the documented supported surface so ftimer_clock/ftimer_summary/ftimer_mpi are no longer presented as stable user-facing modules. Keep the PR focused on supported-surface hardening, not packaging churn for its own sake.
```

### Task 8: Lookup and Allocation Scalability

- Issue: #123
- Depends on: Task 7
- Goal: improve lookup and growth behavior without demoting ergonomic name-based timing.
- Required outcome:
  - replace linear name lookup and repeated whole-array growth with more scalable internal structures
  - keep name-based start/stop as the primary user story
  - keep `lookup`/`start_id`/`stop_id` as optional hot-path tools
- Initial thread prompt:

```text
Read the plan doc first, then implement issue #123. Preserve the public API, but replace linear name lookup and repeated whole-array growth with a scalable internal mapping and capacity strategy. Keep name-based start/stop as the default ergonomic path, document lookup/start_id/stop_id as optional hot-path optimization, and update the benchmark harness or expectations to show the improvement.
```

### Task 9: Revisit the Deferred Integration Issue

- Issue: #121
- Depends on: Tasks 2, 3, and 7
- Goal: make the issue state honest after the docs, summary model, and API surface are all updated.
- Default direction for this wave: do not build a serious profiler integration contract here.
- Expected result: either keep #121 explicitly deferred behind later adopter demand, or close/supersede it if the narrowed callback contract is the intended near-term position.
- Initial thread prompt:

```text
Read the plan doc first, then revisit issue #121 after the callback docs are narrowed and the API surface is hardened. Do not add a serious stable callback identity API in this wave. Make the issue state honest: either keep it explicitly deferred behind future adopter demand and post-#125 foundations, or close/supersede it if the narrowed lightweight-callback contract is the intended near-term outcome.
```

## Validation Expectations

Each task should keep the relevant validation honest for its scope:

- Docs/contract alignment: README, `docs/semantics.md`, `docs/design.md`, examples, and install-consumer coverage must match each landed behavior change.
- Summary/MPI work: cover repeated-name tree structure, parent linkage, MPI global result identity across ranks, MPI print/write coverage, rank-at-extrema data, and mismatch diagnostics.
- Runtime/API hardening: cover omitted-`ierr` no-mutation behavior, setter lifecycle checks, procedural/OOP parity, and install-consumer/API-compat validation.
- Performance work: show lookup/allocation improvements without regressing existing correctness coverage.

## Tracking Notes

- Task 1 is the dependency root for the rest of the queue.
- Task 9 is intentionally last because the repo should not promise stronger external integration until the callback docs, summary model, and public API surface are all settled.
- If a later task discovers that a prior locked decision is no longer viable, stop and record a new maintainer decision explicitly rather than silently drifting away from this plan.
