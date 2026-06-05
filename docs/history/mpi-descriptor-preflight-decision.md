> **When to read this:** When changing strict `mpi_summary()` descriptor consistency checks, mismatch diagnostics, or the collective pattern used before MPI summary reductions.

# MPI Descriptor Preflight Decision

Issue #151 revisited whether strict `mpi_summary()` should keep allgathering descriptor hashes from every rank and whether exact descriptor diagnostics are warranted.

## Decision

Replace the successful-path `MPI_Allgather` of every rank's descriptor hashes with a rank-0 reference hash broadcast plus an all-rank mismatch reduction. If a mismatch is detected, gather one integer mismatch flag per rank so the omitted-`ierr` diagnostic can still report communicator-local ranks that disagree with rank 0, bounded by the diagnostic buffer and with truncation marked when the list does not fit.

Keep strict `mpi_summary()` hash-based by default. Do not exchange exact descriptor strings on every successful summary call.

## Rationale

The previous preflight allocated `gathered_hashes(2, nprocs)` and allgathered two 64-bit hash values from every rank. That was simple and produced useful rank-list diagnostics, but it made every successful summary pay O(P) temporary storage per rank for a preflight whose normal answer is just "all ranks match."

The replacement preserves the same safety model: every rank still compares the same two hashes built from the canonical, sorted, length-prefixed descriptor list. It only changes the collective shape:

- successful path: broadcast two `integer(int64)` hash values from rank 0, then allreduce one integer mismatch flag
- mismatch path: after failure is already known, allgather one integer mismatch flag per rank for diagnostics

This keeps successful summaries O(1) in rank-count temporary storage per rank for the preflight. The tradeoff is one additional small collective on the successful path, but the message payload is constant-size and `mpi_summary()` already performs multiple subsequent allreduces for the summary fields. For large P, avoiding per-rank replicated hash lists is the better default.

## Exact Descriptor Diagnostics

Exact descriptor diagnostics are useful, but they should be a mismatch-only debug feature or a future explicit diagnostic mode rather than part of the default successful path. Exact descriptor exchange can scale with entry count and encoded path length, and the current public error-reporting path is a short diagnostic string rather than a structured diff surface.

The current recommendation is:

- keep exact descriptor strings local during normal preflight
- preserve bounded disagreeing-rank diagnostics in the default omitted-`ierr` path
- consider a future mismatch-only exact diagnostic mode that exchanges rank-0 and one or more disagreeing descriptor lists, then reports a bounded first-difference summary

That future mode should be tested separately because useful exact output needs truncation, first-difference selection, and a clear contract for very large timer trees.

## Validation

The existing MPI consistency tests cover missing, extra, renamed, hierarchy, and long-name descriptor mismatches. The four-rank diagnostic tests also check that the omitted-`ierr` path reports ranks that disagree with rank 0, preserves communicator-local rank numbering for split communicators, and marks truncated rank-list diagnostics.
