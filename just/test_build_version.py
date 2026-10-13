# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Raise an app's version for an internal test build (vauchi/private#665).

Usage: test_build_version.py <android|ios> <file>

Rewrites the file in place with the next patch version and the next build
number, and prints "<version> <build>". The stores refuse a build number
they have seen, so both always go up. A file without exactly one of each
field is refused and left unchanged.
"""

from pathlib import Path
import re
import sys


FIELDS = {
    "android": (
        re.compile(r'(versionName = ")(\d+)\.(\d+)\.(\d+)(")'),
        re.compile(r"(versionCode = )(\d+)()"),
    ),
    "ios": (
        re.compile(r'(MARKETING_VERSION: ")(\d+)\.(\d+)\.(\d+)(")'),
        re.compile(r'(CURRENT_PROJECT_VERSION: ")(\d+)(")'),
    ),
}


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in FIELDS:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    version_pattern, build_pattern = FIELDS[argv[1]]
    path = Path(argv[2])
    text = path.read_text()

    versions = version_pattern.findall(text)
    builds = build_pattern.findall(text)
    if len(versions) != 1 or len(builds) != 1:
        print(
            f"{path}: expected one version and one build number, "
            f"found {len(versions)} and {len(builds)}",
            file=sys.stderr,
        )
        return 1

    _, major, minor, patch, _ = versions[0]
    version = f"{major}.{minor}.{int(patch) + 1}"
    build = int(builds[0][1]) + 1
    text = version_pattern.sub(lambda m: f"{m.group(1)}{version}{m.group(5)}", text)
    text = build_pattern.sub(lambda m: f"{m.group(1)}{build}{m.group(3)}", text)
    path.write_text(text)
    print(version, build)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
