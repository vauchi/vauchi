# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for the ready queue behind `just gitlab mr-ready` (vauchi/private#1179).

With fast-forward merges GitLab rebases a behind MR at merge time and merges
on its earlier green pipeline, so two ready MRs merged one after the other
land a tree no pipeline tested (9 of 15 sampled core merges). The maintainer
rejected merge trains; agents queue instead. An MR goes ready only when no
other live ready MR waits in its repository and it is rebased on main.
Otherwise it stays Draft, its pipeline is cancelled, and both MRs say so in
a comment.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
# "." stands for the repository the shell is in, as in vauchi/scripts.
RESOLVE_REPO = """resolve_gitlab_repo() { if [ "$1" = . ]; then echo core; else echo "$1"; fi; }
resolve_gitlab_project() { echo "vauchi/$(resolve_gitlab_repo "$1")"; }
gitlab_repo_dir() { echo "$1"; }
"""
# A stand-in for glab backed by a JSON file: the MR list, single MRs,
# notes, pipeline cancel and `mr update --ready/--draft`.
FAKE_GLAB = r"""#!/usr/bin/env python3
import json, os, sys
path = os.environ["FAKE_GLAB_STATE"]
state = json.load(open(path))
args = sys.argv[1:]

def save_and_print(value):
    json.dump(state, open(path, "w"))
    print(json.dumps(value))
    sys.exit(0)

if args[:2] == ["auth", "status"]:
    sys.exit(0)
if args[:2] == ["mr", "update"]:
    mr = state["mrs"][args[2]]
    mr["draft"] = "--draft" in args
    json.dump(state, open(path, "w"))
    print("- Updating merge request !%s" % args[2])
    sys.exit(0)
assert args[0] == "api", args
method, fields, rest, i = "GET", {}, [], 1
while i < len(args):
    if args[i] == "-X":
        method = args[i + 1]; i += 2
    elif args[i] in ("-f", "-F"):
        k, _, v = args[i + 1].partition("="); fields[k] = v; i += 2
    else:
        rest.append(args[i]); i += 1
route, _, query = rest[0].partition("?")
parts = route.split("/")
assert parts[:2] == ["projects", "vauchi%2Fcore"], parts
if len(parts) == 2:
    # The queue asks the project whether a merge train runs (private#1204).
    save_and_print({"merge_trains_enabled": state.get("merge_trains_enabled", False)})
if parts[2] == "merge_requests" and len(parts) == 3:
    save_and_print([{k: v for k, v in m.items() if k != "head_pipeline"}
                    for m in state["mrs"].values() if m["state"] == "opened"])
if parts[2] == "merge_requests" and len(parts) == 5 and parts[4] == "pipelines":
    # GitLab creates an MR's pipeline a few seconds after the MR: it shows
    # here before the MR's head_pipeline is set.
    save_and_print(state["mrs"][parts[3]].get("pipelines", []))
if parts[2] == "merge_requests" and len(parts) == 4:
    save_and_print(state["mrs"][parts[3]])
if parts[2] == "merge_requests" and parts[4] == "notes" and method == "POST":
    state.setdefault("notes", {}).setdefault(parts[3], []).append(fields["body"])
    save_and_print({"id": 1})
if parts[2] == "pipelines" and parts[4] == "cancel" and method == "POST":
    state.setdefault("cancelled", []).append(int(parts[3]))
    save_and_print({"id": int(parts[3]), "status": "canceled"})
sys.stderr.write("unexpected: %r\n" % args)
sys.exit(2)
"""


def mr(iid, draft, pipeline=None, behind=0):
    return {
        "iid": iid, "state": "opened", "draft": draft,
        "source_branch": f"issue/{iid}", "diverged_commits_count": behind,
        "head_pipeline": pipeline,
    }


class MrReadyQueueTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "resolve-repo.sh").write_text(RESOLVE_REPO, encoding="utf-8")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        glab = bin_dir / "glab"
        glab.write_text(FAKE_GLAB, encoding="utf-8")
        glab.chmod(0o755)
        self.state = base / "state.json"
        self.env = dict(
            os.environ, JUST_UNSTABLE="1", FAKE_GLAB_STATE=str(self.state),
            PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}", READY_QUEUE_POLL_INTERVAL="0",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def ready(self, mrs, iid, repo="core"):
        self.state.write_text(json.dumps({"mrs": {str(m["iid"]): m for m in mrs}}), encoding="utf-8")
        result = subprocess.run(
            ["just", "gitlab", "mr-ready", str(iid), repo],
            cwd=self.ws, env=self.env, capture_output=True, text=True,
        )
        return result, json.loads(self.state.read_text(encoding="utf-8"))

    def test_an_mr_alone_and_rebased_goes_ready(self) -> None:
        result, state = self.ready([mr(20, True, {"id": 5, "status": "running"})], 20)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(state["mrs"]["20"]["draft"])
        self.assertNotIn("notes", state)

    # 2026-11-09: `mr-create .` printed "first in the . ready queue".
    def test_messages_name_the_repository_not_the_argument(self) -> None:
        ahead = mr(19, False, {"id": 4, "status": "running"})
        result, state = self.ready([ahead, mr(20, True, {"id": 5, "status": "running"})], 20, ".")

        self.assertIn("just gitlab mr-ready 20 core", state["notes"]["20"][0])
        self.assertIn("mr-ready 20 core", result.stdout)
        self.assertNotIn(" . ", result.stdout + state["notes"]["20"][0])

    def test_an_mr_behind_main_stays_draft_and_is_told_to_rebase(self) -> None:
        result, state = self.ready([mr(20, True, {"id": 5, "status": "success"}, behind=2)], 20)

        self.assertEqual(result.returncode, 1)
        self.assertTrue(state["mrs"]["20"]["draft"])
        self.assertIn("2 commits behind main", result.stdout + result.stderr)

    def test_a_bump_mr_behind_main_is_told_to_let_gitlab_rebase_it(self) -> None:
        bump = dict(mr(20, True, {"id": 5, "status": "success"}, behind=1),
                    source_branch="chore/bump-core-0.103.0")
        result, _ = self.ready([bump], 20)

        self.assertEqual(result.returncode, 1)
        self.assertIn("just gitlab mr-rebase 20 core", result.stdout)
        self.assertNotIn("push", result.stdout)

    def test_an_mr_behind_a_live_ready_mr_waits_as_draft_and_stops_its_pipeline(self) -> None:
        ahead = mr(19, False, {"id": 4, "status": "running"})
        result, state = self.ready([ahead, mr(20, True, {"id": 5, "status": "running"})], 20)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(state["mrs"]["20"]["draft"])
        self.assertEqual(state["cancelled"], [5])
        self.assertIn("waiting behind !19", state["notes"]["20"][0])
        self.assertIn("!20 waits for this MR", state["notes"]["19"][0])
        self.assertIn("waiting behind !19", result.stdout)

    # 2026-11-09, core!2287: opened behind !2286 before GitLab had created
    # its pipeline, so nothing was cancelled and the pipeline ran anyway.
    def test_a_waiting_mrs_pipeline_created_after_the_mr_is_cancelled(self) -> None:
        ahead = mr(19, False, {"id": 4, "status": "running"})
        fresh = dict(mr(20, True, None), pipelines=[{"id": 8, "status": "created"}])
        _, state = self.ready([ahead, fresh], 20)

        self.assertTrue(state["mrs"]["20"]["draft"])
        self.assertEqual(state["cancelled"], [8])

    def test_a_finished_pipeline_of_a_waiting_mr_is_not_cancelled(self) -> None:
        ahead = mr(19, False, {"id": 4, "status": "success"})
        _, state = self.ready([ahead, mr(20, True, {"id": 5, "status": "success"})], 20)

        self.assertTrue(state["mrs"]["20"]["draft"])
        self.assertNotIn("cancelled", state)

    def test_a_red_ready_mr_does_not_hold_the_queue(self) -> None:
        red = mr(19, False, {"id": 4, "status": "failed"})
        result, state = self.ready([red, mr(20, True, {"id": 5, "status": "running"})], 20)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(state["mrs"]["20"]["draft"])

    def test_of_two_ready_mrs_the_older_one_keeps_its_place(self) -> None:
        older = mr(19, False, {"id": 4, "status": "running"})
        result, state = self.ready([older, mr(20, False, {"id": 5, "status": "running"})], 20)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(state["mrs"]["19"]["draft"])
        self.assertTrue(state["mrs"]["20"]["draft"])


if __name__ == "__main__":
    unittest.main()
