# CSV Schema Reader-Aid Fixtures

These files are tiny hand-written parser smoke fixtures for
`docs/csv-schema.md`. They are not generated-output golden fixtures and do not
broaden the CSV compatibility promise.

Each fixture is intentionally small and highlights one interpretation boundary:

- `local-active-reader-aid.csv`: live local snapshot fields.
- `strict-mpi-reader-aid.csv`: strict MPI fields plus metadata rows.
- `mpi-union-sparse-reader-aid.csv`: sparse MPI participation without
  zero-filling the missing rank.
- `openmp-mixed-epoch-reader-aid.csv`: local OpenMP missing-lane precision is
  unknown for a mixed-epoch aggregate.
- `mpi-openmp-strict-reader-aid.csv`: strict hybrid rank rows.
- `mpi-openmp-union-mixed-epoch-reader-aid.csv`: sparse hybrid participation
  and unknown missing rank/lane sample precision.
