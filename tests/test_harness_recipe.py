# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HARNESS_JUSTFILE = Path(sys.argv.pop(1)).resolve()


class HarnessRecipeTest(unittest.TestCase):
    def launch(
        self, directory: Path, harness: str, *arguments: str, session_id: str | None = None
    ) -> list[str]:
        bin_dir = directory / "bin"
        bin_dir.mkdir(exist_ok=True)
        stand_in = bin_dir / harness
        stand_in.write_text('#!/bin/sh\nprintf "%s\\n" "$VAUCHI_SESSION_ID" "$@"\n')
        stand_in.chmod(0o755)
        shutil.copyfile(HARNESS_JUSTFILE, directory / "harness.just")
        (directory / "justfile").write_text("mod harness 'harness.just'\n")

        environment = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
        environment.pop("VAUCHI_SESSION_ID", None)
        if session_id is not None:
            environment["VAUCHI_SESSION_ID"] = session_id
        result = subprocess.run(
            ["just", "--justfile", str(directory / "justfile"), "harness", harness, *arguments],
            cwd=directory,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.splitlines()

    def test_each_launch_gets_its_own_session_id(self) -> None:
        for harness in ("codex", "kimi"):
            with self.subTest(harness=harness), tempfile.TemporaryDirectory() as directory:
                first = self.launch(Path(directory), harness)[0]
                second = self.launch(Path(directory), harness)[0]

                self.assertRegex(first, rf"^{harness}-[0-9a-f]{{32}}$")
                self.assertRegex(second, rf"^{harness}-[0-9a-f]{{32}}$")
                self.assertNotEqual(first, second)

    def test_an_existing_session_id_is_kept(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lines = self.launch(Path(directory), "codex", session_id="outer-session")

            self.assertEqual(lines, ["outer-session"])

    def test_arguments_pass_through_unsplit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lines = self.launch(Path(directory), "kimi", "-p", "two words")

            self.assertEqual(lines[1:], ["-p", "two words"])


if __name__ == "__main__":
    unittest.main()
