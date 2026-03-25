> **When to read this**
>
> Read this file when creating, scoping, refining, or linking issues before implementation begins.
>
> Use it to define scope, acceptance criteria, and issue structure before opening or updating a PR.
>
> Do **not** load this by default once implementation is already underway unless the task needs to be re-scoped or split.

# Issue Intake Workflow

This document covers how to create, scope, and prepare work items before implementation begins.

## Rule: Start From an Issue

For every scoped piece of work:

- create a new GitHub issue, or
- explicitly link the work to an existing issue

Do not treat a PR alone as the planning artifact.

## Good Issue Scope

A good issue should be:

- specific enough to implement in one focused PR
- large enough to be meaningful
- small enough that review remains tractable

Prefer issues that define:

- the problem
- why it matters
- the intended scope
- key affected files or modules if known
- acceptance criteria

## Recommended Issue Structure

Use this structure when practical:

```text
Problem
Why it matters
Scope
Out of scope
Acceptance criteria
Notes / references
```

## Scope Discipline

Before implementation starts, make scope decisions explicit:

* What behavior is actually changing?
* What behavior must remain unchanged?
* Which docs/tests are expected to change?
* Does the work require architecture discussion, or is it local?
* Is the change phase-bounded, or does it risk pulling future work forward?

If the issue is likely to expand substantially during implementation, split it before opening the PR.

## Relationship To Other Tracking

When applicable, link the issue to:

* parent or umbrella issues
* prior review findings
* deferred follow-up issues
* milestone or phase tracking

## Before Handing Off to Implementation

Make sure the issue identifies enough context to start with a minimal working set:

* touched source area
* likely touched tests
* whether runtime contract changes are expected
* whether public docs are likely affected
