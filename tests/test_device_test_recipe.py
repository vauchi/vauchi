# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import sys
import unittest
from pathlib import Path

DEVICE_TEST_JUSTFILE = Path(sys.argv.pop(1)).resolve()
DEVICE_TEST_LIBRARY = Path(sys.argv.pop(1)).resolve()


class DeviceTestRecipeTest(unittest.TestCase):
    def test_physical_device_libraries_enable_dev_logging(self) -> None:
        source = DEVICE_TEST_JUSTFILE.read_text()

        expected_builds = [
            "cargo build -p vauchi-platform --target aarch64-apple-ios "
            "--release --features dev-logging",
            "cargo build -p vauchi-platform --target aarch64-linux-android "
            "--release --features dev-logging",
        ]

        for command in expected_builds:
            self.assertIn(command, source)

    def test_native_bindgen_build_clears_ios_deployment_target(self) -> None:
        source = DEVICE_TEST_JUSTFILE.read_text()
        combined_build = source.split(
            "_dt-build-mobile-libs core_dir:", maxsplit=1
        )[1].split("# Generate Swift bindings", maxsplit=1)[0]
        native_build = combined_build.split(
            "# Native macOS (needed for Kotlin binding generation)", maxsplit=1
        )[1]

        self.assertIn("unset IPHONEOS_DEPLOYMENT_TARGET", native_build)

    def test_ios_build_clears_the_workspace_package_resolution(self) -> None:
        source = DEVICE_TEST_JUSTFILE.read_text()
        ios_build = source.split("_dt-build-ios:", maxsplit=1)[1].split(
            "# Build Android APK", maxsplit=1
        )[0]

        self.assertIn(
            "rm -f Vauchi.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            ios_build,
        )

    def test_ios_build_uses_a_mirror_of_the_fresh_local_artifact(self) -> None:
        recipe = DEVICE_TEST_JUSTFILE.read_text()
        library = DEVICE_TEST_LIBRARY.read_text()
        ios_build = recipe.split("_dt-build-ios:", maxsplit=1)[1].split(
            "# Build Android APK", maxsplit=1
        )[0]

        self.assertIn("dt_provision_ios_local_spm", ios_build)
        self.assertIn(
            '-clonedSourcePackagesDirPath "$DT_IOS_SPM_CACHE_PATH"',
            ios_build,
        )
        self.assertIn(
            'cp -RL "$spm_framework" "$mirror/VauchiPlatformFFI.xcframework"',
            library,
        )
        self.assertIn("DT_IOS_SPM_PROJECT_CONFIG_BACKUP", library)
        self.assertIn(
            'cp "$DT_IOS_SPM_PROJECT_CONFIG_BACKUP" '
            '"$DT_IOS_SPM_PROJECT_CONFIG"',
            library,
        )
        self.assertIn("dt_restore_ios_spm_config", ios_build)
        self.assertIn(
            'security unlock-keychain -p "build" '
            '"$HOME/Library/Keychains/build.keychain-db"',
            ios_build,
        )


if __name__ == "__main__":
    unittest.main()
