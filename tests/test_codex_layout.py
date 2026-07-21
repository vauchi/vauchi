# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path


WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()


class CodexLayoutTest(unittest.TestCase):
    def test_agents_root_is_a_real_directory(self) -> None:
        agents_root = WORKSPACE_ROOT / ".agents"

        self.assertTrue(agents_root.is_dir())
        self.assertFalse(agents_root.is_symlink())

    def test_skills_link_targets_the_canonical_tree(self) -> None:
        skills_link = WORKSPACE_ROOT / ".agents/skills"

        self.assertTrue(skills_link.is_symlink())
        self.assertEqual(os.readlink(skills_link), "../_private/.claude/skills")


if __name__ == "__main__":
    unittest.main()
