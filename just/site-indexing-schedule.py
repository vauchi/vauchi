# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Configure the nightly live audit using the authenticated GitLab account."""

import json
import subprocess

PROJECT = "projects/vauchi%2Fprivate"
ENDPOINT = PROJECT + "/pipeline_schedules"
INPUTS = [{"name": "site_indexing", "value": "live"}]
SETTINGS = {
    "description": "site-indexing-live",
    "ref": "main",
    "cron": "23 6 * * *",
    "cron_timezone": "UTC",
}


def api(endpoint, method="GET", **fields):
    command = ["glab", "api", endpoint]
    if method != "GET":
        command.extend(["-X", method, "--input", "-"])
    result = subprocess.run(
        command,
        input=json.dumps(fields) if method != "GET" else None,
        check=True,
        text=True,
        capture_output=True,
        timeout=30,
    )
    return result.stdout if "/raw?" in endpoint else json.loads(result.stdout)


def ensure_schedule(backend=api):
    root = backend(PROJECT + "/repository/files/.gitlab-ci.yml/raw?ref=main")
    job = backend(
        PROJECT + "/repository/files/infra%2Fci%2Fsite-indexing.yml/raw?ref=main"
    )
    if (
        "infra/ci/site-indexing.yml" not in root
        or "check:site-indexing-live" not in job
    ):
        raise ValueError(
            "Merge the indexing CI configuration to private/main before scheduling it"
        )
    matches = []
    page = 1
    while True:
        schedules = backend(f"{ENDPOINT}?per_page=100&page={page}")
        matches.extend(
            s for s in schedules if s["description"] == SETTINGS["description"]
        )
        if len(schedules) < 100:
            break
        page += 1
    if len(matches) > 1:
        raise ValueError(
            "Multiple site-indexing-live schedules exist; reconcile them first"
        )
    if matches:
        schedule = backend(f"{ENDPOINT}/{matches[0]['id']}")
    else:
        schedule = backend(ENDPOINT, "POST", **SETTINGS, active=False, inputs=INPUTS)
    for key in ("description", "cron", "cron_timezone"):
        if schedule.get(key) != SETTINGS[key]:
            raise ValueError(f"Conflicting schedule {key}; no settings overwritten")
    if schedule.get("ref") not in ("main", "refs/heads/main"):
        raise ValueError("Conflicting schedule ref")
    if schedule.get("inputs") != INPUTS or schedule.get("variables") != []:
        raise ValueError("Conflicting inputs or unexpected schedule variables")
    endpoint = f"{ENDPOINT}/{schedule['id']}"
    if not schedule["active"]:
        backend(endpoint, "PUT", active=True)
    verified = backend(endpoint)
    if (
        verified["active"] is not True
        or verified.get("inputs") != INPUTS
        or verified.get("variables") != []
    ):
        raise RuntimeError("Schedule verification failed")
    return verified["id"]


if __name__ == "__main__":
    try:
        schedule_id = ensure_schedule()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr.strip() or str(error)) from error
    print(
        f"Verified nightly audit at 06:23 UTC: https://gitlab.com/vauchi/private/-/pipeline_schedules/{schedule_id}/edit"
    )
