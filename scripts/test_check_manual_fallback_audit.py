#!/usr/bin/env python3

import unittest

from check_manual_fallback_audit import audit_comments


CURRENT_SHA = "a318d358232f9c55b348a155d288e78e183c67af"
OLD_SHA = "0b981ff235726ab93d6739ac5b674be68eb6cb5b"


class ManualFallbackAuditTests(unittest.TestCase):
    def test_warns_when_superseded_disposition_has_no_prior_old_body(self):
        comments = [
            {
                "id": 1,
                "body": (
                    "Manual fallback review was used.\n\n"
                    f"Reviewed PR head SHA: `{CURRENT_SHA}`\n\n"
                    "## Software Review\n\nNo findings.\n"
                ),
            },
            {
                "id": 2,
                "body": (
                    "Manual fallback disposition for superseded-head findings:\n\n"
                    "- Agreed and fixed a missing test."
                ),
            },
        ]

        warnings = audit_comments(comments, CURRENT_SHA)

        self.assertEqual(1, len(warnings))
        self.assertIn("superseded-head findings", warnings[0])

    def test_accepts_prior_superseded_reviewer_body(self):
        comments = [
            {
                "id": 1,
                "body": (
                    "Manual fallback review record\n\n"
                    f"Reviewed PR head SHA: `{OLD_SHA}`\n"
                    "Role: test-quality\n"
                    "<!-- codex-manual-fallback-review "
                    f"role=test-quality sha={OLD_SHA} wave=1 "
                    "outcome=findings source=fresh-context-subagent -->\n\n"
                    "## Test Quality Review\n\nFinding: missing test."
                ),
            },
            {
                "id": 2,
                "body": (
                    "Manual fallback disposition for superseded-head findings:\n\n"
                    "- Agreed and fixed the missing test."
                ),
            },
        ]

        warnings = audit_comments(comments, CURRENT_SHA)

        self.assertEqual([], warnings)

    def test_later_superseded_body_does_not_satisfy_prior_disposition(self):
        comments = [
            {
                "id": 1,
                "body": (
                    "Manual fallback disposition for superseded-head findings:\n\n"
                    "- Agreed and fixed a missing test."
                ),
            },
            {
                "id": 2,
                "body": (
                    "Manual fallback review record\n\n"
                    f"Reviewed PR head SHA: `{OLD_SHA}`\n\n"
                    "## Test Quality Review\n\nFinding: missing test."
                ),
            },
        ]

        warnings = audit_comments(comments, CURRENT_SHA)

        self.assertEqual(1, len(warnings))


if __name__ == "__main__":
    unittest.main()
