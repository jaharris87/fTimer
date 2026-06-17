# Security Policy

fTimer is a timing library, not a security boundary. Still, maintainers want
reports about vulnerabilities or release-integrity risks handled privately
before public disclosure.

## Supported Versions

For v1.0 and later, security fixes normally target the latest stable release
line and current `main` unless a maintainer documents another patch policy for a
specific release. Pre-1.0 tags and snapshots remain best-effort only.

## Reporting A Vulnerability

Do not include exploit details, sensitive logs, credentials, private repository
data, or embargoed information in a public issue.

Preferred reporting path:

1. Use GitHub private vulnerability reporting if it is available for this
   repository.
2. If private vulnerability reporting is not available, open a public issue with
   no sensitive details that asks the maintainer to establish a private contact
   path.

Include privately:

- affected fTimer version or commit,
- supported workflow involved, such as serial, MPI, OpenMP, install/package, or
  CI/release infrastructure,
- reproduction steps or proof of concept,
- expected impact,
- whether the report is already public anywhere else.

## Handling Expectations

Maintainers will triage whether the report is a vulnerability, a release
integrity issue, a normal bug, or out of scope. Valid security fixes should land
through a scoped PR with appropriate validation and release notes. Public
disclosure should wait until a fix or maintainer disposition is available unless
the issue is already public.
