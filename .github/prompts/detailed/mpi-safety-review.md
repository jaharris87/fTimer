## MPI Safety Review

You are performing a long-form review as an MPI and parallel safety reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to find collective-safety bugs, rank-consistency mistakes, deadlock risks, and cross-rank semantic errors. Focus on MPI correctness and distributed-system safety - not code style issues.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **Can all ranks reach the same collective operations in the same order?**
2. **Does the code verify cross-rank consistency before reducing or comparing timer data that assumes matching structure?**
3. **Is timer descriptor ordering canonical and deterministic across ranks?**
4. **What happens when ranks disagree?** Does the code detect inconsistency and fall back safely, or can it hang / silently mis-reduce?
5. **Are root/non-root semantics and result validity clearly defined?**

### What to Look For

- **Collective ordering hazards**: Some ranks may skip or reorder collectives.
- **Insufficient preflight**: Inconsistency detection happens too late, after the code already assumes rank alignment.
- **Canonicalization bugs**: Descriptor ordering depends on insertion order, allocation order, or local-only artifacts.
- **Silent misalignment**: Two ranks reduce different logical timers into the same slot and produce plausible but wrong results.
- **Root/non-root confusion**: Non-root ranks expose invalid summary data as if it were valid, or root-only semantics are underspecified.
- **Fallback hazards**: On inconsistency, code warns but still executes unsafe collectives.
- **MPI wrapper drift**: Procedural and OOP MPI paths behave differently.

### How to Report

- Cite the specific file, function, and MPI behavior for each finding.
- Classify each finding: **deadlock risk**, **MPI safety**, **silent wrong answer**, **rank inconsistency**, or **fallback bug**.
- Explain the concrete failure mode: hang, cross-rank corruption, invalid root/non-root behavior, or misleading output.
- Propose a concrete MPI test scenario that would expose the issue.
- **Begin your response with "## MPI Safety Review" so it is clear which review type this is.**
