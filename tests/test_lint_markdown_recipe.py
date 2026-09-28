# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""`just lint-markdown` must reject what the push gate rejects.

vauchi/private#417: the recipe loaded only the line-length rule, while
gate-push.sh also loads the VDC01 no-abs-paths rule — so it reported
"All markdown checks passed." on a file the gate then refused to push
(2026-09-28, operational-notes-infrastructure.md).

Run: python3 tests/test_lint_markdown_recipe.py <workspace-root>
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()


@unittest.skipUnless(shutil.which("markdownlint"), "markdownlint not installed")
class LintMarkdownRecipeTest(unittest.TestCase):
    def lint(self, body: str) -> subprocess.CompletedProcess[str]:
        # Inside the workspace: markdownlint rejects paths outside its cwd.
        directory = Path(tempfile.mkdtemp(prefix=".lint-markdown-test-", dir=WORKSPACE_ROOT))
        self.addCleanup(shutil.rmtree, directory)
        page = directory / "page.md"
        page.write_text(f"# Page\n\n{body}\n")
        return subprocess.run(
            ["just", "--justfile", str(WORKSPACE_ROOT / "justfile"), "lint-markdown", str(page)],
            cwd=WORKSPACE_ROOT, capture_output=True, text=True,
        )

    def test_a_machine_local_path_fails_like_the_push_gate(self) -> None:
        result = self.lint("The runner lives in `/Users/gitlab-runner/builds`.")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("VDC01", result.stdout + result.stderr)

    def test_a_clean_page_passes(self) -> None:
        result = self.lint("The runner lives in `~gitlab-runner/builds`.")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All markdown checks passed.", result.stdout)


if __name__ == "__main__":
    unittest.main()
