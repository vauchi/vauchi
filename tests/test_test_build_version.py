# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for just/test_build_version.py (vauchi/private#665).

`just test-build` raises an app's version so that merging the bump tags a
release and CI uploads it to TestFlight or Play internal testing. Both
stores refuse a build number they have seen, so the build number must go
up every time, and nothing else in the file may change.
"""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "just" / "test_build_version.py"

ANDROID = """android {
    defaultConfig {
        applicationId = "app.vauchi"
        versionCode = 5
        versionName = "0.1.4"
    }
}
"""

IOS = """targets:
  Vauchi:
    settings:
      base:
        MARKETING_VERSION: "0.1.13"
        CURRENT_PROJECT_VERSION: "14"
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
"""


def bump(app: str, text: str) -> tuple[subprocess.CompletedProcess, str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "file"
        path.write_text(text, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(HELPER), app, str(path)],
            capture_output=True,
            text=True,
        )
        return result, path.read_text(encoding="utf-8")


class TestBuildVersionTests(unittest.TestCase):
    def test_android_gets_the_next_patch_and_version_code(self) -> None:
        result, text = bump("android", ANDROID)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0.1.5 6")
        self.assertEqual(
            text,
            ANDROID.replace("versionCode = 5", "versionCode = 6").replace(
                'versionName = "0.1.4"', 'versionName = "0.1.5"'
            ),
        )

    def test_ios_gets_the_next_patch_and_build_number(self) -> None:
        result, text = bump("ios", IOS)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0.1.14 15")
        self.assertEqual(
            text,
            IOS.replace('MARKETING_VERSION: "0.1.13"', 'MARKETING_VERSION: "0.1.14"').replace(
                'CURRENT_PROJECT_VERSION: "14"', 'CURRENT_PROJECT_VERSION: "15"'
            ),
        )

    def test_a_file_without_exactly_one_version_is_left_alone(self) -> None:
        for app, text in [
            ("android", ANDROID.replace("versionCode = 5\n", "")),
            ("android", ANDROID + 'versionName = "9.9.9"\n'),
            ("ios", IOS.replace('MARKETING_VERSION: "0.1.13"', 'MARKETING_VERSION: "beta"')),
        ]:
            result, after = bump(app, text)
            self.assertNotEqual(result.returncode, 0, f"{app}: must refuse")
            self.assertEqual(after, text, f"{app}: the file must be unchanged")

    def test_an_unknown_app_is_refused(self) -> None:
        result, _ = bump("windows", ANDROID)

        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
