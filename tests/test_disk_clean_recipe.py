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
import shutil
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
        self.assertIn("2 incremental session directories", result.stdout)
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


class BrewOnlyWhereItExistsTests(unittest.TestCase):
    """A tier run on a host without Homebrew (Linux) skips the brew step
    silently instead of printing `brew: command not found`."""

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
        # One tier-1 path, so the run reaches the cleanup steps.
        cache = self.home / "Library/Caches/org.swift.swiftpm/artifacts"
        cache.mkdir(parents=True)
        (cache / "blob").write_text("x")
        # A PATH with the tools the recipe needs and no brew in it.
        self.bin = base / "bin"
        self.bin.mkdir()
        # `just` is linked, not its directory added: under Homebrew that
        # directory also holds brew (vauchi/private#1038).
        for tool in ("just", "bash", "sh", "env", "du", "df", "rm", "find", "sort", "awk",
                     "sed", "grep", "tail", "head", "cut", "date", "stat", "printf",
                     "dirname", "basename", "mkdir", "cat", "wc", "tr", "xargs",
                     "uname", "mktemp", "chmod", "ls", "test", "realpath", "readlink"):
            found = shutil.which(tool)
            if found:
                (self.bin / tool).symlink_to(found)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_a_tier_run_without_brew_never_mentions_it(self) -> None:
        env = dict(os.environ, HOME=str(self.home), JUST_UNSTABLE="1",
                   PATH=str(self.bin))
        result = subprocess.run(
            ["just", "disk-clean", "--tier=1", "--apply"],
            cwd=self.workspace, env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("brew", (result.stdout + result.stderr).lower())
        self.assertFalse((self.home / "Library/Caches/org.swift.swiftpm/artifacts").exists())


class TierApplyTests(unittest.TestCase):
    """On 2026-11-02 an editor's `cargo check` rebuilt into `e2e/target`
    while tier 3 deleted it; `rm` failed and the remaining target trees and
    sccache were never reached (vauchi/private#1037)."""

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
        bin_dir = base / "bin"
        bin_dir.mkdir()
        brew = bin_dir / "brew"
        brew.write_text("#!/bin/sh\nexit 0\n")
        brew.chmod(0o755)
        self.path = f"{bin_dir}:{os.environ['PATH']}"

        self.first = self.workspace / "a/target"
        self.busy = self.workspace / "b/target"
        self.last = self.workspace / "c/target"
        for target in (self.first, self.busy, self.last):
            (target / "debug").mkdir(parents=True)
            (target / "debug/artifact").write_text("x")
        self.sccache = self.home / "Library/Caches/Mozilla.sccache"
        self.sccache.mkdir(parents=True)
        # A directory rm cannot empty stands in for one being rebuilt.
        (self.busy / "debug").chmod(0o555)

    def tearDown(self) -> None:
        if (self.busy / "debug").exists():
            (self.busy / "debug").chmod(0o755)
        self._tmp.cleanup()

    def test_a_path_that_cannot_be_removed_does_not_stop_the_rest(self) -> None:
        env = dict(os.environ, HOME=str(self.home), JUST_UNSTABLE="1", PATH=self.path)
        result = subprocess.run(
            ["just", "disk-clean", "--tier=3", "--apply"],
            cwd=self.workspace,
            env=env,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0, "a partial clean must not report success")
        self.assertFalse(self.first.exists())
        self.assertFalse(self.last.exists(), "paths after the failure must still be removed")
        self.assertFalse(self.sccache.exists())
        self.assertTrue(self.busy.exists())
        self.assertIn("Not removed: b/target", result.stdout)


if __name__ == "__main__":
    unittest.main()
