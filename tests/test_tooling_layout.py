# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Behaviour tests for `just/tooling-layout-lib.sh::check_tooling_layout`.

The tools and forks live under utils/ and come from the vauchi/utils
subgroup (private#1034). A slot set up before the move keeps its clones at
the workspace root with the old personal-namespace remotes, and nothing
else notices: the hooks and recipes simply stop seeing the tool. Each case
builds a throwaway workspace and runs the real function against it.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()
LIB = WORKSPACE_ROOT / "just/tooling-layout-lib.sh"
ENTRIES = [
    "git@gitlab.com:vauchi/utils/drift-detector.git,utils/drift-detector",
    "git@gitlab.com:vauchi/utils/rqrr.git,utils/rqrr",
]


def run_check(workspace: Path) -> subprocess.CompletedProcess[str]:
    args = " ".join(f'"{entry}"' for entry in ENTRIES)
    return subprocess.run(
        ["bash", "-c", f'source "{LIB}"; check_tooling_layout {args}'],
        cwd=workspace,
        capture_output=True,
        text=True,
        check=False,
    )


def clone(path: Path, origin: str) -> None:
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(path)], check=True)
    subprocess.run(["git", "-C", str(path), "remote", "add", "origin", origin], check=True)


def sound_workspace(tmp: str) -> Path:
    workspace = Path(tmp)
    clone(workspace / "utils/drift-detector", "git@gitlab.com:vauchi/utils/drift-detector.git")
    clone(workspace / "utils/rqrr", "https://gitlab.com/vauchi/utils/rqrr.git")
    return workspace


class ToolingLayoutTest(unittest.TestCase):
    def test_sound_layout_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_check(sound_workspace(tmp))

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("WARNING", result.stdout)

    def test_clone_left_at_the_root_is_flagged_with_the_move(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            clone(workspace / "drift-detector", "git@gitlab.com:megloff1/drift-detector.git")
            clone(workspace / "utils/rqrr", "git@gitlab.com:vauchi/utils/rqrr.git")

            result = run_check(workspace)

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("drift-detector/ is at the workspace root", result.stdout)
            self.assertIn("mv drift-detector utils/drift-detector", result.stdout)
            self.assertTrue((workspace / "drift-detector/.git").is_dir(), "the check must not move a clone")

    def test_old_remote_is_flagged_with_the_new_url(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            clone(workspace / "utils/drift-detector", "git@gitlab.com:megloff1/drift-detector.git")
            clone(workspace / "utils/rqrr", "git@gitlab.com:vauchi/utils/rqrr.git")

            result = run_check(workspace)

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn(
                "remote set-url origin git@gitlab.com:vauchi/utils/drift-detector.git", result.stdout
            )

    def test_missing_clone_is_flagged_with_the_clone_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            clone(workspace / "utils/drift-detector", "git@gitlab.com:vauchi/utils/drift-detector.git")

            result = run_check(workspace)

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("git clone git@gitlab.com:vauchi/utils/rqrr.git utils/rqrr", result.stdout)


if __name__ == "__main__":
    unittest.main()
