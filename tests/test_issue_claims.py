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
    print(json.dumps(value)); json.dump(state, open(state_path, "w")); sys.exit(0)

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
    if method == "POST":
        note = new_note(parts[3], fields["body"])
        state.setdefault("discussions", {}).setdefault(parts[3], []).append(
            {"id": "thread-%d" % note["id"], "notes": [note]})
        out(note)
    out(list(reversed(state["notes"].setdefault(parts[3], []))))
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
        state["branches"].pop(parts[4].replace("%2F", "/"), None); out({})
    if len(parts) == 5:
        branch = state["branches"].get(parts[4].replace("%2F", "/"))
        out(branch) if branch else fail("404 Branch Not Found")
    prefix = query.partition("search=")[2].split("&")[0].lstrip("^")
    out([b for n, b in state["branches"].items() if n.startswith(prefix)])
if parts[2] == "repository" and parts[3] == "compare":
    to = query.partition("to=")[2].split("&")[0].replace("%2F", "/")
    out({"commits": [{}] * state["branches"][to]["ahead"]})
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

    def run_lib(self, command: str, session: str, check: bool = False) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "PATH": self.path, "FAKE_GLAB_STATE": str(self.state),
                       "VAUCHI_SESSION_ID": session}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        return subprocess.run(
            ["bash", "-c", f'source just/slot-lib.sh; source just/issue-lib.sh; {command}'],
            cwd=self.slot, env=environment, check=check, capture_output=True, text=True,
        )

    def test_claim_creates_the_issue_branch_and_names_session_and_slot(self) -> None:
        result = self.run_lib("issue_claim 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.load()
        self.assertIn("issue/7", state["branches"])
        self.assertRegex(state["notes"]["7"][0]["body"],
                         r"^claim: session:[0-9a-f]{12} slot:[^ ]+/vauchi-1$")

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

    def test_release_deletes_an_empty_claim_branch_and_notes_it(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("issue/7", self.load()["branches"])
        self.assertTrue(self.load()["notes"]["7"][-1]["body"].startswith("release: session:"))

    def test_release_refuses_a_branch_holding_unmerged_work(self) -> None:
        self.run_lib("issue_claim 7", "codex-a", check=True)
        state = self.load()
        state["branches"]["issue/7"]["ahead"] = 2
        self.save(state)

        result = self.run_lib("issue_release 7", "codex-a")

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

    def test_release_refuses_while_a_sibling_issue_branch_holds_work(self) -> None:
        remote = self.sibling_with_issue_branch(7, unmerged=True)
        self.run_lib("issue_claim 7", "codex-a", check=True)

        result = self.run_lib("issue_release 7", "codex-a")

        self.assertEqual(result.returncode, 1)
        self.assertIn("core", result.stdout)
        self.assertIn("issue/7", self.remote_branches(remote))
        self.assertIn("issue/7", self.load()["branches"])

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
        self.assertRegex(note["body"], r"^Merged in !12\.\n\n— session:[0-9a-f]{12} slot:[^ ]+/vauchi-1$")
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


if __name__ == "__main__":
    unittest.main()
