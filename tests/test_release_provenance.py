# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Release inputs must come from unchanged, committed checklist evidence."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from certification_fixture import fresh_report

WORKSPACE = Path(__file__).resolve().parents[1]
CHECKLIST = "docs/planning/2026-10-30-first-release-ship-checklist.md"


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True,
        timeout=10,
    ).stdout.strip()


def initialize(repo, filename):
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "Release test")
    git(repo, "config", "user.email", "release@example.test")
    path = repo / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("fixture\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "Initial fixture")
    origin = repo.with_name(repo.name + "-origin.git")
    subprocess.run(["git", "clone", "--bare", "-q", str(repo), str(origin)], check=True)
    git(repo, "remote", "add", "origin", str(origin))
    git(repo, "fetch", "-q", "origin")
    return git(repo, "rev-parse", "HEAD")


class ReleaseProvenanceTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.private = self.root / "_private"
        self.checklist_revision = initialize(self.private, CHECKLIST)
        self.release_revision = initialize(self.root / "core", "Cargo.toml")
        self.e2e_revision = initialize(self.root / "e2e", "README.md")
        report = fresh_report()
        report["pipeline"]["sha"] = self.e2e_revision
        report["sources"]["e2e"] = self.e2e_revision
        for lane in report["lanes"]:
            lane["sha"] = self.e2e_revision
        self.evidence = self.root / "target/release-evidence/certification.json"
        self.evidence.parent.mkdir(parents=True)
        self.evidence.write_text(json.dumps(report))
        self.output = self.evidence.with_name("release-inputs.json")

    def invoke(self, mode="record"):
        return subprocess.run(
            [sys.executable, "-m", "tools.release_provenance", "core", "v1.2.3",
             str(self.output), "--workspace", str(self.root), "--mode", mode],
            cwd=WORKSPACE, capture_output=True, text=True, timeout=15,
        )

    def assert_blocked(self, phrase):
        result = self.invoke()
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(phrase, result.stderr)
        self.assertFalse(self.output.exists())

    def test_records_exact_checklist_commit_and_certification_inputs(self):
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        report = json.loads(self.output.read_text())
        self.assertEqual({"repository": "core", "tag": "v1.2.3",
                          "revision": self.release_revision}, report["release"])
        self.assertEqual({
            "repository": "vauchi/private", "revision": self.checklist_revision,
            "path": CHECKLIST,
            "sha256": hashlib.sha256((self.private / CHECKLIST).read_bytes()).hexdigest(),
        }, report["checklist"])
        self.assertEqual(self.e2e_revision, report["certification"]["e2e_revision"])
        self.assertEqual(2948969220, report["certification"]["pipeline_id"])
        self.assertEqual(hashlib.sha256(self.evidence.read_bytes()).hexdigest(),
                         report["certification"]["sha256"])
        verified = self.invoke("verify")
        self.assertEqual(0, verified.returncode, verified.stderr)
        self.assertIn("unchanged", verified.stdout)

    def test_rejects_uncommitted_checklist_edits(self):
        (self.private / CHECKLIST).write_text("unchecked change\n")
        self.assert_blocked("private checkout is dirty")

    def test_rejects_staged_checklist_edits(self):
        (self.private / CHECKLIST).write_text("staged change\n")
        git(self.private, "add", CHECKLIST)
        self.assert_blocked("private checkout is dirty")

    def test_rejects_untracked_private_files(self):
        (self.private / "unexpected.py").write_text("unexpected\n")
        self.assert_blocked("private checkout is dirty")

    def test_rejects_unmerged_checklist_commits(self):
        (self.private / CHECKLIST).write_text("unmerged\n")
        git(self.private, "commit", "-qam", "Unmerged checklist")
        self.assert_blocked("private HEAD does not match origin/main")

    def test_refreshes_remote_main_before_accepting_local_tracking_ref(self):
        writer = self.root / "writer"
        subprocess.run(["git", "clone", "-q", str(self.private), str(writer)], check=True)
        git(writer, "config", "user.name", "Other writer")
        git(writer, "config", "user.email", "writer@example.test")
        git(writer, "remote", "set-url", "origin", str(self.root / "_private-origin.git"))
        (writer / CHECKLIST).write_text("new main\n")
        git(writer, "commit", "-qam", "Update main")
        git(writer, "push", "-q", "origin", "main")
        self.assertEqual(self.checklist_revision, git(self.private, "rev-parse", "origin/main"))
        self.assert_blocked("private HEAD does not match origin/main")

    def test_unavailable_origin_blocks_release(self):
        git(self.private, "remote", "set-url", "origin", str(self.root / "missing.git"))
        self.assert_blocked("cannot refresh private origin/main")

    def test_missing_certification_blocks_release(self):
        self.evidence.unlink()
        self.assert_blocked("certification report missing or unreadable")

    def test_verification_rejects_changed_certification_bytes(self):
        prepared = self.invoke()
        self.assertEqual(0, prepared.returncode, prepared.stderr)
        self.evidence.write_text(self.evidence.read_text() + "\n")
        result = self.invoke("verify")
        self.assertEqual(1, result.returncode)
        self.assertIn("release inputs changed", result.stderr)

    def test_verification_rejects_a_new_release_commit(self):
        prepared = self.invoke()
        self.assertEqual(0, prepared.returncode, prepared.stderr)
        (self.root / "core/Cargo.toml").write_text("changed\n")
        git(self.root / "core", "commit", "-qam", "New release source")
        result = self.invoke("verify")
        self.assertEqual(1, result.returncode)
        self.assertIn("release inputs changed", result.stderr)

    def release_prod(self, gate_mutation=False):
        core = self.root / "core"
        (core / "Cargo.toml").write_text('[workspace.package]\nversion = "1.2.3"\n')
        git(core, "commit", "-qam", "Release version")
        (self.root / "gate.py").write_text(
            "from pathlib import Path\nPath('gate-ran').touch()\n"
            + (f"Path('_private/{CHECKLIST}').write_text('changed during approval')\n"
               if gate_mutation else "")
        )
        (self.root / "justfile").write_text(
            'release-provenance repo tag mode="record":\n'
            '    python3 -m tools.release_provenance {{repo}} {{tag}} '
            'target/release-evidence/release-inputs.json --mode {{mode}}\n'
            'release-gates:\n    python3 gate.py\n'
        )
        return subprocess.run(
            ["just", "--justfile", str(WORKSPACE / "justfile"),
             "--working-directory", str(self.root), "release-prod", "core"],
            input="y\n", capture_output=True, text=True, timeout=20,
            env=dict(os.environ, PYTHONPATH=str(WORKSPACE)),
        )

    def test_release_prod_rejects_dirty_checklist_before_gates_or_tagging(self):
        (self.private / CHECKLIST).write_text("dirty\n")
        result = self.release_prod()
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("private checkout is dirty", result.stderr)
        self.assertFalse((self.root / "gate-ran").exists())
        self.assertEqual("", git(self.root / "core", "tag", "--list"))

    def test_release_prod_rechecks_inputs_before_tagging(self):
        result = self.release_prod(gate_mutation=True)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("private checkout is dirty", result.stderr)
        self.assertTrue((self.root / "gate-ran").exists())
        self.assertEqual("", git(self.root / "core", "tag", "--list"))

    def test_release_tag_preserves_the_provenance_record(self):
        result = self.release_prod()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        message = git(self.root / "core", "for-each-ref", "refs/tags/v1.2.3", "--format=%(contents)")
        record = json.loads(message)
        self.assertEqual(self.checklist_revision, record["checklist"]["revision"])
        self.assertEqual("v1.2.3", record["release"]["tag"])
        self.assertEqual(git(self.root / "core", "rev-parse", "HEAD"),
                         git(self.root / "core-origin.git", "rev-parse", "v1.2.3^{}"))


if __name__ == "__main__":
    unittest.main()
