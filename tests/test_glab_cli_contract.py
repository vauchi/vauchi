# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Every glab command and flag the recipes use exists in the installed glab.

The recipe tests replace glab with fakes, so they cannot see glab renaming
or dropping a flag; a host's glab upgrade would then break a recipe only
when someone runs it (vauchi/private#1179). This asks the real glab's
`--help`. Skipped where glab is not installed, as in the alpine CI image.
"""

from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMMAND = re.compile(r"\bglab (mr|ci|issue|job|release|repo|label|variable) ([a-z][a-z-]*)([^|;&)]*)")
FLAG = re.compile(r"(?<![\w-])(--[a-z][a-z-]*)")


def used_commands() -> dict[tuple[str, str], set[str]]:
    used: dict[tuple[str, str], set[str]] = {}
    for path in sorted((ROOT / "just").glob("*.just")) + sorted((ROOT / "just").glob("*.sh")):
        text = re.sub(r"\\\n\s*", " ", path.read_text(encoding="utf-8"))
        for line in text.splitlines():
            code = line.split("#", 1)[0] if line.lstrip().startswith("#") else line
            for match in COMMAND.finditer(code):
                key = (match.group(1), match.group(2))
                used.setdefault(key, set()).update(FLAG.findall(match.group(3)))
        # mr-create builds its glab arguments in an array before the call.
        for args in re.findall(r"ARGS\+?=\(([^)]*)\)", text):
            used.setdefault(("mr", "create"), set()).update(FLAG.findall(args))
    return used


@unittest.skipUnless(shutil.which("glab"), "glab is not installed")
class GlabCliContractTests(unittest.TestCase):
    def test_recipes_use_glab_commands(self) -> None:
        self.assertIn(("mr", "create"), used_commands())

    def test_every_command_and_flag_exists_in_the_installed_glab(self) -> None:
        for (group, command), flags in sorted(used_commands().items()):
            with self.subTest(command=f"glab {group} {command}"):
                help_text = subprocess.run(["glab", group, command, "--help"],
                                           capture_output=True, text=True)
                text = help_text.stdout + help_text.stderr
                self.assertEqual(help_text.returncode, 0, text[:300])
                # glab answers an unknown subcommand with its parent's help and exit 0.
                self.assertTrue(re.search(rf"glab {group} {command}\b", text),
                                f"glab {group} {command} is unknown to this glab")
                missing = sorted(f for f in flags if not re.search(re.escape(f) + r"\b", text))
                self.assertEqual(missing, [], f"glab {group} {command} has no {missing}")


if __name__ == "__main__":
    unittest.main()
