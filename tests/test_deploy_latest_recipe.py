# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


JUSTFILE = Path(sys.argv.pop(1)).resolve()
CURRENT_SHA = "360e1af8f0745af03fc8f57bf13a1474666a617a"


class DeployLatestRecipeTests(unittest.TestCase):
    def run_recipe(
        self,
        service: str = "ohttp-relay",
        pipelines_json: str = '[{"id":101}]',
        sha_digest: str = "sha256:current-main",
        created_variables_json: str | None = None,
        pipelines_exit_code: int = 0,
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            fake_bin = temporary_path / "bin"
            fake_bin.mkdir()
            glab_log = temporary_path / "glab.log"

            fake_git = fake_bin / "git"
            fake_git.write_text(
                "\n".join(
                    [
                        "#!/bin/sh",
                        'if [ "$1" = "-C" ] && [ "$3" = "fetch" ]; then',
                        "  exit 0",
                        "fi",
                        'if [ "$1" = "-C" ] && [ "$3" = "rev-parse" ]; then',
                        '  printf "%s\\n" "$DEPLOY_LATEST_TEST_SHA"',
                        "  exit 0",
                        "fi",
                        'printf "unsupported fake git invocation: %s\\n" "$*" >&2',
                        "exit 2",
                        "",
                    ]
                )
            )
            fake_git.chmod(0o755)

            fake_glab = fake_bin / "glab"
            fake_glab.write_text(
                "\n".join(
                    [
                        "#!/bin/sh",
                        '{ printf "CALL\\n"; printf "%s\\n" "$@"; } '
                        '>> "$DEPLOY_LATEST_TEST_GLAB_LOG"',
                        'case "$*" in',
                        '  *"--input -"*)',
                        '    { printf "BODY\\n"; cat; } '
                        '>> "$DEPLOY_LATEST_TEST_GLAB_LOG"',
                        "    ;;",
                        "esac",
                        'case "$*" in',
                        '  *"pipelines?sha="*)',
                        '    printf "%s\\n" "$DEPLOY_LATEST_TEST_PIPELINES_JSON"',
                        '    exit "$DEPLOY_LATEST_TEST_PIPELINES_EXIT"',
                        "    ;;",
                        '  *"registry/repositories/12/tags/latest"*)',
                        '    printf \'{"digest":"sha256:mutable-latest"}\\n\'',
                        "    ;;",
                        '  *"registry/repositories/12/tags/"*)',
                        '    if [ -n "$DEPLOY_LATEST_TEST_SHA_DIGEST" ]; then',
                        '      printf \'{"digest":"%s"}\\n\' '
                        '"$DEPLOY_LATEST_TEST_SHA_DIGEST"',
                        "    else",
                        "      printf '{}\\n'",
                        "    fi",
                        "    ;;",
                        '  *"registry/repositories"*)',
                        "    printf '%s\\n' '[",
                        '      {"id":12,"path":"vauchi/docs"},',
                        '      {"id":12,"path":"vauchi/website"},',
                        '      {"id":12,"path":"vauchi/relay"},',
                        '      {"id":12,"path":"vauchi/ohttp-relay"}',
                        "    ]'",
                        "    ;;",
                        '  *"projects/vauchi%2Fprivate/pipelines/9001/jobs"*)',
                        "    printf '%s\\n' '[",
                        '      {"name":"kamal:deploy:docs-production",'
                        '"web_url":"https://gitlab.example/jobs/docs"},',
                        '      {"name":"kamal:deploy:landing-production",'
                        '"web_url":"https://gitlab.example/jobs/landing"},',
                        '      {"name":"kamal:deploy:cdn-production",'
                        '"web_url":"https://gitlab.example/jobs/cdn"},',
                        '      {"name":"kamal:deploy:relay-production",'
                        '"web_url":"https://gitlab.example/jobs/relay"},',
                        '      {"name":"kamal:deploy:ohttp-relay-production",'
                        '"web_url":"https://gitlab.example/jobs/ohttp"}',
                        "    ]'",
                        "    ;;",
                        '  *"projects/vauchi%2Fprivate/pipelines/9001/variables"*)',
                        '    printf "%s\\n" '
                        '"$DEPLOY_LATEST_TEST_CREATED_VARIABLES_JSON"',
                        "    ;;",
                        '  *"projects/vauchi%2Fprivate/pipeline"*)',
                        "    printf '{\"id\":9001}\\n'",
                        "    ;;",
                        "  *)",
                        '    printf "unsupported fake glab invocation: %s\\n" '
                        '"$*" >&2',
                        "    exit 2",
                        "    ;;",
                        "esac",
                        "",
                    ]
                )
            )
            fake_glab.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = (
                f"{fake_bin}{os.pathsep}{environment.get('PATH', '')}"
            )
            environment["DEPLOY_LATEST_TEST_SHA"] = CURRENT_SHA
            environment["DEPLOY_LATEST_TEST_PIPELINES_JSON"] = pipelines_json
            environment["DEPLOY_LATEST_TEST_SHA_DIGEST"] = sha_digest
            environment["DEPLOY_LATEST_TEST_GLAB_LOG"] = str(glab_log)
            environment["DEPLOY_LATEST_TEST_PIPELINES_EXIT"] = str(
                pipelines_exit_code
            )
            repository = self.repository_for(service)
            expected_variables = (
                '[{"key":"DEPLOY_SERVICE","value":"'
                f'{service}"}},{{"key":"DEPLOY_IMAGE","value":"'
                f'registry.gitlab.com/vauchi/{repository}:{CURRENT_SHA}"}}]'
            )
            environment["DEPLOY_LATEST_TEST_CREATED_VARIABLES_JSON"] = (
                expected_variables
                if created_variables_json is None
                else created_variables_json
            )

            result = subprocess.run(
                ["just", "-f", str(JUSTFILE), "deploy-latest", service],
                cwd=JUSTFILE.parent,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            return result, glab_log.read_text()

    @staticmethod
    def repository_for(service: str) -> str:
        return {
            "docs": "docs",
            "landing": "website",
            "cdn": "website",
            "relay": "relay",
            "ohttp-relay": "ohttp-relay",
        }[service]

    def test_mints_sha_pinned_pipeline_for_every_service(self) -> None:
        service_repositories = {
            service: self.repository_for(service)
            for service in ("docs", "landing", "cdn", "relay", "ohttp-relay")
        }

        for service, repository in service_repositories.items():
            with self.subTest(service=service):
                result, glab_log = self.run_recipe(service=service)
                deploy_image = (
                    f"registry.gitlab.com/vauchi/{repository}:{CURRENT_SHA}"
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Content-Type: application/json", glab_log)
                self.assertIn("--input\n-", glab_log)
                self.assertIn('"ref": "main"', glab_log)
                self.assertIn('"key": "DEPLOY_SERVICE"', glab_log)
                self.assertIn(
                    f'"value": "{service}"',
                    glab_log,
                )
                self.assertIn('"key": "DEPLOY_IMAGE"', glab_log)
                self.assertIn(
                    f'"value": "{deploy_image}"',
                    glab_log,
                )
                self.assertIn(
                    "projects/vauchi%2Fprivate/pipelines/9001/variables",
                    glab_log,
                )
                self.assertIn(f"deploys {deploy_image}", result.stdout)
                self.assertIn(
                    ":latest differs; this link remains pinned",
                    result.stdout,
                )
                self.assertNotIn(f"deploys {repository}:latest", result.stdout)

    def test_missing_successful_build_fails_before_pipeline_creation(self) -> None:
        result, glab_log = self.run_recipe(pipelines_json="[]")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no successful pipeline", result.stderr)
        self.assertNotIn("projects/vauchi%2Fprivate/pipeline", glab_log)

    def test_unauthenticated_glab_fails_before_pipeline_creation(self) -> None:
        # glab prints the API error body on stdout and exits non-zero; the
        # one-key object must not be counted as one successful pipeline.
        result, glab_log = self.run_recipe(
            pipelines_json='{"message":"401 Unauthorized"}',
            pipelines_exit_code=1,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("glab auth login", result.stderr)
        self.assertNotIn("successful build pipelines: 1", result.stdout)
        self.assertNotIn("projects/vauchi%2Fprivate/pipeline", glab_log)

    def test_missing_sha_tag_fails_before_pipeline_creation(self) -> None:
        result, glab_log = self.run_recipe(sha_digest="")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no registry image", result.stderr)
        self.assertNotIn("projects/vauchi%2Fprivate/pipeline", glab_log)

    def test_created_pipeline_variable_mismatch_fails_before_job_link(self) -> None:
        result, glab_log = self.run_recipe(created_variables_json="[]")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pipeline did not retain", result.stderr)
        self.assertNotIn("pipelines/9001/jobs", glab_log)


if __name__ == "__main__":
    unittest.main()
