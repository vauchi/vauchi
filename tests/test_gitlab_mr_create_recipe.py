# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise real local push hooks while GitLab remains an external boundary."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOLVER = """resolve_gitlab_repo() { echo "$1"; }
resolve_gitlab_project() { echo "vauchi/$1"; }
gitlab_repo_dir() { echo "$1"; }
_dir_to_gitlab_name() { echo "$1"; }
"""
GLAB = r"""#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:3] == ["auth", "status"]:
    sys.exit(0)
with open(os.environ["GLAB_CALL_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\n")
route = sys.argv[2] if sys.argv[1] == "api" else ""
if "source_branch=" in route:
    print(json.dumps([{"iid": 1}]))
elif "merge_requests/1" in route:
    if os.environ.get("MR_FAIL_DESCRIPTION") == "1":
        sys.exit(1)
    print(json.dumps({"iid": 1, "draft": True, "diverged_commits_count": 0, "head_pipeline": None,
                      "description": os.environ.get("MR_EXISTING_DESC", "")}))
elif "state=opened" in route:
    print(json.dumps([{"iid": 1, "draft": True}]))
elif route == "projects/vauchi%2Fcore":
    # The ready queue asks whether the project runs a merge train.
    print(json.dumps({"merge_trains_enabled": False}))
else:
    print("https://gitlab.test/vauchi/core/-/merge_requests/1")
"""
HOOK = """#!/bin/sh
printf '%s\n' "${SKIP_TESTS:-unset}" >> "$HOOK_LOG"
[ ! -f "$REFUSE_PUSH" ]
"""


class MrCreateRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.ws = base / "workspace"
        self.ws.mkdir()
        shutil.copy2(ROOT / "justfile", self.ws / "justfile")
        shutil.copytree(ROOT / "just", self.ws / "just")
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "resolve-repo.sh").write_text(RESOLVER)
        shutil.copy2(ROOT / "scripts/scripts/escape-mr-mentions.py", helpers)
        self.repo = self.ws / "core"
        self.remote = base / "remote.git"
        self.git(self.ws, "init", "--bare", "--initial-branch=main", str(self.remote))
        self.git(self.ws, "init", "--initial-branch=main", str(self.repo))
        self.git(self.repo, "config", "user.name", "Recipe Test")
        self.git(self.repo, "config", "user.email", "recipe@example.test")
        hooks = base / "hooks"
        hooks.mkdir()
        self.git(self.repo, "config", "core.hooksPath", str(hooks))
        self.git(self.repo, "commit", "--allow-empty", "-m", "chore: initial")
        self.git(self.repo, "remote", "add", "origin", str(self.remote))
        self.git(self.repo, "push", "origin", "main")
        self.git(self.repo, "switch", "-c", "feature/mr-test")
        self.git(self.repo, "commit", "--allow-empty", "-m", "fix: recipe contract",
                 "-m", 'Tools used: "Codex (OpenAI)"')
        hook = hooks / "pre-push"
        hook.write_text(HOOK)
        hook.chmod(0o755)
        commands = base / "bin"
        commands.mkdir()
        glab = commands / "glab"
        glab.write_text(GLAB)
        glab.chmod(0o755)
        self.calls = base / "glab.jsonl"
        self.hook_log = base / "hook.log"
        self.refuse = base / "refuse"
        self.env = dict(os.environ, JUST_UNSTABLE="1", MR_NO_AUTOLINK="1",
                        MR_DRAFT="1", GLAB_CALL_LOG=str(self.calls),
                        HOOK_LOG=str(self.hook_log), REFUSE_PUSH=str(self.refuse),
                        PATH=f"{commands}{os.pathsep}{os.environ['PATH']}")
        self.env.pop("SKIP_TESTS", None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["git", "-C", str(repo), *args], check=True,
                              capture_output=True, text=True)

    def create(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["just", "gitlab", "mr-create", "core",
                               "fix: recipe contract", *extra], cwd=self.ws,
                              env=self.env, capture_output=True, text=True)

    def requests(self) -> list[list[str]]:
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_publication_runs_the_normal_push_hook(self) -> None:
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        requests = self.requests()
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][:2], ["mr", "create"])
        self.assertIn("--draft", requests[0])
        self.assertEqual(requests[0][requests[0].index("--description") + 1],
                         '- fix: recipe contract\n\nTools used: "Codex (OpenAI)"')

    def test_an_mr_created_ready_goes_through_the_ready_queue(self) -> None:
        self.env.pop("MR_DRAFT")
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        requests = self.requests()
        self.assertEqual(requests[0][:2], ["mr", "create"])
        self.assertIn("--draft", requests[0])
        self.assertEqual(requests[-1], ["mr", "update", "1", "--ready", "-R", "vauchi/core"])
        self.assertIn("first in the core ready queue", result.stdout)

    def test_a_rejected_push_does_not_create_an_mr_or_retry_forcefully(self) -> None:
        self.refuse.touch()
        result = self.create()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.hook_log.exists(), result.stdout + result.stderr)
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        self.assertEqual(self.requests(), [])


    def test_a_description_file_preserves_newlines_quotes_and_literal_shell_text(self) -> None:
        body = "## Summary\nKeep Bob's \"quoted\" value and $(touch should-not-exist).\n\n## Test Plan\n- [x] Observed RED then GREEN."
        description = self.ws / "reviewer's description.md"
        description.write_text(body)
        result = self.create(str(description))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = self.requests()[0]
        self.assertEqual(request[request.index("--description") + 1],
                         body + '\n\nTools used: "Codex (OpenAI)"')
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        self.assertFalse((self.ws / "should-not-exist").exists())

    def test_a_missing_description_file_stops_before_publication(self) -> None:
        result = self.create(str(self.ws / "missing.md"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or empty description file", result.stdout + result.stderr)
        self.assertFalse(self.hook_log.exists())
        self.assertEqual(self.requests(), [])


    def test_view_can_read_comments_without_publishing(self) -> None:
        result = subprocess.run(["just", "gitlab", "mr-view", "18", "core", "true"],
                                cwd=self.ws, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests(), [["mr", "view", "18", "-R", "vauchi/core", "--comments"]])
        self.assertFalse(self.hook_log.exists())

    def test_creation_collects_all_tools_from_legacy_and_current_credits(self) -> None:
        self.git(self.repo, "commit", "--allow-empty", "-m", "docs: another contribution",
                 "-m", 'Tools used: "Kimi (Moonshot AI)", "Codex (OpenAI)"',
                 "-m", "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>")
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        body = self.requests()[0]
        body = body[body.index("--description") + 1]
        self.assertEqual(body.count("Tools used:"), 1)
        self.assertNotIn("Co-Authored-By:", body)
        self.assertTrue(body.endswith(
            'Tools used: "Codex (OpenAI)", "Kimi (Moonshot AI)", "Claude (Anthropic)"'))

    def test_creation_replaces_the_generated_with_footer(self) -> None:
        description = self.ws / "description.md"
        description.write_text("## Result\nUseful change.\n\n🤖 Generated with [Claude Code](https://claude.ai/code)")
        result = self.create(str(description))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = self.requests()[0]
        self.assertEqual(request[request.index("--description") + 1],
                         '## Result\nUseful change.\n\nTools used: "Codex (OpenAI)", "Claude (Anthropic)"')

    def test_invalid_tools_stop_before_push_or_creation(self) -> None:
        for value in ['"Codex (Anthropic)"', '"Codex (OpenAI)", "Unknown (Provider)"', '',
                      '"Codex (OpenAI)" trailing text']:
            with self.subTest(value=value):
                description = self.ws / "description.md"
                description.write_text("## Result\nUseful change.\n\nTools used: " + value)
                result = self.create(str(description))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Tools used", result.stdout + result.stderr)
                self.assertFalse(self.hook_log.exists())
                self.assertEqual(self.requests(), [])

    def test_editing_collects_tools_and_replaces_generated_credit(self) -> None:
        description = self.ws / "description.md"
        description.write_text("## Result\nUpdated explanation.\n\n🤖 Generated with Kimi Code")
        result = subprocess.run(
            ["just", "gitlab", "mr-update", "core", "fix: recipe contract", str(description)],
            cwd=self.ws, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updates = [call for call in self.requests() if call[:2] == ["mr", "update"]]
        self.assertEqual(len(updates), 1)
        request = updates[0]
        self.assertEqual(request[request.index("--description") + 1],
                         '## Result\nUpdated explanation.\n\nTools used: "Codex (OpenAI)", "Kimi (Moonshot AI)"')
        self.assertFalse(self.hook_log.exists())

    def test_editing_a_draft_keeps_its_draft_mark(self) -> None:
        # A title without the prefix marks the MR ready, and a queued Draft
        # then jumps its queue or train (private!4024, 2026-11-10; #1208).
        description = self.ws / "description.md"
        description.write_text('## Result\nRefreshed.\n\nTools used: "Codex (OpenAI)"')
        result = subprocess.run(
            ["just", "gitlab", "mr-update", "core", "fix: recipe contract", str(description)],
            cwd=self.ws, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updates = [call for call in self.requests() if call[:2] == ["mr", "update"]]
        self.assertEqual(len(updates), 1)
        request = updates[0]
        self.assertEqual(request[request.index("--title") + 1], "Draft: fix: recipe contract")

    def test_invalid_edit_does_not_publish(self) -> None:
        description = self.ws / "description.md"
        description.write_text('Tools used: "Claude (OpenAI)"')
        result = subprocess.run(
            ["just", "gitlab", "mr-update", "core", "fix: recipe contract", str(description)],
            cwd=self.ws, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tools used", result.stdout + result.stderr)
        self.assertFalse(any(call[:2] == ["mr", "update"] for call in self.requests()))

    def test_missing_provenance_stops_before_publication(self) -> None:
        self.git(self.repo, "commit", "--amend", "--allow-empty", "-m", "fix: recipe contract")
        result = self.create()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tools used: missing", result.stdout + result.stderr)
        self.assertFalse(self.hook_log.exists())
        self.assertEqual(self.requests(), [])

    def test_unreadable_history_stops_before_publication(self) -> None:
        self.git(self.repo, "update-ref", "-d", "refs/remotes/origin/main")
        result = self.create()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tools used", result.stdout + result.stderr)
        self.assertFalse(self.hook_log.exists())
        self.assertEqual(self.requests(), [])

    def test_credit_examples_in_code_blocks_remain_literal(self) -> None:
        body = 'Example:\n```text\nTools used: "Codex (Anthropic)"\n```'
        description = self.ws / "description.md"
        description.write_text(body)
        result = self.create(str(description))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = self.requests()[0]
        self.assertEqual(request[request.index("--description") + 1],
                         body + '\n\nTools used: "Codex (OpenAI)"')

    def test_autolink_edits_normalize_existing_credits(self) -> None:
        self.env.pop("MR_NO_AUTOLINK")
        self.git(self.ws, "clone", str(self.repo), str(self.ws / "cli"))
        self.env["MR_EXISTING_DESC"] = "Prior result.\n\n🤖 Generated with Claude Code"
        result = subprocess.run(["just", "gitlab", "_autolink", "core"], cwd=self.ws,
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updates = [call for call in self.requests() if call[:3] == ["api", "-X", "PUT"]]
        self.assertEqual(len(updates), 2)
        for update in updates:
            body = next(arg.removeprefix("description=") for arg in update if arg.startswith("description="))
            self.assertNotIn("Generated with", body)
            self.assertTrue(body.endswith('Tools used: "Codex (OpenAI)", "Claude (Anthropic)"'))

    def test_invalid_autolink_description_is_not_published(self) -> None:
        self.env.pop("MR_NO_AUTOLINK")
        self.git(self.ws, "clone", str(self.repo), str(self.ws / "cli"))
        self.env["MR_EXISTING_DESC"] = 'Tools used: "Codex (Anthropic)"'
        result = subprocess.run(["just", "gitlab", "_autolink", "core"], cwd=self.ws,
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tools used", result.stdout + result.stderr)
        self.assertFalse(any(call[:3] == ["api", "-X", "PUT"] for call in self.requests()))

    def test_an_unclosed_commit_example_does_not_hide_later_contributors(self) -> None:
        self.git(self.repo, "commit", "--allow-empty", "-m", "docs: unfinished example",
                 "-m", "```text\nExample content")
        self.git(self.repo, "commit", "--allow-empty", "-m", "docs: another contribution",
                 "-m", 'Tools used: "Kimi (Moonshot AI)"')
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = self.requests()[0]
        self.assertTrue(request[request.index("--description") + 1].endswith(
            'Tools used: "Codex (OpenAI)", "Kimi (Moonshot AI)"'))

    def test_autolink_read_failure_does_not_replace_the_description(self) -> None:
        self.env.pop("MR_NO_AUTOLINK")
        self.git(self.ws, "clone", str(self.repo), str(self.ws / "cli"))
        self.env["MR_FAIL_DESCRIPTION"] = "1"
        result = subprocess.run(["just", "gitlab", "_autolink", "core"], cwd=self.ws,
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:3] == ["api", "-X", "PUT"] for call in self.requests()))


if __name__ == "__main__":
    unittest.main()
