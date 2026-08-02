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


class CodexConfigRootLayoutTest(unittest.TestCase):
    """Codex bind-mounts <root>/.codex read-only, and bubblewrap refuses to
    enforce a read-only path that crosses a writable symlink. A symlinked
    .codex therefore fails EVERY sandboxed command with "cannot enforce
    sandbox read-only path ... because it crosses writable symlink", while
    read-only mode keeps working — which is how it stayed hidden.
    """

    def test_codex_root_is_a_real_directory(self) -> None:
        codex_root = WORKSPACE_ROOT / ".codex"

        self.assertTrue(codex_root.is_dir())
        self.assertFalse(codex_root.is_symlink())

    def test_every_entry_links_into_the_canonical_tree(self) -> None:
        canonical = WORKSPACE_ROOT / "_private/.codex"
        expected = {entry.name: f"../_private/.codex/{entry.name}" for entry in canonical.iterdir()}
        self.assertNotEqual(expected, {}, "_private/.codex is empty — is _private cloned?")

        actual = {
            entry.name: os.readlink(entry) if entry.is_symlink() else None
            for entry in (WORKSPACE_ROOT / ".codex").iterdir()
        }

        self.assertEqual(actual, expected)

    def test_config_resolves_through_the_links(self) -> None:
        config = WORKSPACE_ROOT / ".codex/config.toml"

        self.assertTrue(config.is_symlink())
        self.assertTrue(config.is_file(), "dangling link — Codex would load no project hooks")
        self.assertEqual(config.resolve(), (WORKSPACE_ROOT / "_private/.codex/config.toml").resolve())

    def test_claude_and_kimi_roots_stay_symlinks(self) -> None:
        """The asymmetry with .codex is deliberate, not drift: neither Claude
        Code nor Kimi bind-mounts its config dir, and Claude Code only
        discovers project config at the workspace root.
        """
        for name in (".claude", ".kimi-code"):
            with self.subTest(root=name):
                root = WORKSPACE_ROOT / name

                self.assertTrue(root.is_symlink())
                self.assertEqual(os.readlink(root), f"_private/{name}")


if __name__ == "__main__":
    unittest.main()
