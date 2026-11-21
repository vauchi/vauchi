# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
"""The public creation recipe preserves arguments and helper failures."""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class CreateRepoRecipeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.workspace = Path(self.directory.name)
        shutil.copyfile(ROOT / "justfile", self.workspace / "justfile")
        shutil.copytree(ROOT / "just", self.workspace / "just")
        self.helper = self.workspace / "scripts/scripts/create-repo.py"
        self.helper.parent.mkdir(parents=True)

    def run_recipe(self, *args):
        return subprocess.run(
            ["just", "create-repo", *args], cwd=self.workspace,
            capture_output=True, text=True, check=False,
        )

    def test_forwards_description_as_data_without_shell_execution(self):
        self.helper.write_text("import json,sys\nprint(json.dumps(sys.argv[1:]))\n", encoding="utf-8")
        description = 'A "quote" $(touch injected) `touch injected2`'
        result = self.run_recipe("apple-display", "--description", description)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["apple-display", "--description", description])
        self.assertFalse((self.workspace / "injected").exists())
        self.assertFalse((self.workspace / "injected2").exists())

    def test_propagates_helper_failure(self):
        self.helper.write_text("import sys\nprint('policy mismatch', file=sys.stderr)\nsys.exit(7)\n", encoding="utf-8")
        result = self.run_recipe("apple-display")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("policy mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
