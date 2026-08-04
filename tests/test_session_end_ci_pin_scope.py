# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Regression coverage for project-wide CI template-pin checks."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETUP_JUST = ROOT / "just" / "setup.just"


class SessionEndCiPinScopeTests(unittest.TestCase):
    """Protect the project-wide scope of the local alignment gate."""

    def test_session_end_discovers_every_pipeline_config(self) -> None:
        recipe = SETUP_JUST.read_text(encoding="utf-8")
        stale_pin_block = recipe.split("# VSP01:", 1)[1].split("# VFL01:", 1)[0]

        self.assertIn("find .", stale_pin_block)
        self.assertIn("-name .gitlab-ci.yml", stale_pin_block)
        self.assertIn("-path './.worktrees' -prune", stale_pin_block)
        self.assertNotIn(
            "_private/.gitlab-ci.yml .gitlab-ci.yml",
            stale_pin_block,
        )


if __name__ == "__main__":
    unittest.main()
