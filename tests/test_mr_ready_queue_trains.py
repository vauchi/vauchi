# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
"""A repository on a merge train has no agent-side ready queue (vauchi/private#1204).

The train serializes merges and tests each merged result itself, so
`mr-ready` marks the MR ready at once instead of holding it Draft behind
another ready MR and cancelling its pipeline.
"""
import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "mr_ready_queue", Path(__file__).resolve().parents[1] / "just" / "mr-ready-queue.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeGlab:
    def __init__(self, project, own, opened, trains):
        self.calls = []
        self.project, self.own, self.opened, self.trains = project, own, opened, trains

    def __call__(self, *args):
        self.calls.append(args)
        if args[0] != "api" or args[1] == "-X":
            return None
        path = args[1]
        if path == f"projects/{self.project}":
            return {"merge_trains_enabled": self.trains}
        if path.startswith(f"projects/{self.project}/merge_requests?state=opened"):
            return self.opened
        if path.startswith(f"projects/{self.project}/merge_requests/{self.own['iid']}?"):
            return self.own
        if path.startswith(f"projects/{self.project}/merge_requests/"):
            iid = int(path.split("/")[3].split("?")[0])
            return next(m for m in self.opened if m["iid"] == iid)
        raise AssertionError(f"unexpected api call {path}")


def run(trains):
    own = {"iid": 20, "draft": True, "source_branch": "issue/1", "diverged_commits_count": 0,
           "head_pipeline": {"id": 1, "status": "running"}}
    ahead = {"iid": 10, "draft": False, "head_pipeline": {"id": 2, "status": "running"}}
    fake = FakeGlab("vauchi%2Fprivate", own, [ahead, own], trains)
    MODULE.glab = fake
    out = io.StringIO()
    with redirect_stdout(out):
        code = MODULE.main("vauchi/private", 20, "_private")
    return code, out.getvalue(), fake.calls


class MergeTrainRepositoryTests(unittest.TestCase):
    def test_marks_ready_at_once_and_cancels_nothing(self):
        code, out, calls = run(trains=True)
        self.assertEqual(code, 0)
        self.assertIn(("mr", "update", "20", "--ready", "-R", "vauchi/private"), calls)
        self.assertFalse(any("cancel" in " ".join(map(str, c)) for c in calls))
        self.assertFalse(any("--draft" in c for c in calls))
        self.assertIn("merge train", out)

    def test_without_a_train_the_queue_still_holds_it(self):
        code, out, calls = run(trains=False)
        self.assertEqual(code, 0)
        self.assertIn("WAITING", out)
        self.assertNotIn(("mr", "update", "20", "--ready", "-R", "vauchi/private"), calls)


if __name__ == "__main__":
    unittest.main()
