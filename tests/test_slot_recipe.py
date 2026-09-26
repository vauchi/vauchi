# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()


class SlotRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.parent = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.parent)
        for name in ("vauchi", "vauchi-1", "vauchi-2"):
            self.make_slot(name)
        (self.parent / "vauchi-old").mkdir()
        (self.parent / "vauchi-old/justfile").write_text("")

    def make_slot(self, name: str) -> Path:
        slot = self.parent / name
        (slot / "just").mkdir(parents=True)
        for library in ("slot.just", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, slot / "just" / library)
        (slot / "justfile").write_text("mod slot 'just/slot.just'\n")
        (slot / "CLAUDE.md").write_text("")
        for repository in (slot, slot / "core"):
            subprocess.run(
                ["git", "init", "--quiet", "--initial-branch=main", str(repository)],
                check=True,
            )
        (slot / ".gitignore").write_text("/core/\n/.slot.lock\n")
        subprocess.run(["git", "-C", str(slot), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(slot), "-c", "user.name=t", "-c", "user.email=t@e",
             "commit", "--quiet", "-m", "slot"],
            check=True,
        )
        return slot

    def just(
        self, slot: str, recipe: str, *, session: str, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "VAUCHI_SESSION_ID": session}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        return subprocess.run(
            ["just", "--justfile", str(self.parent / slot / "justfile"), "slot", recipe],
            cwd=self.parent / slot,
            env=environment,
            check=check,
            capture_output=True,
            text=True,
        )

    def status_rows(self, session: str) -> dict[str, str]:
        output = self.just("vauchi", "status", session=session).stdout
        rows = {}
        for line in output.splitlines():
            fields = line.split(None, 1)
            if fields and fields[0].startswith("vauchi"):
                rows[fields[0]] = fields[1] if len(fields) > 1 else ""
        return rows

    def test_status_lists_only_numbered_sibling_slots(self) -> None:
        rows = self.status_rows("codex-a")

        self.assertEqual(sorted(rows), ["vauchi", "vauchi-1", "vauchi-2"])
        self.assertTrue(all(row.startswith("free") for row in rows.values()), rows)

    def test_acquire_marks_the_slot_as_held_by_this_session(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")

        self.assertTrue(self.status_rows("codex-a")["vauchi-1"].startswith("held by you (codex,"))
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith("held by codex"))

    def test_a_second_session_is_refused_and_pointed_at_a_free_slot(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        self.just("vauchi", "acquire", session="claude-c")

        result = self.just("vauchi-1", "acquire", session="kimi-b", check=False)

        self.assertEqual(result.returncode, 1)
        self.assertIn("HELD", result.stdout)
        self.assertIn("free: vauchi-2", result.stdout)
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith("held by codex"))

    def test_a_stale_lock_is_taken_over(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        lock = self.parent / "vauchi-1/.slot.lock"
        old = int(time.time()) - 13 * 3600
        lock.write_text(lock.read_text().replace(lock.read_text().split("seen=")[1].split()[0], str(old)))

        result = self.just("vauchi-1", "acquire", session="kimi-b")

        self.assertIn("stale", result.stdout)
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith("held by you (kimi,"))

    def test_only_the_holder_releases(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")

        self.just("vauchi-1", "release", session="kimi-b")
        self.assertTrue(self.status_rows("codex-a")["vauchi-1"].startswith("held by you"))

        self.just("vauchi-1", "release", session="codex-a")
        self.assertTrue(self.status_rows("codex-a")["vauchi-1"].startswith("free"))

    def test_status_counts_repositories_off_main_and_dirty(self) -> None:
        core = self.parent / "vauchi-2/core"
        subprocess.run(["git", "-C", str(core), "switch", "--quiet", "-c", "fix/x"], check=True)
        (core / "scratch.txt").write_text("unsaved\n")

        row = self.status_rows("codex-a")["vauchi-2"]

        self.assertIn("1 off main", row)
        self.assertIn("1 dirty", row)

    def test_claim_tag_names_session_and_slot_and_parses_back(self) -> None:
        library = WORKSPACE_ROOT / "just/slot-lib.sh"
        script = (
            f'source "{library}"; tag=$(slot_claim_tag "{self.parent / "vauchi-1"}"); '
            'echo "$tag"; slot_claim_owner "claim: x $tag"'
        )
        environment = {**os.environ, "VAUCHI_SESSION_ID": "codex-a"}

        lines = subprocess.run(
            ["bash", "-c", script], env=environment, check=True, capture_output=True, text=True
        ).stdout.splitlines()

        self.assertRegex(lines[0], r"^session:[0-9a-f]{12} slot:vauchi-1$")
        self.assertEqual(lines[1], lines[0].removeprefix("session:").replace(" slot:", " @"))


if __name__ == "__main__":
    unittest.main()
