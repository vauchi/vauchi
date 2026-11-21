# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just plan-validate`: a plan it cannot check is an error.

vauchi/private#686: when the markdown-plan parser could not be imported,
each file's traceback was printed as its result and the recipe still
reported `Errors: 0` and exited 0.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

PLAN = "# Plan\n\n- [x] First step\n- [ ] Second step\n"


def run_validate(workspace: Path, target: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["just", "plan-validate", target],
        cwd=workspace,
        capture_output=True,
        text=True,
    )


class PlanValidateRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmp.name)
        shutil.copyfile(ROOT / "justfile", self.workspace / "justfile")
        shutil.copytree(ROOT / "just", self.workspace / "just")
        self.plans = self.workspace / "plans"
        self.plans.mkdir()
        (self.plans / "good.plan.md").write_text(PLAN, encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def with_parser(self) -> None:
        source = ROOT / "utils/markdown-plan/python/src"
        if not source.is_dir():
            self.skipTest("utils/markdown-plan is not cloned in this workspace")
        shutil.copytree(source, self.workspace / "utils/markdown-plan/python/src")

    def test_a_plan_the_parser_cannot_be_loaded_for_counts_as_an_error(self) -> None:
        result = run_validate(self.workspace, "plans")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Checked: 1 file(s), Errors: 1", result.stdout)

    def test_a_valid_plan_passes(self) -> None:
        self.with_parser()

        result = run_validate(self.workspace, "plans")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK: 1/2 tasks done (1 remaining)", result.stdout)
        self.assertIn("Checked: 1 file(s), Errors: 0", result.stdout)

    def test_a_plan_path_with_a_quote_is_read_not_run(self) -> None:
        self.with_parser()
        (self.plans / "good.plan.md").rename(self.plans / "it's.plan.md")

        result = run_validate(self.workspace, "plans")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK: 1/2 tasks done (1 remaining)", result.stdout)


if __name__ == "__main__":
    unittest.main()
