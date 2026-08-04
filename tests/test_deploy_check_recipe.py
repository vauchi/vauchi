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


DEPLOY_JUST = Path(sys.argv.pop(1)).resolve()
CURRENT_SHA = "a1234567890bcdefa1234567890bcdefa1234567"


class DeployCheckRecipeTests(unittest.TestCase):
    @staticmethod
    def write_executable(path: Path, lines: list[str]) -> None:
        path.write_text("\n".join([*lines, ""]))
        path.chmod(0o755)

    def run_recipe(
        self,
        malformed_url: str = "",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            shutil.copy2(DEPLOY_JUST, workspace / "deploy.just")
            (workspace / "justfile").write_text(
                "\n".join(
                    [
                        'set shell := ["bash", "-cu"]',
                        'set script-interpreter := ["bash", "-eu"]',
                        "import 'deploy.just'",
                        "",
                    ]
                )
            )

            helper_directory = workspace / "scripts/scripts"
            helper_directory.mkdir(parents=True)
            (helper_directory / "output-helpers.sh").write_text(
                'GREEN=""\nRED=""\nYELLOW=""\nDIM=""\nNC=""\n'
            )

            fake_bin = workspace / "bin"
            fake_bin.mkdir()
            self.write_executable(
                fake_bin / "git",
                [
                    "#!/bin/sh",
                    'if [ "$1" = "-C" ] && [ "$3" = "fetch" ]; then',
                    "  exit 0",
                    "fi",
                    'if [ "$1" = "-C" ] && [ "$3" = "rev-parse" ]; then',
                    '  printf "%s\\n" "$DEPLOY_CHECK_TEST_SHA"',
                    "  exit 0",
                    "fi",
                    'if [ "$1" = "-C" ] && [ "$3" = "rev-list" ]; then',
                    "  printf '0\\n'",
                    "  exit 0",
                    "fi",
                    'printf "unsupported fake git invocation: %s\\n" "$*" >&2',
                    "exit 2",
                ],
            )
            self.write_executable(
                fake_bin / "glab",
                [
                    "#!/bin/sh",
                    'case "$*" in',
                    '  *"registry/repositories/12/tags/"*)',
                    "    printf '{\"digest\":\"sha256:current\"}\\n'",
                    "    ;;",
                    '  *"registry/repositories"*)',
                    "    printf '%s\\n' '[",
                    '      {"id":12,"path":"vauchi/relay"},',
                    '      {"id":12,"path":"vauchi/ohttp-relay"}',
                    "    ]'",
                    "    ;;",
                    '  *"deployments?environment="*)',
                    "    printf '%s\\n' '[{",
                    '      "created_at":"2026-08-04T06:00:00Z"',
                    "    }]'",
                    "    ;;",
                    '  *"pipelines?sha="*)',
                    "    printf '[{\"id\":99,\"sha\":\"%s\"}]\\n' \\",
                    '      "$DEPLOY_CHECK_TEST_SHA"',
                    "    ;;",
                    '  *"pipelines/99"*)',
                    "    printf '%s\\n' '{",
                    '      "finished_at":"2026-08-04T05:00:00Z"',
                    "    }'",
                    "    ;;",
                    '  *"pipelines?ref=main&status=success&per_page=1"*)',
                    "    printf '[{\"id\":99,\"sha\":\"%s\"}]\\n' \\",
                    '      "$DEPLOY_CHECK_TEST_SHA"',
                    "    ;;",
                    "  *)",
                    '    printf "unsupported fake glab invocation: %s\\n" '
                    '"$*" >&2',
                    "    exit 2",
                    "    ;;",
                    "esac",
                ],
            )
            self.write_executable(
                fake_bin / "curl",
                [
                    "#!/bin/sh",
                    'follow_redirects="no"',
                    'url=""',
                    'for arg in "$@"; do',
                    '  case "$arg" in',
                    '    -*L*) follow_redirects="yes" ;;',
                    '    http*) url="$arg" ;;',
                    "  esac",
                    "done",
                    'if [ "$url" = "$DEPLOY_CHECK_TEST_MALFORMED_URL" ]; then',
                    "  printf 'not-json\\n'",
                    "  exit 0",
                    "fi",
                    'if [ "$url" = '
                    '"https://docs.vauchi.app/build-info.json" ] && '
                    '[ "$follow_redirects" != "yes" ]; then',
                    "  printf '<html>moved</html>\\n'",
                    "  exit 0",
                    "fi",
                    "printf '{\"sha\":\"%s\",\"built\":\"%s\"}\\n' \\",
                    '  "$DEPLOY_CHECK_TEST_SHA" "2026-08-04T05:30:00Z"',
                ],
            )

            environment = os.environ.copy()
            environment["PATH"] = (
                f"{fake_bin}{os.pathsep}{environment.get('PATH', '')}"
            )
            environment["DEPLOY_CHECK_TEST_SHA"] = CURRENT_SHA
            environment["DEPLOY_CHECK_TEST_MALFORMED_URL"] = malformed_url
            return subprocess.run(
                ["just", "deploy-check"],
                cwd=workspace,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_redirected_build_info_reports_every_service(self) -> None:
        result = self.run_recipe()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"docs\s+UP TO DATE")
        self.assertRegex(result.stdout, r"cdn\s+UP TO DATE")
        self.assertIn("Fetch latest: just git fetch", result.stdout)
        self.assertNotIn("jq: parse error", result.stderr)

    def test_malformed_build_info_is_unknown_and_later_checks_run(self) -> None:
        result = self.run_recipe(
            malformed_url="https://vauchi.app/build-info.json"
        )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertRegex(result.stdout, r"website\s+UNKNOWN")
        self.assertRegex(result.stdout, r"docs\s+UP TO DATE")
        self.assertRegex(result.stdout, r"cdn\s+UP TO DATE")
        self.assertIn("EVIDENCE: 1 service(s) could not be verified", result.stdout)
        self.assertNotIn("jq: parse error", result.stderr)


if __name__ == "__main__":
    unittest.main()
