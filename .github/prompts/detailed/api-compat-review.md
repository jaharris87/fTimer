## API / Compatibility Review

You are performing a long-form review as an API and compatibility reviewer. The subject may be a pull request, a feature branch, or current `main`. Your job is to find changes or existing conditions that make the public surface inconsistent, surprising, or accidentally incompatible. Focus on user-visible behavior, interface stability, and parity between the procedural and OOP APIs - not code style issues.

If no explicit diff is provided, interpret references to "this diff" below as the reviewed codebase state.

### Required Questions

Answer each of these explicitly. If a question is not applicable, say so and why.

1. **Does this diff change the public API surface?** (procedure names, signatures, keyword arguments, defaults, exported symbols, package/export behavior)
2. **Are procedural and OOP interfaces still behaviorally aligned?** If both surfaces expose the same feature, do they behave the same way?
3. **Are argument-passing conventions safe and unsurprising?** Could positional vs keyword usage become ambiguous or incompatible?
4. **Does this diff preserve backward compatibility where expected?** If not, is the breakage explicit, documented, and justified?
5. **Are installation and package-consumer interfaces still correct?** (`use ftimer`, `use ftimer_core`, `find_package(fTimer)`, exported targets, module installation)

### What to Look For

- **Surface drift**: A method exists in the OOP API but not in the procedural API, or vice versa, without a deliberate reason.
- **Signature mismatches**: Wrapper argument order, optional arguments, defaults, or keyword names differ from the underlying implementation.
- **Compatibility traps**: Existing call sites could silently do the wrong thing because of overloaded or ambiguous integer/keyword positional usage.
- **Export mistakes**: Public symbols missing from modules, inconsistent `public` declarations, or package/export/install drift.
- **Documentation mismatch**: README/examples/docs describe an API shape that the code does not actually provide.
- **Thin-wrapper violations**: Procedural wrappers add semantics or defaults that differ from the OOP core without explicit intent.

### How to Report

- Cite the specific file, procedure, and interface detail for each finding.
- Classify each finding: **api break**, **compatibility risk**, **parity gap**, **package/export issue**, or **design concern**.
- Explain the user impact concretely: what existing or expected call pattern would break, become ambiguous, or behave differently.
- **Begin your response with "## API / Compatibility Review" so it is clear which review type this is.**
