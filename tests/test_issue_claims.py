# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()

# A stand-in for `glab api`, backed by a JSON file, covering exactly the calls
# issue-lib.sh makes: issues, notes, branches and the main..branch compare.
FAKE_GLAB = r'''#!/usr/bin/env python3
import json, os, sys, time
state_path = os.environ["FAKE_GLAB_STATE"]
state = json.load(open(state_path))
args = sys.argv[1:]
assert args[0] == "api", args
method, fields, rest = "GET", {}, []
i = 1
while i < len(args):
    if args[i] == "-X":
        method = args[i + 1]; i += 2
    elif args[i] in ("-f", "-F"):
        key, _, value = args[i + 1].partition("="); fields[key] = value; i += 2
    else:
        rest.append(args[i]); i += 1
path = rest[0].split("?")[0]
query = rest[0].partition("?")[2]
parts = path.split("/")

def out(value):
    # Reads run concurrently (issue_claims fetches holders in parallel) and must not rewrite the file.
    print(json.dumps(value))
    if method != "GET":
        json.dump(state, open(state_path, "w"))
    sys.exit(0)

def fail(message):
    print(json.dumps({"message": message})); sys.stderr.write(message + "\n"); sys.exit(1)

if parts[2] == "issues" and len(parts) == 3:
    opened = [i for i in state["issues"].values() if i["state"] == "opened"]
    if "--paginate" not in args:
        opened = opened[:int(query.partition("per_page=")[2].split("&")[0] or 20)]
    out(opened)
if parts[2] == "issues" and len(parts) == 4:
    issue = state["issues"].get(parts[3])
    out(issue) if issue else fail("404 Not found")
def new_note(issue, body):
    note = {"id": 1000 + sum(len(n) for n in state["notes"].values()), "body": body,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())}
    state["notes"].setdefault(issue, []).append(note)
    return note

if parts[2] == "issues" and parts[4] == "discussions":
    discussions = state.setdefault("discussions", {}).setdefault(parts[3], [])
    if method == "POST" and len(parts) == 7:
        thread = next((d for d in discussions if d["id"] == parts[5]), None)
        if thread is None:
            fail("404 Discussion Not Found")
        note = new_note(parts[3], fields["body"]); thread["notes"].append(note); out(note)
    out(discussions)
if parts[2] == "issues" and parts[4] == "notes":
    if parts[3] not in state["issues"]:
        fail("404 Not found")
    if method == "POST":
        note = new_note(parts[3], fields["body"])
        state.setdefault("discussions", {}).setdefault(parts[3], []).append(
            {"id": "thread-%d" % note["id"], "notes": [note]})
        out(note)
    notes = list(reversed(state["notes"].setdefault(parts[3], [])))
    if "--paginate" not in args:
        notes = notes[:int(query.partition("per_page=")[2].split("&")[0] or 20)]
    out(notes)
if parts[2] == "repository" and parts[3] == "branches":
    if method == "POST":
        name = fields["branch"]
        if name in state["branches"]:
            fail("Branch already exists")
        # GitLab reports commit dates with the committer's offset, not Z.
        state["branches"][name] = {"name": name, "ahead": 0,
            "commit": {"committed_date": time.strftime("%Y-%m-%dT%H:%M:%S+02:00", time.gmtime(time.time() + 7200))}}
        out(state["branches"][name])
    if method == "DELETE":
        # Lets a test land a push elsewhere while release is under way (#444).
        if os.environ.get("FAKE_GLAB_ON_BRANCH_DELETE"):
            os.system(os.environ["FAKE_GLAB_ON_BRANCH_DELETE"])
        state["branches"].pop(parts[4].replace("%2F", "/"), None); out({})
    if len(parts) == 5:
        branch = state["branches"].get(parts[4].replace("%2F", "/"))
        out(branch) if branch else fail("404 Branch Not Found")
    prefix = query.partition("search=")[2].split("&")[0].lstrip("^")
    # Like GitLab: sorted by name, one page unless --paginate.
    found = [state["branches"][n] for n in sorted(state["branches"]) if n.startswith(prefix)]
    if "--paginate" not in args:
        found = found[:int(query.partition("per_page=")[2].split("&")[0] or 20)]
    out(found)
if parts[2] == "repository" and parts[3] == "compare":
    to = query.partition("to=")[2].split("&")[0].replace("%2F", "/")
    if to not in state["branches"]:
        fail("404 Ref Not Found")
    out({"commits": [{}] * state["branches"][to]["ahead"]})
if parts[2] == "merge_requests" and len(parts) == 3:
    source = query.partition("source_branch=")[2].split("&")[0].replace("%2F", "/")
    out([m for m in state.get("mrs", {}).values()
         if m["state"] == "opened" and m["source_branch"] == source])
if parts[2] == "merge_requests" and len(parts) == 4 and method == "PUT":
    mr = state["mrs"][parts[3]]
    # GitLab answered this PUT with a 500 right after the MR was created.
    if state.get("put_failures", 0) > 0:
        state["put_failures"] -= 1
        json.dump(state, open(state_path, "w"))
        fail("glab: 500 Internal Server Error (HTTP 500)")
    mr["force_remove_source_branch"] = fields["remove_source_branch"] == "true"
    out(mr)
fail("unhandled " + method + " " + rest[0])
'''


class IssueClaimTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        self.slot = self.directory / "vauchi-1"
        (self.slot / "just").mkdir(parents=True)
        for library in ("issue-lib.sh", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, self.slot / "just" / library)
        (self.slot / "_private/docs").mkdir(parents=True)
        (self.slot / "_private/docs/2026-09-25-claim-collisions.md").write_text("## Entries\n")
        bin_dir = self.directory / "bin"
        bin_dir.mkdir()
        (bin_dir / "glab").write_text(FAKE_GLAB)
        (bin_dir / "glab").chmod(0o755)
        self.path = f"{bin_dir}:{os.environ['PATH']}"
        self.state = self.directory / "state.json"
        self.save({
            "issues": {
                "7": {"iid": 7, "state": "opened", "title": "Fix the relay",
                      "labels": ["priority::high"], "web_url": "u7"},
                "9": {"iid": 9, "state": "opened", "title": "Tidy docs",
                      "labels": ["priority::low", "type::chore"], "web_url": "u9"},
                "3": {"iid": 3, "state": "closed", "title": "Old", "labels": [], "web_url": "u3"},
            },
            "notes": {},
            "branches": {},
        })

    def save(self, state: dict) -> None:
        self.state.write_text(json.dumps(state))

    def load(self) -> dict:
        return json.loads(self.state.read_text())

    def run_lib(self, command: str, session: str, check: bool = False,
                extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "PATH": self.path, "FAKE_GLAB_STATE": str(self.state),
                       "VAUCHI_SESSION_ID": session, **(extra_env or {})}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        return subprocess.run(
            ["bash", "-c", f'set -euo pipefail; source just/slot-lib.sh; source just/issue-lib.sh; {command}'],
            cwd=self.slot, env=environment, check=check, capture_output=True, text=True,
        )

    def test_claim_creates_the_issue_branch_and_names_session_and_slot(self) -> None:
        result = self.run_lib("issue_claim 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.load()
        self.assertIn("issue/7", state["branches"])
        self.assertRegex(state["notes"]["7"][0]["body"],
                         r"^claim: session:[0-9a-f]{12} slot:[^ ]+/vauchi-1/codex$")

    def test_a_second_session_is_blocked_and_the_refusal_logged(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_claim 7", "kimi-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("BLOCKED", result.stdout)
        self.assertIn("(active 0h ago)", result.stdout)
        self.assertIn("#7 | held-by-other", (self.slot / "_private/docs/2026-09-25-claim-collisions.md").read_text())

    def test_reclaiming_your_own_issue_succeeds(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_claim 7", "codex-a")

        self.assertEqual(result.returncode, 0)
        self.assertIn("already yours", result.stdout)

    def test_a_closed_or_missing_issue_cannot_be_claimed(self) -> None:
        for number in ("3", "404"):
            with self.subTest(number=number):
                result = self.run_lib(f"issue_claim {number}", "codex-a")

                self.assertEqual(result.returncode, 1)
                self.assertNotIn(f"issue/{number}", self.load()["branches"])

    def test_a_stale_claim_is_taken_over_with_a_note(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["branches"]["issue/7"]["commit"]["committed_date"] = "2026-01-01T02:00:00+02:00"
        state["notes"]["7"][0]["created_at"] = "2026-01-01T00:00:00.000Z"
        self.save(state)

        result = self.run_lib("issue_claim 7", "kimi-b")

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.load()["notes"]["7"][-1]["body"].startswith("takeover: session:"))

    def test_an_active_claim_is_taken_over_when_the_maintainer_authorizes_it(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_claim 7 'holder slot is free'", "kimi-b")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        note = self.load()["notes"]["7"][-1]["body"]
        self.assertRegex(note, r"^takeover: session:[0-9a-f]{12} slot:")
        self.assertIn("idle 0h, authorized by the maintainer: holder slot is free)", note)
        self.assertIn("#7 | authorized-takeover",
                      (self.slot / "_private/docs/2026-09-25-claim-collisions.md").read_text())

    def test_a_blank_reason_does_not_authorize_a_takeover(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_claim 7 '  '", "kimi-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("BLOCKED", result.stdout)
        self.assertFalse(self.load()["notes"]["7"][-1]["body"].startswith("takeover:"))

    # vauchi/private#415: session-end read the legacy work board and reported
    # "No active claims" while this session still held issues.
    def test_session_claims_lists_only_this_sessions_live_claims(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        self.run_lib("issue_claim 9", "codex-b", check=True)

        mine = self.run_lib("issue_session_claims", "codex-a")

        self.assertEqual(mine.returncode, 0, mine.stderr)
        self.assertEqual(mine.stdout.split(), ["7"])

        self.run_lib("issue_release 7", "codex-a", check=True)
        self.assertEqual(self.run_lib("issue_session_claims", "codex-a").stdout.split(), [])

    # vauchi/private#830: an issue/<N>-<slug> work branch is no claim, yet its
    # "<N>-<slug>" was looked up as an issue and jq failed on GitLab's 404.
    def test_a_branch_named_issue_n_with_a_slug_is_not_a_claim(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["branches"]["issue/9-notification-identity"] = dict(
            state["branches"]["issue/7"], name="issue/9-notification-identity")
        self.save(state)

        for command, expected in (("issue_session_claims", "7"), ("issue_claims", "#7")):
            with self.subTest(command=command):
                result = self.run_lib(command, "codex-a")

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertEqual(result.stdout.split()[0], expected)
                self.assertNotIn("notification-identity", result.stdout)

    def test_claims_are_listed_by_issue_number_with_their_holder(self) -> None:
        for number, session in (("12", "codex-a"), ("7", "kimi-b"), ("9", "codex-a")):
            self.state.write_text(json.dumps({**self.load(), "issues": {
                **self.load()["issues"], number: {"iid": int(number), "state": "opened",
                                                  "title": "T", "labels": [], "web_url": "u"}}}))
            self.run_lib(f"issue_claim {number}", session, check=True)

        result = self.run_lib("issue_claims", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual([line.split()[0] for line in lines], ["#7", "#9", "#12"])
        self.assertIn("/kimi", lines[0])
        self.assertIn("/codex", lines[2])

    # 72 issue/<N> branches on 2026-11-09; past GitLab's 100-per-page the
    # rest of the claims would vanish from every listing.
    def test_claims_past_the_first_page_of_branches_are_listed(self) -> None:
        state = self.load()
        for number in range(1000, 1101):
            state["branches"][f"issue/{number}"] = {"name": f"issue/{number}", "ahead": 0,
                "commit": {"committed_date": "2026-11-09T05:00:00+00:00"}}
        self.save(state)

        result = self.run_lib("issue_claims", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 101)
        self.assertEqual(result.stdout.splitlines()[-1].split()[0], "#1100")

    def test_release_deletes_an_empty_claim_branch_and_notes_it(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("issue/7", self.load()["branches"])
        self.assertTrue(self.load()["notes"]["7"][-1]["body"].startswith("release: session:"))

    def test_release_finds_the_claim_under_many_system_notes(self) -> None:
        # #30 (2026-10-08): label and MR-link system notes pushed the claim
        # note past the newest 50, and its own session was refused.
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["notes"]["7"].extend(
            {"id": 5000 + n, "body": "added ~claim::active label", "system": True,
             "created_at": "2026-10-08T12:00:00.000Z"} for n in range(60))
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("issue/7", self.load()["branches"])

    def test_release_refuses_a_branch_holding_unmerged_work(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["branches"]["issue/7"]["ahead"] = 2
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 1)
        self.assertIn("2 commit(s)", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    # A claim outlives the session that made it when the issue closes before
    # that session releases it; the next session in the same slot cannot
    # release it, and takeover refuses a closed issue, so it stayed forever.
    def claimed_then_closed(self, slot: str | None = None) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["issues"]["7"]["state"] = "closed"
        if slot is not None:
            note = state["notes"]["7"][-1]
            note["body"] = note["body"].rsplit(" slot:", 1)[0] + " slot:" + slot
        self.save(state)

    def test_release_frees_a_closed_issue_claimed_by_an_earlier_session_of_this_slot(self) -> None:
        self.claimed_then_closed()

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("earlier session in this slot", result.stdout)
        self.assertNotIn("issue/7", self.load()["branches"])
        self.assertTrue(self.load()["notes"]["7"][-1]["body"].startswith("release: session:"))

    # Stamps before the harness suffix name the slot as <host>/<folder> only;
    # #815, #875, #882 and #921 carried "slot:AC/vauchi".
    def test_release_frees_a_closed_issue_whose_claim_predates_the_harness_suffix(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        legacy = self.load()["notes"]["7"][-1]["body"].rsplit("/", 1)[0]
        self.claimed_then_closed(slot=legacy.split(" slot:", 1)[1])

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.load()["branches"])

    def test_release_leaves_a_closed_issue_claimed_from_another_slot(self) -> None:
        self.claimed_then_closed(slot="nell/vauchi-2/codex")

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("not held by this session", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    def test_release_leaves_a_closed_issue_whose_claim_names_no_slot(self) -> None:
        self.claimed_then_closed()
        state = self.load()
        note = state["notes"]["7"][-1]
        note["body"] = note["body"].rsplit(" slot:", 1)[0]
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("not held by this session", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    def test_release_leaves_an_open_issue_claimed_by_an_earlier_session_of_this_slot(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("not held by this session", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    def test_release_of_a_closed_issue_from_this_slot_still_refuses_unmerged_work(self) -> None:
        self.claimed_then_closed()
        state = self.load()
        state["branches"]["issue/7"]["ahead"] = 2
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-b")

        self.assertEqual(result.returncode, 1)
        self.assertIn("2 commit(s)", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    def sibling_with_issue_branch(self, number: int, unmerged: bool) -> Path:
        remote = self.directory / "core.git"
        subprocess.run(["git", "init", "--quiet", "--bare", "--initial-branch=main", str(remote)], check=True)
        core = self.slot / "core"
        subprocess.run(["git", "clone", "--quiet", str(remote), str(core)], check=True, capture_output=True)
        git = ["git", "-C", str(core), "-c", "user.name=t", "-c", "user.email=t@e"]
        subprocess.run([*git, "commit", "--quiet", "--allow-empty", "-m", "base"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", "HEAD:main"], check=True)
        subprocess.run([*git, "switch", "--quiet", "-c", f"issue/{number}"], check=True)
        if unmerged:
            (core / "work.txt").write_text("work\n")
            subprocess.run([*git, "add", "work.txt"], check=True)
            subprocess.run([*git, "commit", "--quiet", "-m", "work"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", f"issue/{number}"], check=True)
        return remote

    def remote_branches(self, remote: Path) -> list[str]:
        return subprocess.run(["git", "-C", str(remote), "branch", "--format=%(refname:short)"],
                              check=True, capture_output=True, text=True).stdout.split()

    def test_release_deletes_merged_issue_branches_in_sibling_repos(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=False)
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.remote_branches(remote))
        self.assertIn("core", result.stdout)

    def test_release_treats_a_rebase_merged_sibling_branch_as_merged(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=True)
        core = self.slot / "core"
        git = ["git", "-C", str(core), "-c", "user.name=t", "-c", "user.email=t@e"]
        # GitLab rebases on merge: main gets the same change under a new hash.
        subprocess.run([*git, "switch", "--quiet", "main"], check=True)
        subprocess.run([*git, "commit", "--quiet", "--allow-empty", "-m", "other work on main"], check=True)
        subprocess.run([*git, "cherry-pick", "issue/7"], check=True, capture_output=True)
        subprocess.run([*git, "push", "--quiet", "origin", "main"], check=True)
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.remote_branches(remote))

    # #444: release decided "merged" during its sibling scan and deleted the
    # branch later; a push in between was deleted with it, closing its MR.
    def test_release_keeps_a_sibling_branch_that_gained_a_commit_during_release(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=False)
        pusher = self.directory / "pusher"
        subprocess.run(["git", "clone", "--quiet", "--branch", "issue/7", str(remote), str(pusher)],
                       check=True, capture_output=True)
        git = ["git", "-C", str(pusher), "-c", "user.name=t", "-c", "user.email=t@e"]
        (pusher / "late.txt").write_text("late\n")
        subprocess.run([*git, "add", "late.txt"], check=True)
        subprocess.run([*git, "commit", "--quiet", "-m", "late work"], check=True)
        late = subprocess.run([*git, "rev-parse", "HEAD"], check=True, capture_output=True,
                              text=True).stdout.strip()
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib(
            "issue_release 7", "codex-a",
            extra_env={"FAKE_GLAB_ON_BRANCH_DELETE": f"git -C {pusher} push --quiet origin issue/7"})

        self.assertIn("issue/7", self.remote_branches(remote), result.stdout + result.stderr)
        tip = subprocess.run(["git", "-C", str(remote), "rev-parse", "issue/7"], check=True,
                             capture_output=True, text=True).stdout.strip()
        self.assertEqual(tip, late)
        self.assertIn("issue/7 in core moved during release — kept", result.stdout)

    def test_release_refuses_while_a_sibling_issue_branch_holds_work(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=True)
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 1)
        self.assertIn("core", result.stdout)
        self.assertIn("issue/7", self.remote_branches(remote))
        self.assertIn("issue/7", self.load()["branches"])

    # #614, #645, #646, #867: the compare call answered 404 for a branch
    # deleted by hand, and release stopped before posting its note.
    def test_release_notes_the_release_when_the_claim_branch_is_already_gone(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        del state["branches"]["issue/7"]
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.load()["notes"]["7"][-1]["body"].startswith("release: session:"))
        self.assertIn("issue/7 is already gone", result.stdout)

    def private_with_issue_branch(self, number: int, commits: list[str]) -> Path:
        """`_private` as a clone whose issue/<N> writes each of `commits` to work.txt in turn."""
        remote = self.directory / "private.git"
        subprocess.run(["git", "init", "--quiet", "--bare", "--initial-branch=main", str(remote)], check=True)
        private = self.slot / "_private"
        git = ["git", "-C", str(private), "-c", "user.name=t", "-c", "user.email=t@e"]
        subprocess.run(["git", "-C", str(private), "init", "--quiet", "--initial-branch=main"], check=True)
        subprocess.run([*git, "remote", "add", "origin", str(remote)], check=True)
        subprocess.run([*git, "commit", "--quiet", "--allow-empty", "-m", "base"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", "main"], check=True)
        subprocess.run([*git, "switch", "--quiet", "-c", f"issue/{number}"], check=True)
        for content in commits:
            (private / "work.txt").write_text(content)
            subprocess.run([*git, "add", "work.txt"], check=True)
            subprocess.run([*git, "commit", "--quiet", "-m", f"work: {content.strip()}"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", f"issue/{number}"], check=True)
        subprocess.run([*git, "switch", "--quiet", "main"], check=True)
        return private

    def land_on_main(self, private: Path, content: str) -> None:
        git = ["git", "-C", str(private), "-c", "user.name=t", "-c", "user.email=t@e"]
        (private / "work.txt").write_text(content)
        subprocess.run([*git, "add", "work.txt"], check=True)
        subprocess.run([*git, "commit", "--quiet", "-m", "one commit in place of the branch"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", "main"], check=True)

    # #614, #867: main holds the branch's work as one commit (a squash, or a
    # replacement MR), so no patch ID matches and git cherry reports it unmerged.
    def test_release_treats_work_on_main_under_other_commits_as_merged(self) -> None:
        private = self.private_with_issue_branch(7, ["a\n", "a\nb\n"])
        self.land_on_main(private, "a\nb\n")
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.load()["branches"])

    # #713: after a rebase merge the claim branch merged main to stay alive
    # without a force push. That moved the merge base past main's copies of
    # its commits, so git cherry never compared against them.
    def test_release_treats_a_branch_that_merged_main_after_its_rebase_merge_as_merged(self) -> None:
        private = self.private_with_issue_branch(7, ["a\n", "a\nb\n"])
        git = ["git", "-C", str(private), "-c", "user.name=t", "-c", "user.email=t@e"]
        (private / "other.txt").write_text("other work\n")
        subprocess.run([*git, "add", "other.txt"], check=True)
        subprocess.run([*git, "commit", "--quiet", "-m", "other work on main"], check=True)
        subprocess.run([*git, "cherry-pick", "main..issue/7"], check=True, capture_output=True)
        subprocess.run([*git, "push", "--quiet", "origin", "main"], check=True)
        subprocess.run([*git, "switch", "--quiet", "issue/7"], check=True)
        subprocess.run([*git, "merge", "--quiet", "--no-edit", "main"], check=True, capture_output=True)
        subprocess.run([*git, "push", "--quiet", "origin", "issue/7"], check=True)
        cherry = subprocess.run([*git, "cherry", "origin/main", "origin/issue/7"], check=True,
                                capture_output=True, text=True).stdout
        self.assertEqual(cherry.count("+"), 2, "the arrangement must reproduce #713")
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.load()["branches"])

    def test_release_refuses_a_branch_whose_work_main_holds_only_in_part(self) -> None:
        private = self.private_with_issue_branch(7, ["a\n", "a\nb\n"])
        self.land_on_main(private, "a\n")
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("not on main", result.stdout)
        self.assertIn("issue/7", self.load()["branches"])

    def test_release_treats_a_squash_merged_sibling_branch_as_merged(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=True)
        core = self.slot / "core"
        git = ["git", "-C", str(core), "-c", "user.name=t", "-c", "user.email=t@e"]
        subprocess.run([*git, "switch", "--quiet", "main"], check=True)
        (core / "work.txt").write_text("work\n")
        (core / "notes.txt").write_text("from main\n")
        subprocess.run([*git, "add", "work.txt", "notes.txt"], check=True)
        subprocess.run([*git, "commit", "--quiet", "-m", "squashed with other work"], check=True)
        subprocess.run([*git, "push", "--quiet", "origin", "main"], check=True)
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("issue/7", self.remote_branches(remote))

    def test_queue_lists_open_issues_by_priority_with_their_holder(self) -> None:
        self.run_lib("issue_claim 9", "codex-a", check=True)

        lines = self.run_lib("issue_queue", "kimi-b", check=True).stdout.splitlines()

        rows = [line for line in lines if "#" in line]
        self.assertTrue(rows[0].lstrip().startswith("#7"), rows)
        self.assertIn("high", rows[0])
        self.assertIn("#9", rows[1])
        self.assertIn("claimed", rows[1])
        self.assertFalse(any("#3" in row for row in rows))

    def add_issues(self, *issues: tuple[int, str, str]) -> None:
        state = self.load()
        for number, priority, status in issues:
            labels = [f"priority::{priority}"] + ([f"status::{status}"] if status else [])
            state["issues"][str(number)] = {"iid": number, "state": "opened", "labels": labels,
                                            "title": f"Item {number}", "web_url": f"u{number}"}
        self.save(state)

    def test_queue_groups_by_board_column_and_counts_the_shelf(self) -> None:
        self.add_issues((11, "medium", "review"), (12, "critical", "backlog"),
                        (13, "high", "deferred"), (14, "critical", "refreshing"),
                        (15, "high", "implementing"), (16, "low", "select-solution"))

        lines = self.run_lib("issue_queue", "kimi-b", check=True).stdout.splitlines()

        def section(title: str) -> list[str]:
            start = next(i for i, line in enumerate(lines) if title in line)
            rows = []
            for line in lines[start + 1:]:
                if "#" not in line:
                    break
                rows.append(line.split()[0])
            return rows

        self.assertEqual(section("ready for agents"), ["#14", "#7", "#9"])
        self.assertEqual(section("waiting on maintainer"), ["#11", "#16"])
        self.assertEqual(section("in flight"), ["#15"])
        self.assertIn("refreshing", next(line for line in lines if "#14" in line))
        self.assertFalse(any("#12" in line or "#13" in line for line in lines))
        self.assertTrue(any("1 backlog" in line and "1 deferred" in line for line in lines))

    def test_queue_offers_verification_first_then_the_work_closest_to_done(self) -> None:
        # #449: testing is verified by whoever can, before anything new, and
        # within a priority planned work comes before planning or intake.
        self.add_issues((14, "critical", "refreshing"), (17, "high", "planned"),
                        (18, "medium", "testing"), (19, "high", "planning"),
                        (15, "high", "implementing"))

        lines = self.run_lib("issue_queue", "kimi-b", check=True).stdout.splitlines()

        def section(title: str) -> list[str]:
            start = next(i for i, line in enumerate(lines) if title in line)
            rows = []
            for line in lines[start + 1:]:
                if "#" not in line:
                    break
                rows.append(line.split()[0])
            return rows

        titles = [line.strip() for line in lines if "#" not in line and line.strip()]
        self.assertLess(titles.index(next(t for t in titles if t.startswith("verify first"))),
                        titles.index("ready for agents"))
        self.assertEqual(section("verify first"), ["#18"])
        self.assertEqual(section("ready for agents"), ["#14", "#17", "#19", "#7", "#9"])
        self.assertEqual(section("in flight"), ["#15"])

    def test_queue_shows_what_a_testing_item_needs_to_be_verified(self) -> None:
        self.add_issues((18, "medium", "testing"), (20, "low", "testing"))
        state = self.load()
        state["issues"]["18"]["labels"].append("verify::rig")
        self.save(state)

        lines = self.run_lib("issue_queue", "kimi-b", check=True).stdout.splitlines()

        self.assertIn("[verify:rig]", next(line for line in lines if "#18" in line))
        self.assertNotIn("[verify:", next(line for line in lines if "#20" in line))

    def test_queue_reads_every_page_of_open_issues(self) -> None:
        self.add_issues(*((number, "low", "intake") for number in range(100, 205)))

        output = self.run_lib("issue_queue", "kimi-b", check=True).stdout

        self.assertIn("#204", output)

    def test_board_prints_columns_in_lifecycle_order_and_folds_the_shelf(self) -> None:
        self.add_issues((12, "low", "backlog"), (11, "medium", "review"),
                        (14, "high", "refreshing"))

        folded = self.run_lib("issue_board", "kimi-b", check=True).stdout
        full = self.run_lib("issue_board all", "kimi-b", check=True).stdout

        headers = [line for line in folded.splitlines() if line.startswith("──")]
        self.assertEqual([h.split()[1] for h in headers],
                         ["backlog", "intake", "refreshing", "review"])
        self.assertIn("── backlog (1) ──", folded)
        self.assertIn("── intake (2) ──", folded)
        self.assertNotIn("#12", folded)
        self.assertIn("#12", full)

    def test_comment_posts_the_body_signed_with_session_and_slot(self) -> None:
        result = self.run_lib("issue_comment 7 'Merged in !12.'", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        note = self.load()["notes"]["7"][-1]
        self.assertRegex(note["body"], r"^Merged in !12\.\n\n— session:[0-9a-f]{12} slot:[^ ]+/vauchi-1/codex$")
        self.assertIn(f"note {note['id']}", result.stdout)

    def test_comment_refuses_an_empty_body(self) -> None:
        for body in ("''", "'   '"):
            with self.subTest(body=body):
                result = self.run_lib(f"issue_comment 7 {body}", "codex-a")

                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.load()["notes"].get("7", []), [])

    def test_respond_replies_in_the_thread_of_the_named_note(self) -> None:
        self.run_lib("issue_comment 7 'Is the relay fixed?'", "kimi-b", check=True)
        question = self.load()["notes"]["7"][-1]

        result = self.run_lib(f"issue_comment_respond 7 {question['id']} 'Yes, in !12.'", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        thread = self.load()["discussions"]["7"][0]
        self.assertEqual(thread["notes"][0]["id"], question["id"])
        self.assertTrue(thread["notes"][-1]["body"].startswith("Yes, in !12.\n\n— session:"))

    def test_respond_to_an_unknown_note_fails_and_posts_nothing(self) -> None:
        for note in ("424242", "not-a-number"):
            with self.subTest(note=note):
                result = self.run_lib(f"issue_comment_respond 7 {note} 'Reply'", "codex-a")

                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.load()["notes"].get("7", []), [])

    def test_closing_keywords_before_an_issue_reference_are_detected(self) -> None:
        # GitLab closes these issues on merge, bypassing the status sync (#70).
        closing = [
            "docs: close #14 — alert delivery proven end to end",
            "Fixes #7",
            "resolved vauchi/private#58",
            "Implements: #3 and more",
            "closing issue #12",
        ]
        harmless = [
            "docs: Uptime-Kuma notifies via ntfy (#14)",
            "refs vauchi/private#58",
            "close the gap described in #14",
            "no issue here",
        ]
        for text in closing + harmless:
            with self.subTest(text=text):
                result = self.run_lib(f"issue_closing_reference {json.dumps(text)}", "codex-a")
                if text in closing:
                    self.assertEqual(result.returncode, 0, text)
                    self.assertIn("#", result.stdout)
                else:
                    self.assertEqual(result.returncode, 1, result.stdout)

    def open_mr(self, put_failures: int) -> None:
        state = self.load()
        state["mrs"] = {"2804": {"iid": 2804, "state": "opened", "source_branch": "issue/308",
                                 "force_remove_source_branch": True}}
        state["put_failures"] = put_failures
        self.save(state)

    def keep_branch(self) -> subprocess.CompletedProcess[str]:
        return self.run_lib("ISSUE_KEEP_BRANCH_RETRY_DELAY=0 issue_keep_mr_branch vauchi/private issue/308",
                            "codex-a")

    def test_keep_branch_retries_a_500_right_after_creation(self) -> None:
        self.open_mr(put_failures=1)

        result = self.keep_branch()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.load()["mrs"]["2804"]["force_remove_source_branch"])
        self.assertIn("!2804 keeps issue/308 after merge", result.stdout)

    def test_keep_branch_fails_loudly_when_every_attempt_errors(self) -> None:
        self.open_mr(put_failures=99)

        result = self.keep_branch()

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.load()["mrs"]["2804"]["force_remove_source_branch"])
        self.assertIn("!2804", result.stderr)
        self.assertIn("remove_source_branch=false", result.stderr)


if __name__ == "__main__":
    unittest.main()
