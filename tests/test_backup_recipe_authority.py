# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEPLOY_RECIPES = (ROOT / "just" / "deploy.just").read_text()
CI_CONFIG = (ROOT / ".gitlab-ci.yml").read_text()


class ProductionRecipeAuthorityTests(unittest.TestCase):
    def test_ci_runs_authority_contract_for_recipe_changes(self) -> None:
        self.assertIn(
            "python3 -m unittest tests/test_backup_recipe_authority.py",
            CI_CONFIG,
        )
        self.assertIn("- just/deploy.just", CI_CONFIG)
        self.assertIn("- tests/test_backup_recipe_authority.py", CI_CONFIG)

    def test_no_recipe_uses_direct_production_ssh(self) -> None:
        self.assertNotIn('ssh_target := "vauchi@bold-hopper-vps"', DEPLOY_RECIPES)
        self.assertNotIn("ssh {{ssh_target}}", DEPLOY_RECIPES)
        self.assertNotIn('ssh "{{ssh_target}}"', DEPLOY_RECIPES)
        self.assertNotIn("just/deploy-running.sh", DEPLOY_RECIPES)
        self.assertFalse((ROOT / "just" / "deploy-running.sh").exists())

    def test_no_recipe_runs_local_production_mutation_helpers(self) -> None:
        forbidden_commands = (
            "kamal proxy reboot",
            "kamal rollback",
            "./_private/infra/scripts/deploy-mail.sh",
            "./_private/infra/mail/prepare-mail.sh",
            "./_private/infra/scripts/deploy-monitoring.sh",
            "./_private/infra/scripts/deploy-vrt.sh",
        )
        for command in forbidden_commands:
            with self.subTest(command=command):
                self.assertNotIn(command, DEPLOY_RECIPES)

    def test_deep_status_rejects_daily_driver_host_access(self) -> None:
        self.assertIn(
            "--running requires Hety's reviewed operator shell",
            DEPLOY_RECIPES,
        )

    def test_retired_recipes_point_to_reviewed_authority(self) -> None:
        self.assertIn("GitLab", DEPLOY_RECIPES)
        self.assertIn("Hety", DEPLOY_RECIPES)

    def test_backup_recipes_do_not_use_daily_driver_authority(self) -> None:
        backup_section = DEPLOY_RECIPES.split(
            "# BACKUP & RESTORE", maxsplit=1
        )[1].split("# MONITORING", maxsplit=1)[0]

        self.assertNotIn("ssh {{ssh_target}}", backup_section)
        self.assertNotIn("/opt/vauchi-infra/scripts/backup.sh", backup_section)
        self.assertNotIn(
            "/opt/vauchi-infra/scripts/verify-backup.sh", backup_section
        )

    def test_backup_recipes_point_to_hety_runbook(self) -> None:
        self.assertIn(
            "_private/docs/runbooks/2026-07-11-backup-restore.md",
            DEPLOY_RECIPES,
        )
        self.assertIn("Hety", DEPLOY_RECIPES)


if __name__ == "__main__":
    unittest.main()
