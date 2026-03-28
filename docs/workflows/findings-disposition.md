> **When to read this:** When responding to review findings, deciding on deferrals, checking merge-blocking criteria, or closing out a PR. Do not load this during implementation or before reviews have arrived.

# Findings Disposition

## Responding To Findings

For every finding in every review (native, fallback, or manual), post a reply on the PR in one of these categories:

- Agree and fix
- Disagree with evidence
- Defer with reason

Every finding must be addressed explicitly.

When responding:

- cite the fix commit when you agree and fix
- cite code/tests/docs when you disagree
- explain scope clearly when you defer
- if the returned review omits a classification, assign one explicitly in your disposition comment using the repo categories below

After replying:

- resolve the review thread
- once a review role is actually satisfied for the current head SHA, post a coverage marker comment so `Codex Review Coverage` can pass
- verify whether any unresolved review threads remain
- post coverage markers only from a trusted repo commenter account with repo `write`, `maintain`, or `admin` permission, or from an explicitly allowed bot account; untrusted PR-author comments do not satisfy the coverage gate

Coverage marker examples:

```text
Codex review coverage: software covered for <HEAD_SHA> via native review.
<!-- codex-review-coverage role=software sha=<HEAD_SHA> status=covered source=native -->

Codex review coverage: test-quality covered for <HEAD_SHA> via manual fallback.
<!-- codex-review-coverage role=test-quality sha=<HEAD_SHA> status=covered source=manual-fallback -->

Codex review coverage: red-team waived for <HEAD_SHA> because native review was unavailable and the maintainer accepted the risk.
<!-- codex-review-coverage role=red-team sha=<HEAD_SHA> status=waived source=maintainer-override -->
```

## Deferring Findings Properly

A deferred finding is an explicit decision to accept limited risk now and track the work for later. It is not a way to avoid addressing a finding.

**When deferral is appropriate:**

- the finding is real or plausible enough to acknowledge
- it is not merge-blocking under this guide
- fixing it in the current PR would materially expand scope, delay the intended work, or mix unrelated changes
- there is a clear follow-up path

**What deferral requires:**

1. Post a PR disposition reply that states:
   - what the finding is
   - why it is not being fixed in this PR
   - the current risk or impact
   - the intended follow-up
   - whether it is acceptable risk for merge, or release-blocking but not merge-blocking

2. Create a follow-up GitHub issue when the deferred item represents real engineering work. Link both ways:
   - in the PR reply: `Deferred to #NN`
   - in the issue body: `Deferred from PR #NN`

3. Update any parent, umbrella, or audit issue with a disposition line such as:
   - `fixed`
   - `deferred to #NN`
   - `not applicable`
   - `disagreed with evidence`

A deferred finding is not considered handled until the PR disposition comment and any required follow-up issue both exist.

**Rule of thumb for whether to open an issue:**

- If the deferred item requires code, tests, docs, validation, or design work, open an issue.
- If no code, docs, tests, or design work is expected to follow, it can remain in the PR discussion.
- If it came from a formal software, methodology, or red-team review and is a real follow-up item, default to opening an issue.

**Preferred wording.** Avoid vague language like "will do later." Use specific language:

> Deferred to #52 because this PR is scoped to packaging stability; the identified hardening work is real but non-blocking for merge and has explicit acceptance criteria in the follow-up issue.

**Recommended PR disposition template for deferred findings:**

```
Disposition: Deferred to #NN
Finding: <one-line summary of the finding>
Why not fixed in this PR: <scope, sequencing, or mix-of-concerns reason>
Current risk: <low / medium / high — brief rationale>
Merge status: non-merge-blocking / release-blocking but not merge-blocking
Follow-up: #NN — <one-line description of what the issue tracks>
```

**Recommended follow-up issue skeleton:**

```
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

- bug
- leakage
- silent wrong answer

remains unresolved without either a fix or a disagreement backed by evidence.

Findings classified as `bug`, `leakage`, or `silent wrong answer` should not be deferred for merge unless the maintainer documents why the finding is not valid, not applicable to this PR (e.g., pre-existing and not introduced here), or not applicable in this context.

A deferred finding may remain open at merge time only if it is explicitly recorded as non-merge-blocking and has durable follow-up tracking when required (see [Deferring Findings Properly](#deferring-findings-properly)).

Findings classified as nit, design concern, or methodology concern do not block merge unless the user decides otherwise.

## Closeout To The User

After handling the reviews, report:

- how many findings appeared per review type
- what was fixed
- what was disagreed with and why
- what was deferred, including the linked follow-up issue number for each deferred finding
- whether any deferred item is release-blocking but not merge-blocking
- whether any merge-blocking findings remain
- whether `Codex Review Coverage` is now satisfied for the current head SHA
