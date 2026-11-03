# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Record and recheck the committed inputs used by production release gates."""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from tools.release_evidence import EvidenceError, MAX_BYTES, decode_json, validate_report

CHECKLIST = "docs/planning/2026-10-30-first-release-ship-checklist.md"
CERTIFICATION = "target/release-evidence/certification.json"


def require(condition, reason):
    if not condition:
        raise EvidenceError("release provenance: " + reason)


def git(repo, *args):
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args], check=True, capture_output=True,
            text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceError("release provenance: cannot inspect repository") from error
    return result.stdout.strip()


def read_bytes(path, description):
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
    except OSError as error:
        raise EvidenceError(f"release provenance: {description} missing or unreadable") from error
    require(len(raw) <= MAX_BYTES, description + " exceeds size limit")
    return raw


def snapshot(workspace, repo, tag):
    private = workspace / "_private"
    require(Path(git(private, "rev-parse", "--show-toplevel")).resolve() == private.resolve(),
            "private checkout is not a separate repository")
    try:
        git(private, "fetch", "--quiet", "origin", "refs/heads/main:refs/remotes/origin/main")
    except EvidenceError as error:
        raise EvidenceError("release provenance: cannot refresh private origin/main") from error
    require(not git(private, "status", "--porcelain", "--untracked-files=all"),
            "private checkout is dirty")
    revision = git(private, "rev-parse", "HEAD")
    require(revision == git(private, "rev-parse", "origin/main"),
            "private HEAD does not match origin/main")
    git(private, "ls-files", "--error-unmatch", CHECKLIST)
    checklist = read_bytes(private / CHECKLIST, "checklist")
    evidence = read_bytes(workspace / CERTIFICATION, "certification report")
    report = decode_json(evidence)
    e2e_revision = git(workspace / "e2e", "rev-parse", "HEAD")
    validate_report(report, e2e_revision)
    return {
        "schema_version": 1,
        "scope": "release-inputs",
        "release": {"repository": repo, "tag": tag,
                    "revision": git(workspace / repo, "rev-parse", "HEAD")},
        "checklist": {"repository": "vauchi/private", "revision": revision,
                      "path": CHECKLIST, "sha256": hashlib.sha256(checklist).hexdigest()},
        "certification": {"pipeline_id": report["pipeline"]["id"],
                          "e2e_revision": e2e_revision,
                          "sha256": hashlib.sha256(evidence).hexdigest()},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("tag")
    parser.add_argument("output", type=Path)
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    parser.add_argument("--mode", choices=("record", "verify"), default="record")
    args = parser.parse_args()
    try:
        record = snapshot(args.workspace, args.repo, args.tag)
        if args.mode == "verify":
            previous = decode_json(read_bytes(args.output, "prepared provenance"))
            require(previous == record, "release inputs changed; rerun the release gates")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(record, indent=2) + "\n")
    except (EvidenceError, OSError) as error:
        print(str(error) if isinstance(error, EvidenceError)
              else "release provenance: cannot write record", file=sys.stderr)
        return 1
    print("Release inputs " + ("unchanged" if args.mode == "verify" else "recorded"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
