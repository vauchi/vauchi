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


HOST = subprocess.run(["hostname", "-s"], check=True, capture_output=True, text=True).stdout.strip()


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
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith(f"held by {HOST}/vauchi-1/codex "))

    def test_a_second_session_is_refused_and_pointed_at_a_free_slot(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        self.just("vauchi", "acquire", session="claude-c")

        result = self.just("vauchi-1", "acquire", session="kimi-b", check=False)

        self.assertEqual(result.returncode, 1)
        self.assertIn("HELD", result.stdout)
        self.assertIn("free: vauchi-2", result.stdout)
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith(f"held by {HOST}/vauchi-1/codex "))

    def test_a_stale_lock_is_taken_over(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        lock = self.parent / "vauchi-1/.slot.lock"
        old = int(time.time()) - 13 * 3600
        lock.write_text(lock.read_text().replace(lock.read_text().split("seen=")[1].split()[0], str(old)))

        result = self.just("vauchi-1", "acquire", session="kimi-b")

        self.assertIn("stale", result.stdout)
        self.assertTrue(self.status_rows("kimi-b")["vauchi-1"].startswith("held by you (kimi,"))

    def backdate(self, slot: str, hours: int) -> str:
        lock = self.parent / slot / ".slot.lock"
        seen = lock.read_text().split("seen=")[1].split()[0]
        old = str(int(time.time()) - hours * 3600)
        lock.write_text(lock.read_text().replace(seen, old))
        return old

    # vauchi/private#414: seen= was written only at acquire, so a live
    # session older than SLOT_LOCK_EXPIRY_HOURS read as stale and was taken over.
    def test_touch_keeps_a_long_running_holders_lock_held(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        self.backdate("vauchi-1", 13)

        self.just("vauchi-1", "touch", session="codex-a")

        result = self.just("vauchi-1", "acquire", session="kimi-b", check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("HELD", result.stdout)
        self.assertTrue(self.status_rows("codex-a")["vauchi-1"].startswith("held by you"))

    def test_touch_by_another_session_leaves_the_lock_alone(self) -> None:
        self.just("vauchi-1", "acquire", session="codex-a")
        old = self.backdate("vauchi-1", 13)

        self.just("vauchi-1", "touch", session="kimi-b")

        lock = (self.parent / "vauchi-1/.slot.lock").read_text()
        self.assertIn(f"seen={old}", lock)
        self.assertIn("stale", self.just("vauchi-1", "acquire", session="kimi-b").stdout)

    def test_touch_on_a_free_slot_creates_no_lock(self) -> None:
        self.just("vauchi-1", "touch", session="codex-a")

        self.assertFalse((self.parent / "vauchi-1/.slot.lock").exists())

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

        # Slots are per machine and several harnesses share them; claims are
        # shared, so the stamp names the host, the slot and the agent.
        self.assertRegex(lines[0], rf"^session:[0-9a-f]{{12}} slot:{HOST}/vauchi-1/codex$")
        self.assertEqual(lines[1], lines[0].removeprefix("session:").replace(" slot:", " @"))

    def test_linked_worktrees_are_reported_with_their_dirty_count(self) -> None:
        core = self.parent / "vauchi-1/core"
        (core / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "-C", str(core), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(core), "-c", "user.name=t", "-c", "user.email=t@e",
             "commit", "--quiet", "-m", "base"],
            check=True,
        )
        linked = self.parent / "elsewhere"
        subprocess.run(
            ["git", "-C", str(core), "worktree", "add", "--quiet", "-b", "side", str(linked)],
            check=True,
        )
        (linked / "tracked.txt").write_text("unsaved\n")
        library = WORKSPACE_ROOT / "just/slot-lib.sh"

        lines = subprocess.run(
            ["bash", "-c", f'source "{library}"; slot_linked_worktrees "{self.parent / "vauchi-1"}"'],
            check=True, capture_output=True, text=True,
        ).stdout.splitlines()

        self.assertEqual(lines, [f"core {linked.resolve()} side 1"])

    def test_a_linked_worktree_whose_directory_is_gone_is_reported_missing(self) -> None:
        core = self.parent / "vauchi-1/core"
        (core / "tracked.txt").write_text("base\n")
        subprocess.run(["git", "-C", str(core), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(core), "-c", "user.name=t", "-c", "user.email=t@e",
             "commit", "--quiet", "-m", "base"],
            check=True,
        )
        linked = self.parent / "scratch-worktree"
        subprocess.run(
            ["git", "-C", str(core), "worktree", "add", "--quiet", "-b", "side", str(linked)],
            check=True,
        )
        resolved = linked.resolve()
        shutil.rmtree(linked)
        library = WORKSPACE_ROOT / "just/slot-lib.sh"

        lines = subprocess.run(
            ["bash", "-c", f'source "{library}"; slot_linked_worktrees "{self.parent / "vauchi-1"}"'],
            check=True, capture_output=True, text=True,
        ).stdout.splitlines()

        self.assertEqual(lines, [f"core {resolved} side missing"])

    def test_acquire_from_a_relative_root_names_the_slot(self) -> None:
        library = WORKSPACE_ROOT / "just/slot-lib.sh"
        environment = {**os.environ, "VAUCHI_SESSION_ID": "codex-a"}

        output = subprocess.run(
            ["bash", "-c", f'source "{library}"; slot_acquire .'],
            cwd=self.parent / "vauchi-2", env=environment,
            check=True, capture_output=True, text=True,
        ).stdout

        self.assertIn(f"Slot {HOST}/vauchi-2/codex held", output)

    def test_session_id_needs_no_shasum(self) -> None:
        # alpine:3.21 (CI) ships sha256sum but no shasum.
        no_shasum = self.parent / "no-shasum"
        no_shasum.mkdir()
        (no_shasum / "shasum").write_text("#!/bin/sh\nexit 127\n")
        (no_shasum / "shasum").chmod(0o755)
        library = WORKSPACE_ROOT / "just/slot-lib.sh"
        environment = {
            **os.environ,
            "VAUCHI_SESSION_ID": "codex-a",
            "PATH": f"{no_shasum}:{os.environ['PATH']}",
        }

        session = subprocess.run(
            ["bash", "-c", f'source "{library}"; slot_session_id'],
            env=environment, check=True, capture_output=True, text=True,
        ).stdout.strip()

        self.assertRegex(session, r"^[0-9a-f]{12}$")


if __name__ == "__main__":
    unittest.main()
