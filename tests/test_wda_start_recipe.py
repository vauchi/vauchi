# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just dt-wda-start` (vauchi/private#667).

On nell the recipe failed with only "Failed to install the app on the
device": the signing identities sit in a locked build keychain, a cached
runner bundle can be broken, and the grep filter dropped xcodebuild's real
reason. The test runs the recipe in a sandbox with stand-ins for security,
codesign and xcodebuild.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

RUNNER = "Library/Developer/Xcode/DerivedData/WebDriverAgent-x/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"

STUBS = {
    "security": 'echo "security $*" >> "$CALLS"\n',
    "codesign": (
        'echo "codesign $*" >> "$CALLS"\n'
        '[ -f "$BUNDLE_OK" ] || { echo "bundle format unrecognized, invalid, or unsuitable" >&2; exit 1; }\n'
    ),
    "xcodebuild": (
        'echo "xcodebuild $*" >> "$CALLS"\n'
        'case "$*" in\n'
        '  *build-for-testing*) touch "$BUNDLE_OK"; echo "** TEST BUILD SUCCEEDED **" ;;\n'
        '  *test-without-building*)\n'
        '    echo "Failed to initialize for UI testing: Timed out while enabling automation mode."\n'
        '    echo "** TEST EXECUTE FAILED **"; exit 65 ;;\n'
        'esac\n'
    ),
}


class WdaStartRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        self.home = base / "home"
        (self.home / "Workspace/.tools/WebDriverAgent/WebDriverAgent.xcodeproj").mkdir(parents=True)
        (self.home / RUNNER).mkdir(parents=True)
        self.calls = base / "calls.log"
        self.calls.touch()
        self.bundle_ok = base / "bundle-ok"
        self.bin = base / "bin"
        self.bin.mkdir()
        for name, body in STUBS.items():
            stub = self.bin / name
            stub.write_text("#!/bin/sh\n" + body)
            stub.chmod(0o755)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_recipe(self) -> subprocess.CompletedProcess:
        env = dict(
            os.environ,
            HOME=str(self.home),
            PATH=f"{self.bin}:{os.environ['PATH']}",
            IOS_DEVICE_ID="00008030-TEST",
            CALLS=str(self.calls),
            BUNDLE_OK=str(self.bundle_ok),
            JUST_UNSTABLE="1",
        )
        return subprocess.run(
            ["just", "dt-wda-start"], cwd=self.ws, env=env, capture_output=True, text=True
        )

    def calls_made(self) -> list[str]:
        return self.calls.read_text().splitlines()

    def test_the_build_keychain_is_unlocked_before_xcodebuild_signs(self) -> None:
        self.run_recipe()

        calls = self.calls_made()
        unlock = next(
            (i for i, c in enumerate(calls)
             if c.startswith("security unlock-keychain") and c.endswith("Library/Keychains/build.keychain-db")),
            None,
        )
        first_xcodebuild = next(i for i, c in enumerate(calls) if c.startswith("xcodebuild"))
        self.assertIsNotNone(unlock, calls)
        self.assertLess(unlock, first_xcodebuild, calls)

    def test_a_broken_runner_bundle_is_rebuilt_before_testing(self) -> None:
        self.run_recipe()

        builds = [c for c in self.calls_made() if c.startswith("xcodebuild")]
        self.assertEqual(len(builds), 2, builds)
        self.assertIn("build-for-testing", builds[0])
        self.assertIn("test-without-building", builds[1])

    def test_a_valid_runner_bundle_is_not_rebuilt(self) -> None:
        self.bundle_ok.touch()

        self.run_recipe()

        builds = [c for c in self.calls_made() if c.startswith("xcodebuild")]
        self.assertEqual(len(builds), 1, builds)
        self.assertIn("test-without-building", builds[0])

    def test_xcodebuilds_failure_reason_reaches_the_caller(self) -> None:
        self.bundle_ok.touch()

        result = self.run_recipe()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Timed out while enabling automation mode", result.stdout + result.stderr)
        self.assertIn("Enable UI Automation", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
