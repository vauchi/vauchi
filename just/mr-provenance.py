# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Collect declared tooling credits before publishing an MR description."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


TOOLS = {
    "Codex (OpenAI)", "Claude (Anthropic)", "Kimi (Moonshot AI)",
    "Junie (JetBrains)", "GitLab CI (GitLab)",
}
LEGACY = (
    (r"Claude(?: [^<>]*)? <noreply@anthropic\.com>", "Claude (Anthropic)"),
    (r"OpenAI Codex <noreply@openai\.com>", "Codex (OpenAI)"),
    (r"Kimi Code <noreply@kimi\.com>", "Kimi (Moonshot AI)"),
    (r"Junie <noreply@jetbrains\.com>", "Junie (JetBrains)"),
)


def credits(text):
    retained, tools = [], []
    fence = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(("```", "~~~")):
            marker = stripped[:3]
            fence = None if fence == marker else marker if fence is None else fence
        declared = []
        if fence is None and line.startswith("Tools used:"):
            try:
                declared = json.loads("[" + line.removeprefix("Tools used:").strip() + "]")
            except json.JSONDecodeError as error:
                raise ValueError("Tools used: expected comma-separated quoted tool/provider names") from error
            if not declared or any(not isinstance(tool, str) or tool not in TOOLS for tool in declared):
                raise ValueError("Tools used: unsupported or empty tool/provider credit")
        elif fence is None and re.match(r"^(?:🤖\s*)?Generated with\b", stripped):
            for name, tool in (("Codex", "Codex (OpenAI)"), ("Claude", "Claude (Anthropic)"),
                               ("Kimi", "Kimi (Moonshot AI)"), ("Junie", "Junie (JetBrains)")):
                if re.search(r"\b" + name + r"\b", stripped, re.I):
                    declared.append(tool)
            if not declared:
                raise ValueError("Tools used: cannot identify the legacy Generated with tool")
        elif fence is None and line.startswith("Co-Authored-By:"):
            value = line.removeprefix("Co-Authored-By:").strip()
            declared = [tool for pattern, tool in LEGACY if re.fullmatch(pattern, value)]
        if declared:
            tools.extend(tool for tool in declared if tool not in tools)
        else:
            retained.append(line)
    if fence is not None:
        retained.append(fence)
    return "\n".join(retained).rstrip(), tools


def description(repo, supplied=None):
    history = subprocess.run(
        ["git", "-C", str(repo), "log", "origin/main..HEAD", "--reverse", "--format=- %s%n%n%b%x00"],
        check=True, capture_output=True, text=True,
    ).stdout
    parts, tools = [], []
    for message in history.split("\0"):
        clean, declared = credits(message)
        parts.append(clean)
        tools.extend(tool for tool in declared if tool not in tools)
    generated = "\n".join(parts)
    body, extra = credits(supplied) if supplied is not None else (generated, [])
    tools.extend(tool for tool in extra if tool not in tools)
    if not tools:
        raise ValueError("Tools used: missing declared tooling credit in commits or MR description")
    if supplied is None:
        body = re.sub(r"\n{3,}", "\n\n", body).strip()
    footer = "Tools used: " + ", ".join(json.dumps(tool) for tool in tools)
    return body + ("\n\n" if body else "") + footer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("description_file", nargs="?")
    parser.add_argument("--stdin", action="store_true")
    args = parser.parse_args()
    supplied = sys.stdin.read() if args.stdin else (
        Path(args.description_file).read_text(encoding="utf-8") if args.description_file else None
    )
    print(description(args.repo, supplied))


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"Tools used: {error}", file=sys.stderr)
        sys.exit(1)
