# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LINT_DOCS_SCRIPT = Path(sys.argv.pop(1)).resolve()


class LintDocsRecipeTest(unittest.TestCase):
    def initialise_repository(self, path: Path) -> None:
        path.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "init", "--quiet", "--initial-branch=main", str(path)],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "-C", str(path), "config", "user.email", "test@example.com"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(path), "config", "user.name", "Lint Docs Test"],
            check=True,
        )

    def commit_all(self, repository: Path, message: str) -> None:
        subprocess.run(["git", "-C", str(repository), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(repository), "commit", "--quiet", "-m", message],
            check=True,
        )

    def write(self, root: Path, relative_path: str, content: str = "# Test\n") -> None:
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def create_fixture(self, root: Path) -> tuple[Path, Path]:
        self.initialise_repository(root)
        for repository in ["_private", "scripts", "assets", "docs", "core"]:
            self.initialise_repository(root / repository)

        self.write(root, "README.md")
        self.write(root, "_private/docs/decisions/adr-001-test.md")
        self.write(root, "_private/docs/investigations/legacy-topic.md")
        self.commit_all(root / "_private", "historical documents")
        self.write(
            root,
            "_private/docs/investigations/2026-07-18-new-topic.md",
        )
        self.write(
            root,
            "_private/docs/investigations/2026-07-18-staged-topic.md",
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(root / "_private"),
                "add",
                "docs/investigations/2026-07-18-staged-topic.md",
            ],
            check=True,
        )
        self.write(root, "scripts/README.md")
        self.write(root, "assets/README.md")
        self.write(
            root,
            "docs/src/architecture.md",
            "# Public docs\n\nThis project is licensed under MIT.\n",
        )
        self.write(root, "core/docs/domain.md")

        naming_log = root / "naming-files.log"
        naming_checker = root / "scripts/ci-templates/check-doc-naming.sh"
        naming_checker.parent.mkdir(parents=True, exist_ok=True)
        naming_checker.write_text(
            "#!/bin/sh\n"
            "shift\n"
            "printf '%s\\n' \"$@\" > \"$DOC_NAMING_LOG\"\n"
        , encoding="utf-8")
        naming_checker.chmod(0o755)

        lychee_log = root / "lychee-files.log"
        lychee = root / "bin/lychee"
        lychee.parent.mkdir(parents=True)
        lychee.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" > \"$LYCHEE_LOG\"\n"
        , encoding="utf-8")
        lychee.chmod(0o755)
        return naming_log, lychee_log

    def test_scans_owned_repositories_without_descending_into_checkouts(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            naming_log, lychee_log = self.create_fixture(root)
            environment = os.environ.copy()
            environment["DOC_NAMING_LOG"] = str(naming_log)
            environment["LYCHEE_LOG"] = str(lychee_log)
            environment["PATH"] = f"{root / 'bin'}:{environment['PATH']}"

            result = subprocess.run(
                ["bash", str(LINT_DOCS_SCRIPT)],
                cwd=root,
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            naming_files = naming_log.read_text(encoding="utf-8").splitlines()
            self.assertIn("README.md", naming_files)
            self.assertIn(
                "_private/docs/investigations/2026-07-18-new-topic.md",
                naming_files,
            )
            self.assertIn(
                "_private/docs/investigations/2026-07-18-staged-topic.md",
                naming_files,
            )
            self.assertIn("scripts/README.md", naming_files)
            self.assertNotIn(
                "_private/docs/investigations/legacy-topic.md",
                naming_files,
            )
            self.assertNotIn(
                "_private/docs/decisions/adr-001-test.md",
                naming_files,
            )
            self.assertNotIn("assets/README.md", naming_files)
            self.assertFalse(
                any(path.startswith(("docs/", "core/")) for path in naming_files)
            )

            lychee_arguments = lychee_log.read_text(encoding="utf-8").splitlines()
            self.assertIn("assets/README.md", lychee_arguments)
            self.assertFalse(
                any(path.startswith(("docs/", "core/")) for path in lychee_arguments)
            )


if __name__ == "__main__":
    unittest.main()
