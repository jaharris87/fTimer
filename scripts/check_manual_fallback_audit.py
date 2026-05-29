#!/usr/bin/env python3
"""Warn about incomplete manual-fallback review history in PR comments."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REVIEW_HEADINGS = (
    "## Software Review",
    "## Methodology Review",
    "## Red Team Review",
    "## Docs / Contract Review",
    "## Test Quality Review",
    "## Build / Portability Review",
    "## API / Compatibility Review",
    "## MPI Safety Review",
)

REVIEWED_SHA_RE = re.compile(
    r"Reviewed\s+(?:PR\s+)?head\s+SHA:\s*`?([0-9a-f]{7,40})",
    re.IGNORECASE,
)
FALLBACK_MARKER_SHA_RE = re.compile(
    r"codex-manual-fallback-review\b[^>]*\bsha=([0-9a-f]{7,40})",
    re.IGNORECASE,
)
SUPERSEDED_DISPOSITION_RE = re.compile(
    r"manual\s+fallback\s+disposition[\s\S]*superseded[-\s]+head\s+findings",
    re.IGNORECASE,
)


def same_head(lhs: str, rhs: str) -> bool:
    lhs = lhs.lower()
    rhs = rhs.lower()
    return lhs.startswith(rhs) or rhs.startswith(lhs)


def reviewed_shas(body: str) -> list[str]:
    shas = FALLBACK_MARKER_SHA_RE.findall(body)
    shas.extend(REVIEWED_SHA_RE.findall(body))
    seen: set[str] = set()
    result: list[str] = []
    for sha in shas:
        normalized = sha.lower()
        if normalized not in seen:
            seen.add(normalized)
            result.append(normalized)
    return result


def looks_like_fallback_review_body(body: str) -> bool:
    lower_body = body.lower()
    has_explicit_marker = "codex-manual-fallback-review" in lower_body
    has_fallback_context = "manual fallback" in lower_body
    has_review_heading = any(heading in body for heading in REVIEW_HEADINGS)
    return has_explicit_marker or (
        has_fallback_context and has_review_heading and bool(reviewed_shas(body))
    )


def audit_comments(comments: list[dict[str, Any]], head_sha: str) -> list[str]:
    warnings: list[str] = []
    prior_review_shas: list[str] = []

    for index, comment in enumerate(comments, start=1):
        body = comment.get("body") or ""
        comment_id = comment.get("id", f"#{index}")
        comment_url = comment.get("url", "")

        if SUPERSEDED_DISPOSITION_RE.search(body):
            prior_superseded = [
                sha for sha in prior_review_shas if not same_head(sha, head_sha)
            ]
            if not prior_superseded:
                location = f"comment {comment_id}"
                if comment_url:
                    location = f"{location} ({comment_url})"
                warnings.append(
                    f"{location} references manual fallback superseded-head "
                    "findings, but no earlier full fallback reviewer-body "
                    "comment identifies a reviewed head SHA different from "
                    f"the current head {head_sha}."
                )

        if looks_like_fallback_review_body(body):
            prior_review_shas.extend(reviewed_shas(body))

    return warnings


def write_summary(summary_file: Path, warnings: list[str]) -> None:
    with summary_file.open("a", encoding="utf-8") as handle:
        handle.write("\n### Manual fallback audit warnings\n\n")
        if not warnings:
            handle.write("- None detected.\n")
            return
        for warning in warnings:
            handle.write(f"- {warning}\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Warn when manual fallback dispositions reference superseded-head "
            "findings without earlier visible reviewer-body records."
        )
    )
    parser.add_argument("--comments-json", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--summary-file")
    parser.add_argument("--github-warning-format", action="store_true")
    parser.add_argument("--fail-on-warning", action="store_true")
    args = parser.parse_args()

    with open(args.comments_json, encoding="utf-8") as handle:
        comments = json.load(handle)

    warnings = audit_comments(comments, args.head_sha)

    for warning in warnings:
        if args.github_warning_format:
            print(f"::warning::{warning}")
        else:
            print(f"WARNING: {warning}")

    if args.summary_file:
        write_summary(Path(args.summary_file), warnings)

    if warnings and args.fail_on_warning:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
