# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Behaviour tests for `just/claude-layout-lib.sh::check_claude_layout`.

The function both *gates* `just session-end` and *deletes* what it judges
to be scratch, so a false positive is expensive twice over: it fails a
green session, and its printed remedy is `rm -rf` on real repo content.
Each case below builds a throwaway workspace and runs the real function
against it.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()
LIB = WORKSPACE_ROOT / "just/claude-layout-lib.sh"


def run_check(workspace: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-c", f'source "{LIB}"; check_claude_layout'],
        cwd=workspace,
        capture_output=True,
        text=True,
        check=False,
    )


def make_workspace(tmp: str) -> Path:
    workspace = Path(tmp)
    (workspace / "_private/.claude").mkdir(parents=True)
    (workspace / "_private/.claude/settings.json").write_text("{}\n", encoding="utf-8")
    (workspace / ".claude").symlink_to("_private/.claude")
    return workspace


def write(path: Path, text: str = "x\n") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ClaudeLayoutTest(unittest.TestCase):
    def test_sound_layout_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_check(make_workspace(tmp))

            self.assertEqual(result.returncode, 0, result.stdout)

    def test_worktree_config_tree_is_not_a_stray(self) -> None:
        """A worktree of _private carries the canonical .claude tree."""
        with tempfile.TemporaryDirectory() as tmp:
            workspace = make_workspace(tmp)
            checked_out = workspace / ".worktrees/investigation--x/_private/.claude"
            write(checked_out / "settings.json", "{}\n")

            result = run_check(workspace)

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("stray", result.stdout)
            self.assertTrue(checked_out.is_dir(), "worktree content was deleted")

    def test_stray_with_files_fails_and_is_kept(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = make_workspace(tmp)
            scratch = workspace / "core/.claude/agent-memory"
            write(scratch / "notes.md")

            result = run_check(workspace)

            self.assertEqual(result.returncode, 1)
            self.assertIn("stray ./core/.claude", result.stdout)
            self.assertTrue(scratch.is_dir(), "a stray with files needs a human")

    def test_empty_stray_is_removed_silently(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = make_workspace(tmp)
            empty = workspace / "relay/.claude"
            empty.mkdir(parents=True)

            result = run_check(workspace)

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertFalse(empty.exists())


if __name__ == "__main__":
    unittest.main()
