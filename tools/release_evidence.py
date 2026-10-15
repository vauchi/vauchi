# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Validate automated evidence without declaring the product release-ready."""

import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tools.certification_contract import REQUIRED_CASES

MAX_BYTES = 2 * 1024 * 1024
MAX_AGE = timedelta(days=7)
PIPELINE_KEYS = {
    "id", "project_id", "sha", "ref", "status", "created_at", "finished_at", "web_url"
}


class EvidenceError(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise EvidenceError("certification evidence: " + reason)


def _keys(value, expected):
    require(type(value) is dict and set(value) == expected, "invalid schema fields")


def _revision(value):
    return type(value) is str and re.fullmatch(r"[0-9a-f]{40}", value) is not None


def _positive_id(value):
    return type(value) is int and value > 0


def _timestamp(value):
    require(type(value) is str and len(value) <= 40, "invalid timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, "timestamp has no timezone")
    return parsed.astimezone(timezone.utc)


def _validate(report, expected_revision, now):
    _keys(report, {"schema_version", "scope", "pipeline", "sources", "lanes"})
    require(type(report["schema_version"]) is int and report["schema_version"] == 1,
            "unsupported schema version")
    require(report["scope"] == "automated-privacy-multidevice", "invalid report scope")
    pipeline = report["pipeline"]
    _keys(pipeline, PIPELINE_KEYS)
    require(_positive_id(pipeline["id"]) and _positive_id(pipeline["project_id"]),
            "invalid pipeline identity")
    require(_revision(expected_revision) and pipeline["sha"] == expected_revision,
            "E2E revision mismatch")
    require(pipeline["ref"] == "main" and pipeline["status"] == "success",
            "pipeline must have passed on main")
    require(pipeline["web_url"] ==
            f"https://gitlab.com/vauchi/e2e/-/pipelines/{pipeline['id']}", "invalid project URL")
    created = _timestamp(pipeline["created_at"])
    finished = _timestamp(pipeline["finished_at"])
    require(created <= finished <= now, "invalid or future pipeline time")
    require(now - created <= MAX_AGE, "pipeline is older than seven days")
    sources = report["sources"]
    _keys(sources, {"e2e", "cli", "relay", "ohttp-relay"})
    require(all(_revision(revision) for revision in sources.values()), "invalid tested source")
    require(sources["e2e"] == expected_revision, "tested E2E revision mismatch")
    lanes = report["lanes"]
    require(type(lanes) is list and len(lanes) == len(REQUIRED_CASES), "missing or duplicate lane")
    seen_lanes, seen_jobs, total = set(), set(), 0
    for lane in lanes:
        _keys(lane, {"name", "job_id", "pipeline_id", "sha", "status", "allow_failure",
                     "finished_at", "cases"})
        name = lane["name"]
        require(name in REQUIRED_CASES and name not in seen_lanes, "unknown or duplicate lane")
        seen_lanes.add(name)
        require(_positive_id(lane["job_id"]) and lane["job_id"] not in seen_jobs,
                "invalid or duplicate job")
        seen_jobs.add(lane["job_id"])
        require(type(lane["pipeline_id"]) is int and lane["pipeline_id"] == pipeline["id"]
                and lane["sha"] == expected_revision, "mixed pipeline or revision")
        require(lane["status"] == "success" and lane["allow_failure"] is False,
                "lane must pass and be blocking")
        require(created <= _timestamp(lane["finished_at"]) <= finished,
                "invalid or future job time")
        cases = lane["cases"]
        require(type(cases) is list and 0 < len(cases) <= 128, "empty or oversized lane")
        seen_cases = set()
        for case in cases:
            _keys(case, {"name", "classname", "status"})
            require(type(case["name"]) is str and 0 < len(case["name"]) <= 256,
                    "invalid scenario identity")
            require(case["name"] not in seen_cases, "duplicate scenario")
            seen_cases.add(case["name"])
            require(case["classname"] == "vauchi-e2e-tests::it", "invalid scenario class")
            require(case["status"] == "success", "scenario failed, errored, or skipped")
        require(REQUIRED_CASES[name] <= seen_cases, "missing required scenario in " + name)
        total += len(cases)
    return {"lanes": len(lanes), "cases": total}


def validate_report(report, expected_revision, *, now=None):
    """Return lane/case counts, or reject incomplete and expired evidence."""
    try:
        return _validate(report, expected_revision, now or datetime.now(timezone.utc))
    except (KeyError, TypeError, ValueError, OverflowError, RecursionError) as error:
        raise EvidenceError("certification evidence: malformed report") from error


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "duplicate JSON field")
        value[key] = item
    return value


def decode_json(raw):
    require(len(raw) <= MAX_BYTES, "JSON exceeds size limit")
    try:
        return json.loads(raw, object_pairs_hook=_unique_object)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise EvidenceError("certification evidence: malformed JSON") from error


def read_report(path, expected_revision, *, now=None):
    """Read at most 2 MiB before parsing a local evidence file."""
    try:
        with Path(path).open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
    except OSError as error:
        raise EvidenceError("certification evidence: report missing or unreadable") from error
    return validate_report(decode_json(raw), expected_revision, now=now)


def collect_report(pipeline_id, expected_revision, *, fetch=None, now=None):
    """Collect one pipeline through a replaceable GitLab boundary."""
    from tools.collect_release_evidence import collect

    return collect(pipeline_id, expected_revision, fetch=fetch, now=now)
