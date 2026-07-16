# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import re
import subprocess
import sys
import unittest
from pathlib import Path


DEV_JUSTFILE = Path(sys.argv.pop(1)).resolve()


class CoreFreshnessRecipeTest(unittest.TestCase):
    def test_android_binding_version_parser_accepts_the_platform_dependency(self) -> None:
        source = DEV_JUSTFILE.read_text()
        assignment = re.search(
            r'^\s+ANDROID_VER=\$\(sed -n \'([^\']+)\' "\$ANDROID_GRADLE"\)$',
            source,
            re.MULTILINE,
        )
        if assignment is None:
            self.fail("core-freshness must parse Android's binding version")

        result = subprocess.run(
            ["sed", "-n", assignment.group(1)],
            input='implementation("app.vauchi:vauchi-platform:0.55.4")\n',
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.stdout, "0.55.4\n")


if __name__ == "__main__":
    unittest.main()
