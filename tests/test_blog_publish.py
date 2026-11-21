# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PUBLISH_SCRIPT = Path(sys.argv.pop(1)).resolve()

DRAFT = """+++
title = "A card for your people"
description = \"\"\"
Swap once, stay in touch.\"\"\"
date = 2026-01-01
slug = "a-card-for-your-people"
draft = true
+++

The body keeps date = 2026-01-01 and draft = true as plain text.
"""


class BlogPublishTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        root = Path(self.temporary_directory.name)
        self.drafts = root / "drafts"
        self.content = root / "content"
        self.drafts.mkdir()
        self.content.mkdir()

    def publish(self, slug: str = "a-card-for-your-people") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(PUBLISH_SCRIPT), str(self.drafts), str(self.content), slug, "2026-10-26"],
            capture_output=True,
            text=True,
            check=False,
        )

    def write_draft(self, text: str = DRAFT, name: str = "2026-07-16-a-card-for-your-people.md") -> None:
        (self.drafts / name).write_text(text, encoding="utf-8")

    def test_publishing_dates_the_post_and_clears_the_draft_flag_in_front_matter_only(self):
        self.write_draft()
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        published = self.content / "a-card-for-your-people.md"
        self.assertEqual(result.stdout.strip(), str(published))
        self.assertEqual(
            published.read_text(encoding="utf-8"),
            DRAFT.replace("date = 2026-01-01\nslug", "date = 2026-10-26\nslug").replace(
                "draft = true\n+++", "+++"
            ),
        )

    def test_publishing_drops_spdx_comments_before_the_front_matter(self):
        # REUSE-IgnoreStart
        self.write_draft(
            "<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->\n"
            "<!-- SPDX-License-Identifier: GPL-3.0-or-later -->\n\n" + DRAFT
        )
        # REUSE-IgnoreEnd
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.content / "a-card-for-your-people.md").read_text(encoding="utf-8").startswith("+++\n"))

    def test_internal_references_never_reach_the_public_repo(self):
        for leak in ("see _private/docs/x.md", "per ADR-057", "landed in website!99", "the .claude config"):
            with self.subTest(leak=leak):
                self.write_draft(DRAFT + leak + "\n")
                result = self.publish()
                self.assertEqual(result.returncode, 1)
                self.assertIn("internal reference", result.stderr)
                self.assertEqual(list(self.content.iterdir()), [])

    def test_an_unknown_slug_is_refused(self):
        self.write_draft()
        result = self.publish("no-such-post")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no draft with slug no-such-post", result.stderr)

    def test_a_slug_that_is_not_a_plain_name_is_refused(self):
        self.write_draft()
        for slug in ("../escape", "a b", "", "Upper"):
            with self.subTest(slug=slug):
                result = self.publish(slug)
                self.assertEqual(result.returncode, 1)
                self.assertIn("slug must be lowercase letters, digits and dashes", result.stderr)

    def test_an_existing_post_is_never_overwritten(self):
        self.write_draft()
        existing = self.content / "a-card-for-your-people.md"
        existing.write_text("published already\n", encoding="utf-8")
        result = self.publish()
        self.assertEqual(result.returncode, 1)
        self.assertIn("already published", result.stderr)
        self.assertEqual(existing.read_text(encoding="utf-8"), "published already\n")


if __name__ == "__main__":
    unittest.main()
