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
OLDER_SHA = "0ld0000000000000000000000000000000000000"
LAST_SUCCESS = (
    '[{"created_at":"2026-08-04T06:00:00Z","status":"success",'
    f'"sha":"{CURRENT_SHA}","deployable":{{"id":777}}}}]'
)
CONFIG_SERVICES = ("monitoring", "vrt", "mail", "vaultwarden", "infisical")


class DeployCheckRecipeTests(unittest.TestCase):
    @staticmethod
    def write_executable(path: Path, lines: list[str]) -> None:
        path.write_text("\n".join([*lines, ""]), encoding="utf-8")
        path.chmod(0o755)

    def run_recipe(
        self,
        malformed_url: str = "",
        deployed_sha: str = CURRENT_SHA,
        deploy_trace: str | None = None,
        newest_attempt: str = LAST_SUCCESS,
        config_changes_since_deploy: int = 0,
        undeployed_environment: str = "",
        glab_authenticated: bool = True,
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
            , encoding="utf-8")

            helper_directory = workspace / "scripts/scripts"
            helper_directory.mkdir(parents=True)
            (helper_directory / "output-helpers.sh").write_text(
                'GREEN=""\nRED=""\nYELLOW=""\nDIM=""\nNC=""\n'
            , encoding="utf-8")

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
                    '  case "$*" in',
                    '    *" -- infra/"*)',
                    '      printf "%s\\n" "$DEPLOY_CHECK_TEST_CONFIG_CHANGES"',
                    "      exit 0",
                    "      ;;",
                    "  esac",
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
                    'if [ "$DEPLOY_CHECK_TEST_GLAB_AUTH" != 1 ]; then',
                    "  printf '{\"message\":\"401 Unauthorized\"}\\n'",
                    "  exit 1",
                    "fi",
                    'case "$*" in',
                    '  "api user")',
                    "    printf '{\"username\":\"maintainer\"}\\n'",
                    "    ;;",
                    '  *"jobs/777/trace"*)',
                    '    printf "%s\\n" "$DEPLOY_CHECK_TEST_TRACE"',
                    "    ;;",
                    # :latest is the multi-arch index and :<sha> the amd64
                    # image, so their digests never match — that comparison
                    # reported IMAGE DRIFT on every current deploy.
                    '  *"registry/repositories/12/tags/latest"*)',
                    "    printf '{\"digest\":\"sha256:index\"}\\n'",
                    "    ;;",
                    '  *"registry/repositories/12/tags/"*)',
                    "    printf '{\"digest\":\"sha256:amd64\"}\\n'",
                    "    ;;",
                    '  *"registry/repositories"*)',
                    "    printf '%s\\n' '[",
                    '      {"id":12,"path":"vauchi/relay"},',
                    '      {"id":12,"path":"vauchi/ohttp-relay"}',
                    "    ]'",
                    "    ;;",
                    '  *"deployments?environment=$DEPLOY_CHECK_TEST_UNDEPLOYED_ENV&"*)',
                    "    printf '[]\\n'",
                    "    ;;",
                    '  *"deployments?environment="*"status=success"*)',
                    f"    printf '%s\\n' '{LAST_SUCCESS}'",
                    "    ;;",
                    '  *"deployments?environment="*)',
                    '    printf "%s\\n" "$DEPLOY_CHECK_TEST_ATTEMPT"',
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
            environment["DEPLOY_CHECK_TEST_GLAB_AUTH"] = (
                "1" if glab_authenticated else "0"
            )
            environment["DEPLOY_CHECK_TEST_MALFORMED_URL"] = malformed_url
            environment["DEPLOY_CHECK_TEST_ATTEMPT"] = newest_attempt
            environment["DEPLOY_CHECK_TEST_CONFIG_CHANGES"] = str(
                config_changes_since_deploy
            )
            environment["DEPLOY_CHECK_TEST_UNDEPLOYED_ENV"] = (
                undeployed_environment or "no-such-environment"
            )
            environment["DEPLOY_CHECK_TEST_TRACE"] = (
                "production deploy image is pinned: "
                f"registry.gitlab.com/vauchi/relay:{deployed_sha}"
                if deploy_trace is None
                else deploy_trace
            )
            return subprocess.run(
                ["just", "deploy-check"],
                cwd=workspace,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_unauthenticated_glab_stops_before_reporting_any_service(
        self,
    ) -> None:
        # An expired glab login made every GitLab-backed line read UNKNOWN
        # and the recipe died with a bare exit 1 (2026-10-27).
        result = self.run_recipe(glab_authenticated=False)

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("glab auth login", result.stderr)
        self.assertNotRegex(result.stdout, r"relay\s+")
        self.assertNotIn("UNKNOWN", result.stdout)

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

    def test_gitlab_services_compare_the_deployed_tag_with_main(self) -> None:
        result = self.run_recipe()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"relay\s+UP TO DATE")
        self.assertRegex(result.stdout, r"ohttp\s+UP TO DATE")
        self.assertNotIn("IMAGE DRIFT", result.stdout)

    def test_gitlab_service_running_an_older_commit_is_stale(self) -> None:
        result = self.run_recipe(deployed_sha=OLDER_SHA)

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"relay\s+STALE")
        self.assertIn("deployed=0ld00000", result.stdout)

    def test_deploy_job_without_pinned_image_is_unknown(self) -> None:
        result = self.run_recipe(deploy_trace="kamal deploy ... done")

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"relay\s+UNKNOWN")
        self.assertRegex(result.stdout, r"ohttp\s+UNKNOWN")

    def test_failed_deploy_after_the_last_success_is_reported(self) -> None:
        result = self.run_recipe(
            newest_attempt='[{"created_at":"2026-08-05T06:00:00Z",'
            '"status":"failed","deployable":{"id":888}}]'
        )

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"relay\s+DEPLOY FAILED")
        self.assertIn("failed-job=888", result.stdout)
        self.assertIn("deployed=a1234567", result.stdout)
        self.assertRegex(result.stdout, r"vrt\s+DEPLOY FAILED")
        self.assertIn(f"DEPLOY FAILED: {2 + len(CONFIG_SERVICES)} service(s)", result.stdout)

    def test_canceled_deploy_after_the_last_success_is_reported(self) -> None:
        result = self.run_recipe(
            newest_attempt='[{"created_at":"2026-08-05T06:00:00Z",'
            '"status":"canceled","deployable":{"id":889}}]'
        )

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"ohttp\s+DEPLOY FAILED")
        self.assertIn("failed-job=889", result.stdout)

    def test_stale_service_with_no_newer_attempt_stays_stale(self) -> None:
        result = self.run_recipe(deployed_sha=OLDER_SHA)

        self.assertRegex(result.stdout, r"relay\s+STALE")
        self.assertNotIn("DEPLOY FAILED", result.stdout)

    def test_config_services_with_no_infra_change_since_deploy_are_current(self) -> None:
        result = self.run_recipe()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for service in CONFIG_SERVICES:
            self.assertRegex(result.stdout, rf"{service}\s+UP TO DATE")

    def test_config_service_with_infra_changes_since_deploy_is_stale(self) -> None:
        result = self.run_recipe(config_changes_since_deploy=3)

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"vrt\s+STALE \(3 behind\)")
        self.assertRegex(result.stdout, r"relay\s+UP TO DATE")
        self.assertIn("deployed=a1234567", result.stdout)

    def test_config_service_without_a_successful_deploy_is_unknown(self) -> None:
        result = self.run_recipe(undeployed_environment="vrt-prod")

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"vrt\s+UNKNOWN")
        self.assertRegex(result.stdout, r"monitoring\s+UP TO DATE")
        self.assertIn("EVIDENCE: 1 service(s) could not be verified", result.stdout)


if __name__ == "__main__":
    unittest.main()
