> **When to read this**
>
> Read this file when responding to review findings, deciding whether to fix/disagree/defer, enforcing merge-blocking rules, or closing out review.
>
> Use it only after actual findings exist or when preparing final PR disposition.
>
> Do **not** load this by default during implementation or early PR setup.

# Findings Disposition Workflow

This document covers how to respond to findings, defer work properly, enforce merge-blocking rules, and close out review.

## Every Finding Must Be Addressed Explicitly

For every finding in every review path:

- native review
- fallback manual review
- targeted manual review

post a reply on the PR in one of these categories:

- Agree and fix
- Disagree with evidence
- Defer with reason

Do not leave substantive findings unclassified or implicit.

## Response Expectations

When responding:

- cite the fix commit when you agree and fix
- cite code, tests, or docs when you disagree
- explain scope and risk clearly when you defer
- if the review omitted a classification, assign one explicitly in your disposition comment using the repository categories below

After replying:

- resolve the related review thread
- verify whether any unresolved review threads remain

## Deferring Findings Properly

A deferred finding is an explicit decision to accept limited risk now and track follow-up work later.
It is not a way to avoid addressing a finding.

### Deferral Is Appropriate When

- the finding is real or plausible enough to acknowledge
- it is not merge-blocking under this guide
- fixing it in the current PR would materially expand scope, delay intended work, or mix unrelated concerns
- there is a clear follow-up path

### Deferral Requires

1. A PR disposition reply that states:
   - what the finding is
   - why it is not being fixed in this PR
   - the current risk or impact
   - the intended follow-up
   - whether it is acceptable risk for merge, or release-blocking but not merge-blocking

2. A follow-up GitHub issue when the deferred item represents real engineering work.
   Link both ways:
   - in the PR reply: `Deferred to #NN`
   - in the issue body: `Deferred from PR #NN`

3. Updating any parent, umbrella, or audit issue with a disposition line such as:
   - `fixed`
   - `deferred to #NN`
   - `not applicable`
   - `disagreed with evidence`

A deferred finding is not fully handled until the PR disposition comment and any required follow-up issue both exist.

## Rule Of Thumb For Opening A Follow-Up Issue

- If the deferred item requires code, tests, docs, validation, or design work, open an issue.
- If no real follow-up work is expected, it can remain in PR discussion only.
- If it came from a formal software, methodology, or red-team review and is a real follow-up item, default to opening an issue.

## Recommended Deferred-Finding Template

```text
Disposition: Deferred to #NN
Finding: <one-line summary of the finding>
Why not fixed in this PR: <scope, sequencing, or mix-of-concerns reason>
Current risk: <low / medium / high — brief rationale>
Merge status: non-merge-blocking / release-blocking but not merge-blocking
Follow-up: #NN — <one-line description of what the issue tracks>
```

## Recommended Follow-Up Issue Skeleton

```text
Deferred from PR #NN
Scope: <what area of the code or design this covers>
Why deferred: <brief reason — scope, sequencing, risk level>
Risk / impact: <what could go wrong if this is not addressed>
Acceptance criteria:
- [ ] <specific, verifiable condition>
- [ ] <specific, verifiable condition>
```

## Merge-Blocking Criteria

Do not merge the PR if any finding classified as:

* bug
* leakage
* silent wrong answer

remains unresolved without either:

* a fix, or
* a disagreement backed by evidence

Findings classified as `bug`, `leakage`, or `silent wrong answer` should not be deferred for merge unless the maintainer documents why the finding is not valid, not applicable to this PR, or not applicable in this context.

A deferred finding may remain open at merge time only if it is explicitly recorded as non-merge-blocking and has durable follow-up tracking when required.

Findings classified as nit, design concern, or methodology concern do not block merge unless the maintainer decides otherwise.

## Closeout To The User

After handling the reviews, report:

* how many findings appeared per review type
* what was fixed
* what was disagreed with and why
* what was deferred, including linked follow-up issue numbers
* whether any deferred item is release-blocking but not merge-blocking
* whether any merge-blocking findings remain