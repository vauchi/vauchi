# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Export sanitized GitLab certification evidence using existing glab auth."""

import argparse
import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path

from tools.certification_contract import REQUIRED_CASES
from tools.release_evidence import (
    EvidenceError, MAX_BYTES, PIPELINE_KEYS, decode_json, require, validate_report,
)

PROJECT = "projects/vauchi%2Fe2e"


def _bounded_output(command):
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        try:
            deadline = time.monotonic() + 60
            raw = bytearray()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    remaining = max(0, deadline - time.monotonic())
                    if not selector.select(remaining):
                        raise subprocess.TimeoutExpired(command, 60)
                    chunk = os.read(process.stdout.fileno(), min(65536, MAX_BYTES + 1 - len(raw)))
                    if not chunk:
                        break
                    raw.extend(chunk)
                    require(len(raw) <= MAX_BYTES, "GitLab response exceeds size limit")
            status = process.wait(timeout=max(0, deadline - time.monotonic()))
            if status:
                raise subprocess.CalledProcessError(status, command)
            return bytes(raw)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def gitlab_fetch(endpoint):
    try:
        raw = _bounded_output(["glab", "api", "--hostname", "gitlab.com", endpoint])
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceError("certification evidence: GitLab request failed") from error
    if "/artifacts/" in endpoint:
        return raw.decode("ascii").strip()
    return decode_json(raw)


def _jobs(fetch, prefix):
    jobs = []
    for page in range(1, 11):
        batch = fetch(prefix + f"/jobs?per_page=100&page={page}")
        require(type(batch) is list and len(batch) <= 100, "invalid job page")
        jobs.extend(batch)
        if len(batch) < 100:
            return jobs
    raise EvidenceError("certification evidence: too many job pages")


def _one(items, name):
    found = [item for item in items if item["name"] == name]
    require(len(found) == 1, "missing or duplicate job/report: " + name)
    return found[0]


def _collect(pipeline_id, expected_revision, fetch, now):
    require(type(pipeline_id) is int and pipeline_id > 0, "invalid requested pipeline")
    prefix = PROJECT + f"/pipelines/{pipeline_id}"
    pipeline = {key: value for key, value in fetch(prefix).items() if key in PIPELINE_KEYS}
    require(pipeline["id"] == pipeline_id, "requested pipeline mismatch")
    jobs = _jobs(fetch, prefix)
    suites = fetch(prefix + "/test_report")["test_suites"]
    require(type(suites) is list and len(suites) <= 1000, "invalid test suites")
    lanes = []
    for name in REQUIRED_CASES:
        job, suite = _one(jobs, name), _one(suites, name)
        parent = job["pipeline"]
        require(parent["project_id"] == pipeline["project_id"], "mixed job project")
        require(suite["suite_error"] is None, "JUnit parser error in " + name)
        cases = suite["test_cases"]
        require(type(cases) is list and 0 < len(cases) <= 128, "empty or oversized lane")
        for field, expected in (("total_count", len(cases)), ("success_count", len(cases)),
                                ("failed_count", 0), ("error_count", 0), ("skipped_count", 0)):
            require(type(suite[field]) is int and suite[field] == expected,
                    "inconsistent test counts in " + name)
        lanes.append({
            "name": name, "job_id": job["id"], "pipeline_id": parent["id"],
            "sha": parent["sha"], "status": job["status"],
            "allow_failure": job["allow_failure"], "finished_at": job["finished_at"],
            "cases": [{key: case[key] for key in ("name", "classname", "status")}
                      for case in cases],
        })
    smoke = _one(jobs, "test:smoke")
    require(type(smoke["id"]) is int and smoke["id"] > 0,
            "invalid binary artifact job identity")
    require(smoke["status"] == "success" and smoke["allow_failure"] is False
            and smoke["pipeline"]["id"] == pipeline_id
            and smoke["pipeline"]["project_id"] == pipeline["project_id"]
            and smoke["pipeline"]["sha"] == expected_revision,
            "binary provenance job must pass in the same pipeline")
    sources = {"e2e": pipeline["sha"]}
    for name, filename in (("cli", "cli"), ("relay", "relay"), ("ohttp-relay", "ohttp")):
        sources[name] = fetch(PROJECT + f"/jobs/{smoke['id']}/artifacts/.smoke-bin/{filename}.sha").strip()
    report = {"schema_version": 1, "scope": "automated-privacy-multidevice",
              "pipeline": pipeline, "sources": sources, "lanes": lanes}
    validate_report(report, expected_revision, now=now)
    return report


def collect(pipeline_id, expected_revision, *, fetch=None, now=None):
    try:
        return _collect(pipeline_id, expected_revision, fetch or gitlab_fetch, now)
    except (KeyError, TypeError, ValueError, AttributeError, RecursionError) as error:
        raise EvidenceError("certification evidence: malformed GitLab response") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pipeline", type=int)
    parser.add_argument("revision")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = collect(args.pipeline, args.revision)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    except (EvidenceError, OSError) as error:
        print(str(error) if isinstance(error, EvidenceError)
              else "certification evidence: cannot write report", file=sys.stderr)
        return 1
    print("Automated certification evidence: 7 blocking lanes verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
