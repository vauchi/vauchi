# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just disk-clean --stale-incremental`.

On 2026-10-01 nell stood at 98% and rustc's incremental caches held about
173 GB across the three workspace slots (45, 33 and 60 GB in `core` alone).
Cargo never evicts them: one slot's `core/target/debug/incremental` held 694
session directories, 495 of them untouched for two days. No tier removed them
without also deleting whole `target/` trees and the shared sccache
(vauchi/private#322).
"""

from pathlib import Path
import os
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
DAY = 86400


def run_disk_clean(workspace: Path, home: Path, *args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, HOME=str(home), JUST_UNSTABLE="1")
    return subprocess.run(
        ["just", "disk-clean", *args],
        cwd=workspace,
        env=env,
        capture_output=True,
        text=True,
    )


class StaleIncrementalTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.workspace = base / "ws"
        self.home = base / "home"
        self.workspace.mkdir()
        self.home.mkdir()
        for entry in ("justfile", "just"):
            source = ROOT / entry
            target = self.workspace / entry
            if source.is_dir():
                subprocess.run(["cp", "-R", str(source), str(target)], check=True)
            else:
                target.write_bytes(source.read_bytes())

        self.stale = self._session("core/target/debug/incremental/vauchi_core-aaa", days_old=3)
        self.stale_triple = self._session(
            "core/target/aarch64-apple-ios/release/incremental/vauchi_core-bbb", days_old=9
        )
        self.hot = self._session("core/target/debug/incremental/vauchi_core-ccc", days_old=0)
        self.deps = self.workspace / "core/target/debug/deps/libvauchi_core.rlib"
        self.deps.parent.mkdir(parents=True)
        self.deps.write_text("artifact")
        old = time.time() - 30 * DAY
        os.utime(self.deps, (old, old))
        # A tier-1 path in the fake HOME: this mode must leave it alone.
        self.swiftpm = self.home / "Library/Caches/org.swift.swiftpm/artifacts"
        self.swiftpm.mkdir(parents=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _session(self, relative: str, days_old: int) -> Path:
        path = self.workspace / relative
        path.mkdir(parents=True)
        (path / "dep-graph.bin").write_text("x" * 64)
        stamp = time.time() - days_old * DAY
        os.utime(path / "dep-graph.bin", (stamp, stamp))
        os.utime(path, (stamp, stamp))
        return path

    def test_a_dry_run_lists_stale_sessions_and_deletes_nothing(self) -> None:
        result = run_disk_clean(self.workspace, self.home, "--stale-incremental")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("vauchi_core-aaa", result.stdout)
        self.assertIn("vauchi_core-bbb", result.stdout)
        self.assertNotIn("vauchi_core-ccc", result.stdout)
        self.assertIn("Dry-run", result.stdout)
        self.assertTrue(self.stale.is_dir())
        self.assertTrue(self.stale_triple.is_dir())

    def test_apply_removes_stale_sessions_only(self) -> None:
        result = run_disk_clean(self.workspace, self.home, "--stale-incremental", "--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.stale.exists())
        self.assertFalse(self.stale_triple.exists())
        self.assertTrue(self.hot.is_dir(), "a session built today must stay warm")
        self.assertEqual(self.deps.read_text(), "artifact", "compiled dependencies must survive")
        self.assertTrue(self.swiftpm.is_dir(), "tier-1 caches are not this mode's business")

    def test_it_does_not_combine_with_a_tier(self) -> None:
        result = run_disk_clean(self.workspace, self.home, "--stale-incremental", "--tier=3")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.stale.is_dir())

    def test_nothing_stale_is_reported_as_nothing(self) -> None:
        for path in (self.stale, self.stale_triple):
            now = time.time()
            os.utime(path, (now, now))
        result = run_disk_clean(self.workspace, self.home, "--stale-incremental", "--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Nothing to clean", result.stdout)
        self.assertTrue(self.stale.is_dir())


if __name__ == "__main__":
    unittest.main()
