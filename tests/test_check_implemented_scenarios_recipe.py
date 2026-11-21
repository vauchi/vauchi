# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just check-implemented-scenarios`: it fails what CI fails.

vauchi/private#833: the features CI job also passes `--dangling-baseline`,
so an `@scenario` annotation naming no scenario failed CI while the local
recipe passed.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOS = ("core cli tui e2e relay ohttp-relay gtk-display qt-display windows "
         "web-demo ios macos android").split()

FEATURE = """Feature: Navigation

  @implemented
  Scenario: Open my card
    Given the app is unlocked
"""


class CheckImplementedScenariosRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.workspace = Path(self._tmp.name)
        shutil.copyfile(ROOT / "justfile", self.workspace / "justfile")
        shutil.copytree(ROOT / "just", self.workspace / "just")
        checker = self.workspace / "scripts/scripts/check-implemented-scenarios.py"
        checker.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/scripts/check-implemented-scenarios.py", checker)
        features = self.workspace / "features"
        features.mkdir()
        (features / "navigation.feature").write_text(FEATURE, encoding="utf-8")
        (features / "implemented-untested.baseline").write_text("", encoding="utf-8")
        (features / "dangling-annotations.baseline").write_text("", encoding="utf-8")
        for repo in REPOS:
            (self.workspace / repo).mkdir()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def annotate(self, *scenarios: str) -> None:
        (self.workspace / "core/lib.rs").write_text("".join(
            f"// @scenario: {scenario}\n#[test]\nfn test_{n}() {{}}\n"
            for n, scenario in enumerate(scenarios)), encoding="utf-8")

    def run_check(self) -> subprocess.CompletedProcess:
        return subprocess.run(["just", "check-implemented-scenarios"], cwd=self.workspace,
                              capture_output=True, text=True)

    def test_an_annotation_naming_no_scenario_fails_as_it_does_in_ci(self) -> None:
        self.annotate("navigation :: Open my card", "navigation :: Open my business card")

        result = self.run_check()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("naming no scenario:\n  navigation :: open my business card", result.stdout)

    def test_an_annotation_naming_a_scenario_passes(self) -> None:
        self.annotate("navigation :: Open my card")

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
