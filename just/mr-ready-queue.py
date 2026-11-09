# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Mark an MR ready only when it is next in its repository's ready queue.

With fast-forward merges GitLab rebases a behind MR at merge time and merges
on its earlier green pipeline, so two ready MRs merged back to back land a
tree no pipeline tested. Merge trains were rejected (vauchi/private#1179,
decision 4), so agents queue: one live ready MR per repository, rebased on
main. A later MR stays Draft, stops its pipeline, and both MRs say so.

Usage: mr-ready-queue.py <group/project> <iid> <repo>
       mr-ready-queue.py --waiting   (queued Drafts whose MR ahead is no longer open)
"""

import json
import os
import re
import subprocess
import sys
import time

STOPPABLE = {"created", "waiting_for_resource", "preparing", "pending", "running", "scheduled"}
# A ready MR whose pipeline failed cannot be merged as it is, so it does not hold the queue.
NOT_HOLDING = {"failed", "canceled"}


def glab(*args):
    out = subprocess.run(["glab", *args], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"ERROR: glab {' '.join(args[:2])} failed: {out.stderr.strip() or out.stdout.strip()}")
    return json.loads(out.stdout or "null") if args[0] == "api" else None


def main(project, iid, repo):
    api = f"projects/{project.replace('/', '%2F')}"
    own = glab("api", f"{api}/merge_requests/{iid}?include_diverged_commits_count=true")

    def holds_queue(mr):
        if mr["iid"] == own["iid"] or mr["draft"]:
            return False
        full = glab("api", f"{api}/merge_requests/{mr['iid']}")
        return (full.get("head_pipeline") or {}).get("status") not in NOT_HOLDING

    opened = glab("api", f"{api}/merge_requests?state=opened&per_page=100")
    # Lower iid first, so two sessions racing to ready agree on who waits.
    ahead = sorted((m for m in opened if holds_queue(m) and (own["draft"] or m["iid"] < own["iid"])),
                   key=lambda m: m["iid"])
    if ahead:
        wait_behind(api, own, ahead[0]["iid"], repo)
        return 0

    behind = own.get("diverged_commits_count") or 0
    if behind:
        rebase = (f"run `just gitlab mr-rebase {iid} {repo}`" if own["source_branch"].startswith("chore/bump-")
                  else "rebase onto origin/main and push")
        print(f"NOT READY: !{iid} is {behind} commits behind main; {rebase}, "
              f"then run `just gitlab mr-ready {iid} {repo}` again.")
        return 1

    if own["draft"]:
        glab("mr", "update", str(iid), "--ready", "-R", project)
    print(f"!{iid} is ready and first in the {repo} ready queue.")
    return 0


def mr_pipelines(api, own):
    """The MR's pipelines; for a just-opened MR, waits for GitLab to create the first.

    GitLab creates an MR's pipeline seconds after the MR (core!2287 was
    queued before it existed, so nothing was cancelled).
    """
    if own.get("head_pipeline"):
        return [own["head_pipeline"]]
    interval = float(os.environ.get("READY_QUEUE_POLL_INTERVAL", "3"))
    for _ in range(int(os.environ.get("READY_QUEUE_POLLS", "10"))):
        found = glab("api", f"{api}/merge_requests/{own['iid']}/pipelines")
        if found:
            return found
        time.sleep(interval)
    return []


def wait_behind(api, own, ahead_iid, repo):
    iid = own["iid"]
    project = api.removeprefix("projects/").replace("%2F", "/")
    if not own["draft"]:
        glab("mr", "update", str(iid), "--draft", "-R", project)
    ids = [p["id"] for p in mr_pipelines(api, own) if p.get("status") in STOPPABLE]
    for pipeline_id in ids:
        glab("api", "-X", "POST", f"{api}/pipelines/{pipeline_id}/cancel")
    stopped = ""
    if ids:
        stopped = (f" Its pipeline {', '.join(map(str, ids))} is cancelled: "
                   "it would test a tree that is not the one that lands.")
    glab("api", "-X", "POST", f"{api}/merge_requests/{iid}/notes", "-f",
         f"body=ready-queue: waiting behind !{ahead_iid}, which is ready, so this MR stays Draft.{stopped} "
         f"After !{ahead_iid} merges: rebase onto main, push, and run `just gitlab mr-ready {iid} {repo}`.")
    glab("api", "-X", "POST", f"{api}/merge_requests/{ahead_iid}/notes", "-f",
         f"body=ready-queue: !{iid} waits for this MR to merge, then rebases on it.")
    print(f"WAITING: !{iid} is waiting behind !{ahead_iid} (Draft{', pipeline cancelled' if stopped else ''}). "
          f"After !{ahead_iid} merges, rebase and run `just gitlab mr-ready {iid} {repo}` again.")


WAITING_NOTE = re.compile(r"^ready-queue: waiting behind !(\d+)")


def waiting():
    for draft in glab("api", "groups/vauchi/merge_requests?state=opened&wip=yes&scope=all&per_page=100") or []:
        api = f"projects/{draft['project_id']}"
        notes = glab("api", f"{api}/merge_requests/{draft['iid']}/notes?sort=desc&order_by=created_at&per_page=100")
        latest = next((m for m in (WAITING_NOTE.match(n["body"]) for n in notes) if m), None)
        if latest is None:
            continue
        ahead = glab("api", f"{api}/merge_requests/{latest.group(1)}")
        # The MR ahead holds the queue only while it is open, ready and not red.
        if ahead["state"] != "opened":
            why = ahead["state"]
        elif ahead["draft"]:
            why = "draft"
        elif (ahead.get("head_pipeline") or {}).get("status") in NOT_HOLDING:
            why = ahead["head_pipeline"]["status"]
        else:
            continue
        repo = draft["references"]["full"].split("!")[0].rsplit("/", 1)[-1]
        # A bot's bump branch is rebased by GitLab; agents never push it.
        if draft["source_branch"].startswith("chore/bump-"):
            step = f"just gitlab mr-rebase {draft['iid']} {repo}, then"
        else:
            step = "rebase onto main, push, then"
        print(f"  {repo} !{draft['iid']}: !{latest.group(1)} {why} — {step}: "
              f"just gitlab mr-ready {draft['iid']} {repo}")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["--waiting"]:
        sys.exit(waiting())
    sys.exit(main(*sys.argv[1:4]))
