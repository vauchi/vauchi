# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""`just gitlab ready-queue-waiting` names the queued MRs whose turn came (vauchi/private#1179).

An MR the ready queue held back stays Draft after the MR ahead of it
merges, and nothing tells its session. session-init lists it (maintainer,
2026-11-09): a Draft whose latest `ready-queue: waiting behind !N` comment
names an MR that is no longer open.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FAKE_GLAB = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:2] == ["auth", "status"]:
    sys.exit(0)
state = json.load(open(os.environ["FAKE_GLAB_STATE"]))
route = args[1].partition("?")[0]
query = args[1].partition("?")[2]
if route == "groups/vauchi/merge_requests":
    assert "state=opened" in query and "wip=yes" in query, query
    print(json.dumps([m for m in state["mrs"] if m["draft"] and m["state"] == "opened"]))
    sys.exit(0)
parts = route.split("/")
mr = next(m for m in state["mrs"] if str(m["project_id"]) == parts[1] and str(m["iid"]) == parts[3])
if len(parts) == 5 and parts[4] == "notes":
    print(json.dumps(list(reversed(mr.get("notes", [])))))
else:
    print(json.dumps(mr))
"""


def mr(project_id, path, iid, state="opened", draft=False, notes=()):
    return {"project_id": project_id, "iid": iid, "state": state, "draft": draft,
            "references": {"full": f"{path}!{iid}"},
            "notes": [{"body": body} for body in notes]}


WAIT = "ready-queue: waiting behind !{0}, which is ready, so this MR stays Draft."


class ReadyQueueWaitingTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        glab = bin_dir / "glab"
        glab.write_text(FAKE_GLAB)
        glab.chmod(0o755)
        self.state = base / "state.json"
        self.env = dict(os.environ, JUST_UNSTABLE="1", FAKE_GLAB_STATE=str(self.state),
                        PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def waiting(self, mrs) -> subprocess.CompletedProcess:
        self.state.write_text(json.dumps({"mrs": mrs}))
        return subprocess.run(["just", "gitlab", "ready-queue-waiting"], cwd=self.ws,
                              env=self.env, capture_output=True, text=True)

    def test_a_draft_whose_blocker_merged_is_listed_with_its_next_step(self) -> None:
        result = self.waiting([
            mr(7, "vauchi/core", 19, state="merged"),
            mr(7, "vauchi/core", 20, draft=True, notes=[WAIT.format(19)]),
        ])

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("core !20: !19 merged", result.stdout)
        self.assertIn("just gitlab mr-ready 20 core", result.stdout)

    def test_a_draft_still_behind_an_open_mr_is_not_listed(self) -> None:
        result = self.waiting([
            mr(7, "vauchi/core", 19),
            mr(7, "vauchi/core", 20, draft=True, notes=[WAIT.format(19)]),
        ])

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("!20", result.stdout)

    def test_only_the_latest_queue_comment_counts(self) -> None:
        result = self.waiting([
            mr(7, "vauchi/core", 18, state="merged"),
            mr(7, "vauchi/core", 19),
            mr(7, "vauchi/core", 20, draft=True, notes=[WAIT.format(18), WAIT.format(19)]),
        ])

        self.assertNotIn("!20", result.stdout)

    def test_a_draft_the_queue_never_held_is_not_listed(self) -> None:
        result = self.waiting([mr(9, "vauchi/ios", 5, draft=True, notes=["work in progress"])])

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("!5", result.stdout)

    def test_repositories_under_a_subgroup_are_named_by_their_last_segment(self) -> None:
        result = self.waiting([
            mr(11, "vauchi/utils/spake2", 3, state="closed"),
            mr(11, "vauchi/utils/spake2", 4, draft=True, notes=[WAIT.format(3)]),
        ])

        self.assertIn("spake2 !4: !3 closed", result.stdout)
        self.assertIn("just gitlab mr-ready 4 spake2", result.stdout)


if __name__ == "__main__":
    unittest.main()
