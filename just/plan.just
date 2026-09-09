# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Markdown-plan task tracking recipes

# Validate .plan.md files (single file or directory)
[group('tools')]
[script]
plan-validate target='':
    set -euo pipefail
    TARGET="{{target}}"
    if [[ -z "$TARGET" ]]; then
        TARGET="_private/docs"
    fi
    WORKSPACE_ROOT="$(pwd)"
    ERRORS=0
    CHECKED=0

    validate_file() {
        local file="$1"
        CHECKED=$((CHECKED + 1))
        result=$(python3 << PYEOF
    import sys
    sys.path.insert(0, '$WORKSPACE_ROOT/markdown-plan/python/src')
    from mdplan.parse import parse_tree
    from mdplan.count import count_all_tasks, count_remaining_tasks

    with open('$file') as f:
        text = f.read()

    try:
        tree = parse_tree(text)
    except Exception as e:
        print(f'PARSE ERROR: {e}')
        sys.exit(1)

    total = count_all_tasks(text)
    remaining = count_remaining_tasks(text)
    done = total - remaining

    all_descriptions = [node.value.description for node in tree.nodes]
    for node in tree.nodes:
        for dep in node.value.dependencies:
            matches = [d for d in all_descriptions if dep in d]
            if not matches:
                print(f'UNRESOLVED DEP: "{dep}" in task "{node.value.description}"')
                sys.exit(2)

    print(f'OK: {done}/{total} tasks done ({remaining} remaining)')
    PYEOF
        ) 2>&1 || true
        echo "  $file: $result"
        if [[ "$result" == PARSE* ]] || [[ "$result" == UNRESOLVED* ]]; then
            ERRORS=$((ERRORS + 1))
        fi
    }

    if [[ -f "$TARGET" ]]; then
        echo "Validating: $TARGET"
        validate_file "$TARGET"
    elif [[ -d "$TARGET" ]]; then
        echo "Validating all .plan.md files in: $TARGET"
        while IFS= read -r -d '' file; do
            validate_file "$file"
        done < <(find "$TARGET" -name "*.plan.md" -print0)
    else
        echo "ERROR: $TARGET is not a file or directory"
        exit 1
    fi

    echo ""
    echo "Checked: $CHECKED file(s), Errors: $ERRORS"
    [[ $ERRORS -eq 0 ]] || exit 1

# Show task history as JSON (requires git history)
[group('tools')]
[script]
plan-history file:
    set -euo pipefail
    if ! command -v mdplan &>/dev/null; then
        echo "ERROR: mdplan not installed — run 'just setup'"
        exit 1
    fi
    mdplan history "{{file}}"

# Open burn-up chart in browser (requires git history)
[group('tools')]
[script]
plan-plot file:
    set -euo pipefail
    if ! command -v mdplan &>/dev/null; then
        echo "ERROR: mdplan not installed — run 'just setup'"
        exit 1
    fi
    mdplan plot "{{file}}"

# List all .plan.md files with task counts
[group('tools')]
[script]
plan-list dir='_private/docs':
    set -euo pipefail
    WORKSPACE_ROOT="$(pwd)"
    echo "Plan files in {{dir}}:"
    echo ""
    _PL_COL=60
    _pl_row() {
        local c1="$1" c2="$2"
        local _p=$(( _PL_COL - ${#c1} )); [[ $_p -lt 1 ]] && _p=1
        printf "%s%*s %s\n" "$c1" "$_p" "" "$c2"
    }
    _pl_row "FILE" "STATUS"
    printf "%s\n" "$(printf '%*s' $(( _PL_COL + 20 )) '' | tr ' ' '-')"
    while IFS= read -r -d '' file; do
        relpath="${file#$WORKSPACE_ROOT/}"
        stats=$(python3 << PYEOF
    import sys
    sys.path.insert(0, '$WORKSPACE_ROOT/markdown-plan/python/src')
    from mdplan.count import count_all_tasks, count_remaining_tasks
    with open('$file') as f:
        text = f.read()
    total = count_all_tasks(text)
    remaining = count_remaining_tasks(text)
    done = total - remaining
    pct = int(100 * done / total) if total > 0 else 0
    marker = ""
    if "planning/done/" in '$file' and pct < 75:
        marker = " [ANOMALY: LOW COMPLETION]"
    elif "planning/todo/" in '$file' and total > 0 and pct == 100:
        marker = " [ANOMALY: SHOULD BE IN DONE]"
    print(f'{done}/{total} done ({pct}%){marker}')
    PYEOF
        ) 2>/dev/null || echo "parse error"
        _pl_row "$relpath" "$stats"
    done < <(find "{{dir}}" \( -name "*.plan.md" -o -name "plan.md" \) -print0 | sort -z)

# Show remaining tasks from master plan
[group('tools')]
[script]
task-list:
    set -euo pipefail
    WORKSPACE_ROOT="$(pwd)"
    PLAN="$WORKSPACE_ROOT/_private/docs/planning/master-plan.plan.md"
    if [[ ! -f "$PLAN" ]]; then
        echo "ERROR: $PLAN not found"
        exit 1
    fi
    python3 << 'PYEOF'
    import re
    with open("_private/docs/planning/master-plan.plan.md") as f:
        lines = f.readlines()
    # Parse top-level SPs and their subtasks
    current_sp = None
    tasks = []  # (indent, desc, done, deps)
    for line in lines:
        line = line.rstrip()
        # Top-level: "N. [x] SP-..." or "N. SP-..."
        m = re.match(r'^(\d+)\.\s+(\[x\]\s+)?(.+)$', line)
        if m:
            done = bool(m.group(2))
            desc = m.group(3).strip()
            tasks.append((0, desc, done))
            continue
        # Subtask: "   - [x] ..." or "   - ..."
        m = re.match(r'^(\s+)[-*]\s+(\[x\]\s+)?(.+)$', line)
        if m:
            done = bool(m.group(2))
            desc = m.group(3).strip()
            tasks.append((1, desc, done))
    # Print remaining
    total = len(tasks)
    done_count = sum(1 for _, _, d in tasks if d)
    remaining = [(indent, desc) for indent, desc, d in tasks if not d]
    print(f"Master Plan: {done_count}/{total} tasks done, {len(remaining)} remaining\n")
    current_parent = None
    for indent, desc in remaining:
        if indent == 0:
            current_parent = desc
            # Extract SP name before @(...)
            clean = re.sub(r'\s*@\(.+?\)', '', desc)
            deps = re.findall(r'@\(([^)]+)\)', desc)
            dep_str = f"  (blocked by: {deps[0]})" if deps else ""
            print(f"  {clean}{dep_str}")
        else:
            print(f"    - {desc}")
    PYEOF

# List problem records by status
[group('tools')]
[script]
problem-list phase='':
    set -euo pipefail
    PROBLEMS="_private/docs/problems"
    if [[ ! -d "$PROBLEMS" ]]; then
        echo "ERROR: $PROBLEMS not found"
        exit 1
    fi
    python3 << PYEOF
    import os, re
    from collections import defaultdict

    phase_filter = '{{phase}}'.lower()
    problems_dir = '$PROBLEMS'
    by_status = defaultdict(list)

    for d in sorted(os.listdir(problems_dir)):
        # Support both README.md (current) and problem.md (legacy)
        readme = os.path.join(problems_dir, d, 'README.md')
        if not os.path.isfile(readme):
            readme = os.path.join(problems_dir, d, 'problem.md')
        if not os.path.isfile(readme):
            continue
        with open(readme) as f:
            lines = f.readlines()
        # Only search first 20 lines for status/priority (avoid matching item-level fields)
        header = ''.join(lines[:20])
        st = 'unknown'
        for pat in [
            r'\*\*Status\*\*\s*\|\s*\`?(\w+)',
            r'\*\*Status:\*\*\s*\`?(\w+)',
            r'\*\*Status\*\*\s*:\s*\`?(\w+)',
            r'##\s+Status:\s*(\w+)',
        ]:
            m = re.search(pat, header)
            if m:
                st = m.group(1).lower()
                break
        pr = '?'
        for pat in [
            r'\*\*Priority\*\*\s*\|\s*\`?([^\n\`|]+)',
            r'\*\*Priority:\*\*\s*\`?([^\n\`]+)',
            r'\*\*Priority\*\*\s*:\s*\`?([^\n\`]+)',
        ]:
            m = re.search(pat, header)
            if m:
                pr = m.group(1).strip().split('—')[0].split('(')[0].strip()
                break
        by_status[st].append((pr, d))

    order = ['intake', 'investigating', 'planning', 'implementing', 'testing', 'done', 'archived']
    total = sum(len(v) for v in by_status.values())

    # Records under done/ and deferred/ live one level deeper; their
    # location IS their status (os.listdir above only sees top level).
    def count_subdir(name):
        sub = os.path.join(problems_dir, name)
        if not os.path.isdir(sub):
            return 0
        return sum(1 for d in os.listdir(sub)
                   if os.path.isfile(os.path.join(sub, d, 'README.md'))
                   or os.path.isfile(os.path.join(sub, d, 'problem.md')))
    done_dir_count = count_subdir('done')
    deferred_dir_count = count_subdir('deferred')

    backlog_dir = '_private/docs/backlog'
    backlog_count = sum(1 for d in os.listdir(backlog_dir)
                        if os.path.isfile(os.path.join(backlog_dir, d, 'README.md'))
                        or os.path.isfile(os.path.join(backlog_dir, d, 'problem.md')))

    if not phase_filter:
        # Summary mode
        print(f'Problem records: {total + done_dir_count + deferred_dir_count} total  Backlog: {backlog_count}\n')
        for phase in order:
            items = by_status.get(phase, [])
            if items:
                print(f'  {phase:15s} {len(items):3d}')
        unknown = [k for k in by_status if k not in order]
        for k in unknown:
            print(f'  {k:15s} {len(by_status[k]):3d}')
        print()
        active = sum(len(by_status.get(p, [])) for p in ['intake', 'investigating', 'planning', 'implementing', 'testing'])
        done_total = len(by_status.get('done', [])) + done_dir_count
        print(f'Active: {active}  Deferred: {deferred_dir_count}  Done: {done_total}  Archived: {len(by_status.get("archived", []))}  Backlog: {backlog_count}')
    else:
        items = by_status.get(phase_filter, [])
        if not items:
            print(f'No problems in phase: {phase_filter}')
        else:
            print(f'{phase_filter.upper()} ({len(items)})\n')
            for pr, d in items:
                print(f'  [{pr:6s}] {d}')
    PYEOF

# Move done/closed/resolved problem records to done/
[group('tools')]
[script]
problems-tidy:
    set -euo pipefail
    PROBLEMS="_private/docs/problems"
    DONE_DIR="$PROBLEMS/done"
    if [[ ! -d "$PROBLEMS" ]]; then
        echo "ERROR: $PROBLEMS not found"
        exit 1
    fi
    mkdir -p "$DONE_DIR"
    python3 << 'PYEOF'
    import os, re, shutil

    problems_dir = '_private/docs/problems'
    done_dir = os.path.join(problems_dir, 'done')
    terminal = {'done', 'closed', 'resolved', 'completed'}
    moved = []
    skipped = []

    for d in sorted(os.listdir(problems_dir)):
        if d in ('done', 'README.md'):
            continue
        # Support both README.md (current) and problem.md (legacy)
        readme = os.path.join(problems_dir, d, 'README.md')
        if not os.path.isfile(readme):
            readme = os.path.join(problems_dir, d, 'problem.md')
        if not os.path.isfile(readme):
            continue
        with open(readme) as f:
            header = ''.join(f.readlines()[:20])
        st = None
        for pat in [
            r'\*\*Status\*\*\s*\|\s*\`?(\w+)',
            r'\*\*Status:\*\*\s*\`?(\w+)',
            r'\*\*Status\*\*\s*:\s*\`?(\w+)',
            r'##\s+Status:\s*(\w+)',
        ]:
            m = re.search(pat, header)
            if m:
                st = m.group(1).lower()
                break
        if st in terminal:
            src = os.path.join(problems_dir, d)
            dst = os.path.join(done_dir, d)
            if os.path.exists(dst):
                skipped.append((d, st, 'already in done/'))
            else:
                shutil.move(src, dst)
                moved.append((d, st))

    if moved:
        print(f'Moved {len(moved)} record(s) to done/:\n')
        for name, st in moved:
            print(f'  {st:10s}  {name}')
    else:
        print('No done/closed/resolved records to move.')

    if skipped:
        print(f'\nSkipped {len(skipped)} (already in done/):\n')
        for name, st, reason in skipped:
            print(f'  {st:10s}  {name}  ({reason})')

    # Summary
    active = 0
    for d in sorted(os.listdir(problems_dir)):
        if d in ('done', 'README.md'):
            continue
        if os.path.isdir(os.path.join(problems_dir, d)):
            active += 1
    archived = 0
    for d in sorted(os.listdir(done_dir)):
        if os.path.isdir(os.path.join(done_dir, d)):
            archived += 1
    print(f'\nActive: {active}  Archived: {archived}')
    PYEOF

# Archive a doc: git mv to archived/, update all references, record redirect with status
# Usage: just archive <file> <status> [note]
#   status: done | deprecated | deferred | superseded
#   note:   optional reason (e.g. "superseded by 2026-03-24-overhaul")
# Examples:
#   just archive todo/checklist.md done
#   just archive todo/old-plan.md superseded "replaced by new-plan"
#   just archive todo/feature-x.md deferred "moved to v0.3.0"
[group('tools')]
[script]
archive file status='done' note='':
    set -euo pipefail
    FILE="{{file}}"
    STATUS="{{status}}"
    NOTE="{{note}}"
    PRIVATE="_private/docs"

    # Validate status
    case "$STATUS" in
        done|deprecated|deferred|superseded) ;;
        *) echo "ERROR: status must be one of: done, deprecated, deferred, superseded (got: $STATUS)"; exit 1 ;;
    esac

    # Resolve paths — accept both full and relative-to-planning forms
    if [[ "$FILE" == _private/* ]]; then
        REL="${FILE#_private/}"
    elif [[ "$FILE" == docs/* ]]; then
        REL="$FILE"
    else
        REL="docs/planning/$FILE"
    fi
    FULL="$PRIVATE/${REL#docs/}"

    if [[ ! -f "$FULL" ]]; then
        echo "ERROR: $FULL not found"
        exit 1
    fi

    DIR=$(dirname "$FULL")
    BASE=$(basename "$FULL")

    # Guard: file must be inside a subdirectory (e.g. planning/todo/), not at top level
    PARENT=$(dirname "$DIR")
    if [[ "$PARENT" == "$PRIVATE" ]]; then
        echo "ERROR: $FULL is not inside a subdirectory — cannot determine archive destination"
        exit 1
    fi

    # Route by status: deferred → deferred/, everything else → archived/
    case "$STATUS" in
        deferred) DEST_DIR="${DIR%/*}/deferred" ;;
        *)        DEST_DIR="${DIR%/*}/archived" ;;
    esac

    if [[ ! -d "$DEST_DIR" ]]; then
        echo "ERROR: $DEST_DIR does not exist"
        exit 1
    fi

    if [[ "$DIR" == *"/archived" || "$DIR" == *"/deferred" ]]; then
        echo "ERROR: already in $(basename "$DIR")/"
        exit 1
    fi

    OLD_REL="${FULL#$PRIVATE/}"
    NEW_REL="${DEST_DIR#$PRIVATE/}/$BASE"
    # git paths are relative to _private/ repo root (prefix with docs/)
    GIT_OLD="docs/$OLD_REL"
    GIT_NEW="docs/$NEW_REL"
    DEST_NAME=$(basename "$DEST_DIR")

    echo "Archive ($STATUS): $OLD_REL → $NEW_REL"
    [[ -z "$NOTE" ]] || echo "  Note: $NOTE"

    # 1. git mv (+ companion .plan.md if exists)
    git -C _private mv "$GIT_OLD" "$GIT_NEW"
    COMPANION=""
    if [[ "$BASE" != *.plan.md ]]; then
        PLAN_BASE="${BASE%.md}.plan.md"
        PLAN_OLD="$(dirname "$OLD_REL")/$PLAN_BASE"
        if [[ -f "$PRIVATE/$PLAN_OLD" ]]; then
            PLAN_NEW="${DEST_DIR#$PRIVATE/}/$PLAN_BASE"
            git -C _private mv "docs/$PLAN_OLD" "docs/$PLAN_NEW"
            COMPANION="$PLAN_BASE"
            echo "  + companion: $PLAN_OLD → $PLAN_NEW"
        fi
    fi

    # 2. Record redirect with status
    REDIRECTS="$PRIVATE/planning/.redirects.json"
    if [[ ! -f "$REDIRECTS" ]]; then
        echo '{}' > "$REDIRECTS"
    fi
    ARCHIVE_REDIRECTS="$REDIRECTS" \
    ARCHIVE_OLD_REL="$OLD_REL" \
    ARCHIVE_NEW_REL="$NEW_REL" \
    ARCHIVE_STATUS="$STATUS" \
    ARCHIVE_NOTE="$NOTE" \
    ARCHIVE_COMPANION="$COMPANION" \
    python3 -c '
    import json, os, sys
    from datetime import date
    redirects = os.environ["ARCHIVE_REDIRECTS"]
    old_rel = os.environ["ARCHIVE_OLD_REL"]
    new_rel = os.environ["ARCHIVE_NEW_REL"]
    status = os.environ["ARCHIVE_STATUS"]
    note = os.environ.get("ARCHIVE_NOTE", "")
    companion = os.environ.get("ARCHIVE_COMPANION", "")
    with open(redirects) as f:
        data = json.load(f)
    if old_rel in data:
        print(f"  WARNING: redirect for {old_rel!r} already exists: {data[old_rel]}", file=sys.stderr)
        print(f"  Overwriting previous redirect.", file=sys.stderr)
    entry = {"to": new_rel, "status": status, "date": str(date.today())}
    if note:
        entry["note"] = note
    data[old_rel] = entry
    if companion:
        old_dir = "/".join(old_rel.split("/")[:-1])
        new_dir = "/".join(new_rel.split("/")[:-1])
        data[f"{old_dir}/{companion}"] = dict(entry, to=f"{new_dir}/{companion}")
    with open(redirects, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"  Recorded {len(data)} redirect(s) in .redirects.json")
    '

    # 3. Update all references across _private/docs/
    UPDATED=0
    OLD_PATTERNS=("$OLD_REL" "_private/docs/$OLD_REL")
    NEW_PATTERNS=("$NEW_REL" "_private/docs/$NEW_REL")

    # Also fix relative links (e.g. ../todo/file.md → ../archived/file.md)
    OLD_PARENT=$(basename "$(dirname "$OLD_REL")")
    NEW_PARENT=$(basename "$(dirname "$NEW_REL")")
    if [[ "$OLD_PARENT" != "$NEW_PARENT" ]]; then
        OLD_PATTERNS+=("../$OLD_PARENT/$BASE")
        NEW_PATTERNS+=("../$NEW_PARENT/$BASE")
    fi

    while IFS= read -r -d '' mdfile; do
        # Single python call per file — pass all patterns via env, avoid injection
        REWRITE_FILE="$mdfile" \
        REWRITE_OLD="$(IFS=$'\n'; echo "${OLD_PATTERNS[*]}")" \
        REWRITE_NEW="$(IFS=$'\n'; echo "${NEW_PATTERNS[*]}")" \
        python3 -c '
    import os, sys
    path = os.environ["REWRITE_FILE"]
    olds = os.environ["REWRITE_OLD"].splitlines()
    news = os.environ["REWRITE_NEW"].splitlines()
    with open(path) as f:
        text = f.read()
    updated = text
    for old, new in zip(olds, news):
        updated = updated.replace(old, new)
    if updated != text:
        with open(path, "w") as f:
            f.write(updated)
        print(f"  Updated: {path}")
        sys.exit(0)
    sys.exit(1)
    ' 2>/dev/null && UPDATED=$((UPDATED + 1)) || true
    done < <(find "$PRIVATE" -name "*.md" -print0)

    echo ""
    echo "Done: $STATUS ${BASE}${COMPANION:+ + $COMPANION} → $DEST_NAME/, updated $UPDATED file(s)"
    echo "Run: git -C _private diff --stat  to review"

# Show .plan.md files with no git changes in N days
[group('tools')]
[script]
plan-stale days='30':
    set -euo pipefail
    NOW=$(date +%s)
    STALE=0
    echo "Plan files unchanged for {{days}}+ days:"
    echo ""
    while IFS= read -r -d '' file; do
        LAST=$(git -C _private log -1 --format=%ct -- "${file#_private/}" 2>/dev/null || echo 0)
        if [[ "$LAST" == "0" ]]; then
            LAST=$(git log -1 --format=%ct -- "$file" 2>/dev/null || echo 0)
        fi
        DAYS=$(( (NOW - LAST) / 86400 ))
        if [[ $DAYS -ge {{days}} ]]; then
            echo "  STALE ($DAYS days): $file"
            STALE=$((STALE + 1))
        fi
    done < <(find _private/docs \
        \( -path '*/planning/done' -o -path '*/planning/archived' \
           -o -path '*/planning/deferred' -o -path '*/planning/rejected' \) -prune \
        -o -name "*.plan.md" -print0)
    echo ""
    echo "$STALE stale plan(s) found."

# Live v0.2.0 release readiness — generated from master plan (single source of truth)
[group('tests')]
test-release-gates: test-e2e-recipes
    python3 "{{justfile_directory()}}/tests/test_release_gates.py" "{{justfile_directory()}}/justfile"

[group('tools')]
[script]
release-gates:
    set -euo pipefail
    python3 << 'PYEOF'
    import re, subprocess, sys
    from datetime import date
    from pathlib import Path

    PLAN = "_private/docs/planning/master-plan.plan.md"
    DEPLOY_CONFIG = Path("_private/infra/config/deploy.combined.yml")
    ADR_065 = Path(
        "_private/docs/decisions/"
        "adr-065-first-release-protocol-version-contract.md"
    )
    E2E_DIR = Path("e2e")
    CORE_REPO = Path("core")
    USABILITY_EVIDENCE = Path(
        "_private/docs/testing/usability/"
        "first-release-unassisted-sessions.md"
    )
    ACCESSIBILITY_EVIDENCE = Path(
        "_private/docs/testing/accessibility/"
        "native-frontend-acceptance.md"
    )
    PRIVACY_EVIDENCE = Path(
        "_private/docs/testing/privacy/"
        "service-boundary-no-decryptability.md"
    )
    OHTTP_FAIL_CLOSED_EVIDENCE = Path(
        "_private/docs/testing/privacy/"
        "ohttp-fail-closed.md"
    )
    FRONTEND_JOURNEY_EVIDENCE = Path(
        "_private/docs/testing/frontend/"
        "core-user-journey.md"
    )
    LOCAL_TWO_USER_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "local-two-user-propagation.md"
    )
    OHTTP_RELAY_TWO_USER_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "ohttp-relay-two-user-propagation.md"
    )
    SIX_DEVICE_CONVERGENCE_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "six-device-convergence.md"
    )
    EVERY_LINKED_DEVICE_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "every-linked-device-exchange.md"
    )
    SELECTABLE_EXCHANGE_EVIDENCE = Path(
        "_private/docs/testing/usability/"
        "selectable-exchange-mode-acceptance.md"
    )
    LONG_LIVED_CONTACT_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "long-lived-contact-continuity.md"
    )
    PRODUCTION_DISTRIBUTION_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "production-distribution.md"
    )
    USER_DATA_CONVERGENCE_EVIDENCE = Path(
        "_private/docs/testing/release/"
        "user-data-convergence.md"
    )
    PRODUCTION_CONSUMERS = (
        "android",
        "ios",
        "macos",
        "windows",
        "linux-gtk",
        "linux-qt",
        "cli",
        "tui",
    )
    SUPPORTED_NATIVE_FRONTENDS = (
        "android",
        "ios",
        "macos",
        "windows",
        "linux-gtk",
        "linux-qt",
    )
    FRONTEND_REPOS = (
        Path("android"),
        Path("ios"),
        Path("macos"),
        Path("windows"),
        Path("linux-gtk"),
        Path("linux-qt"),
        Path("cli"),
        Path("tui"),
        Path("web-demo"),
    )
    HUMBLE_CHECKER = Path("scripts/scripts/humble_check.py")
    HUMBLE_RULES = Path("scripts/scripts/humble_check_rules.json")
    HUMBLE_BASELINE = Path("scripts/scripts/humble_check.baseline.json")

    def first_match(pattern, text):
        match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
        return match.group(1).strip().strip('"\'') if match else ""

    def extract_ohttp_block(text):
        match = re.search(
            r"(?ms)^  ohttp-relay:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:|\Z)",
            text,
        )
        return match.group("body") if match else ""

    RELEASE_STAGES = ("alpha", "beta", "release")

    def release_stage(plan_text):
        # Owner decision 2026-09-08: a distinct OHTTP operator is a
        # first-release requirement, not an alpha or beta one. A plan with no
        # declared stage is treated as the first release so the gate fails
        # closed rather than silently deferring.
        stage = first_match(
            r"(?m)^(?:>\s*)?\**Release stage\**:\s*(alpha|beta|release)\b",
            plan_text,
        )
        return stage if stage in RELEASE_STAGES else "release"

    def release_config_report(stage="release"):
        if not DEPLOY_CONFIG.is_file():
            return [f"{DEPLOY_CONFIG} is missing"], []

        deploy_text = DEPLOY_CONFIG.read_text()
        relay_block = first_match(
            r"(?ms)^servers:\n(?P<body>.*?)(?=^proxy:|^# Relay proxy|^env:|\Z)",
            deploy_text,
        )
        ohttp_block = extract_ohttp_block(deploy_text)

        relay_host = first_match(r"(?m)^\s+-\s*([A-Za-z0-9_.-]+)\s*$", relay_block)
        ohttp_host = first_match(
            r"(?m)^\s+host:\s*\"?([A-Za-z0-9_.-]+)\"?\s*$", ohttp_block
        )
        relay_operator = first_match(
            r"(?m)^\s+app\.vauchi\.operator:\s*\"?([^\"\n#]+)\"?\s*$",
            relay_block,
        )
        ohttp_operator = first_match(
            r"(?m)^\s+app\.vauchi\.operator:\s*\"?([^\"\n#]+)\"?\s*$",
            ohttp_block,
        )

        failures = []
        if not relay_host:
            failures.append("application relay host is not declared")
        if not ohttp_host:
            failures.append("OHTTP relay host is not declared")
        if relay_host and ohttp_host and relay_host == ohttp_host:
            failures.append(
                f"application relay and OHTTP relay share host '{relay_host}'"
            )
        if not relay_operator:
            failures.append(
                "application relay operator identity label "
                "app.vauchi.operator is not declared"
            )
        if not ohttp_operator:
            failures.append(
                "OHTTP relay operator identity label app.vauchi.operator "
                "is not declared"
            )
        deferrals = []
        if (
            relay_operator
            and ohttp_operator
            and relay_operator == ohttp_operator
        ):
            if stage == "release":
                failures.append(
                    f"operator identities are not distinct ('{relay_operator}')"
                )
            else:
                deferrals.append(
                    f"one operator ('{relay_operator}') runs both hops"
                )
        return failures, deferrals

    def protocol_v2_failures(plan_text):
        failures = []
        if "ADR-065" not in plan_text:
            failures.append("master plan does not cite ADR-065")
        if not ADR_065.is_file():
            failures.append(f"{ADR_065} is missing")
            return failures

        adr_text = ADR_065.read_text()
        status_match = re.search(
            r"(?m)^\*\*Status\*\*:\s*([^\n]+)$",
            adr_text,
        )
        status = status_match.group(1).strip() if status_match else ""
        if status != "Accepted":
            failures.append(
                f"ADR-065 status is {status or 'missing'}, not Accepted"
            )
        return failures

    def e2e_ignored_test_failures(required_state):
        failures = []
        if not E2E_DIR.is_dir():
            return ["e2e test tree is missing"]

        rust_files = list(E2E_DIR.rglob("*.rs"))
        ignored_count = 0
        for rust_file in rust_files:
            ignored_count += len(
                re.findall(r"(?m)^\s*#\s*\[\s*ignore\s*\]", rust_file.read_text())
            )

        ceiling_match = re.search(r"\bno more than\s+(\d+)\b", required_state)
        if not ceiling_match:
            failures.append(
                "E2E ignored-test required state does not declare a ceiling"
            )
            return failures
        ceiling = int(ceiling_match.group(1))
        if ignored_count > ceiling:
            failures.append(
                f"{ignored_count} ignored Rust E2E test(s), expected "
                f"no more than {ceiling}"
            )
        return failures

    def core_binding_release_failures():
        evidence_paths = []
        if user_data_convergence_done:
            evidence_paths.append(USER_DATA_CONVERGENCE_EVIDENCE)
        if production_distribution_done:
            evidence_paths.append(PRODUCTION_DISTRIBUTION_EVIDENCE)

        failures = []
        evidence_tags = []
        for evidence_path in evidence_paths:
            if not evidence_path.is_file():
                failures.append(
                    f"{evidence_path.name} cannot name the core binding tag"
                )
                continue
            matches = re.findall(
                r"(?m)^\s*core binding tag:\s*"
                r"(v(?:0|[1-9][0-9]*)\."
                r"(?:0|[1-9][0-9]*)\."
                r"(?:0|[1-9][0-9]*))\s*$",
                evidence_path.read_text(errors="ignore"),
            )
            if len(matches) != 1:
                failures.append(
                    f"{evidence_path.name} must declare exactly one "
                    "'core binding tag: vX.Y.Z'"
                )
                continue
            evidence_tags.append(matches[0])

        distinct_tags = sorted(set(evidence_tags))
        if len(distinct_tags) > 1:
            failures.append(
                "binding evidence names conflicting core tags: "
                + ", ".join(distinct_tags)
            )
        if failures or not distinct_tags:
            return failures

        required_tag = distinct_tags[0]
        if not CORE_REPO.is_dir():
            return ["core repository is missing"]
        result = subprocess.run(
            [
                "git",
                "-C",
                str(CORE_REPO),
                "tag",
                "--list",
                required_tag,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return [f"cannot inspect core tags: {result.stderr.strip()}"]
        if result.stdout.strip() != required_tag:
            return [f"required core tag {required_tag} is missing"]
        return []

    def humble_ui_failures():
        failures = []
        todo_count = 0
        for frontend_repo in FRONTEND_REPOS:
            if not frontend_repo.is_dir():
                continue
            for path in frontend_repo.rglob("*"):
                if not path.is_file():
                    continue
                if ".git" in path.parts:
                    continue
                try:
                    todo_count += path.read_text(errors="ignore").count("TODO(HUMBLE)")
                except OSError:
                    continue

        if todo_count > 0:
            failures.append(f"{todo_count} TODO(HUMBLE) site(s) remain")

        required_paths = (HUMBLE_CHECKER, HUMBLE_RULES, HUMBLE_BASELINE)
        missing_paths = [path for path in required_paths if not path.is_file()]
        if missing_paths:
            failures.extend(f"{path} is missing" for path in missing_paths)
            return failures

        result = subprocess.run(
            [
                sys.executable,
                str(HUMBLE_CHECKER),
                "--workspace-root",
                ".",
                "--config",
                str(HUMBLE_RULES),
                "--check",
                str(HUMBLE_BASELINE),
                "--release-zero",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            output = "\n".join(
                part.strip() for part in (result.stdout, result.stderr) if part.strip()
            )
            failures.extend(
                output.splitlines()
                if output
                else ["Humble UI release-zero checker failed without output"]
            )
        return failures

    def usability_evidence_failures():
        if not USABILITY_EVIDENCE.is_file():
            return [f"{USABILITY_EVIDENCE.name} is missing"]

        evidence_text = USABILITY_EVIDENCE.read_text(errors="ignore")
        failures = []
        required_phrases = {
            "representative": "representative users",
            "unassisted": "unassisted central journey",
            "approved study protocol": "approved study protocol",
        }
        lowered = evidence_text.lower()
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} evidence is missing")

        session_count = len(
            re.findall(r"(?mi)^\s*-\s+Session\s+\d+\s*:", evidence_text)
        )
        if session_count < 3:
            failures.append(
                f"{session_count} unassisted session record(s), expected at least 3"
            )
        return failures

    def accessibility_evidence_failures():
        if not ACCESSIBILITY_EVIDENCE.is_file():
            return [f"{ACCESSIBILITY_EVIDENCE.name} is missing"]

        evidence_text = ACCESSIBILITY_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        # A pass is required per supported native frontend — listing the
        # frontend names anywhere in the document is not evidence.
        for frontend in SUPPORTED_NATIVE_FRONTENDS:
            phrase = f"{frontend} accessibility acceptance: passed"
            if phrase not in lowered:
                failures.append(f"{phrase} evidence is missing")
        if "physical screen-reader" not in lowered:
            failures.append("physical screen-reader walkthrough evidence is missing")
        if "blocking accessibility defects: zero" not in lowered:
            failures.append("zero blocking accessibility defects evidence is missing")
        return failures

    def service_boundary_privacy_failures():
        if not PRIVACY_EVIDENCE.is_file():
            return [f"{PRIVACY_EVIDENCE.name} is missing"]

        evidence_text = PRIVACY_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "relay storage": "relay storage inspection",
            "ohttp relay storage": "OHTTP relay storage inspection",
            "logs": "log inspection",
            "metrics": "metrics inspection",
            "traces": "trace inspection",
            "configuration": "configuration inspection",
            "service-held secrets": "service-held secret inspection",
            "plaintext/key access: none": "plaintext/key access negative evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def ohttp_fail_closed_failures():
        if not OHTTP_FAIL_CLOSED_EVIDENCE.is_file():
            return [f"{OHTTP_FAIL_CLOSED_EVIDENCE.name} is missing"]

        evidence_text = OHTTP_FAIL_CLOSED_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        for consumer in PRODUCTION_CONSUMERS:
            if consumer not in lowered:
                failures.append(f"{consumer} fail-closed evidence is missing")

        required_phrases = {
            "plaintext path: fails closed": "plaintext path fail-closed evidence",
            "tls-only path: fails closed": "TLS-only path fail-closed evidence",
            "direct path: fails closed": "direct path fail-closed evidence",
            "bootstrap path: fails closed": "bootstrap path fail-closed evidence",
            "reachability-probe path: fails closed": (
                "reachability-probe path fail-closed evidence"
            ),
            "no bypass": "no-bypass evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def frontend_journey_failures():
        if not FRONTEND_JOURNEY_EVIDENCE.is_file():
            return [f"{FRONTEND_JOURNEY_EVIDENCE.name} is missing"]

        evidence_text = FRONTEND_JOURNEY_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        # Per-consumer matrix: a global "create card: passed" line cannot
        # stand in for a consumer that never ran the journey.
        journeys = (
            "create card",
            "edit card",
            "exchange contact",
            "receive update",
            "block or ignore",
        )
        for consumer in PRODUCTION_CONSUMERS:
            for journey in journeys:
                phrase = f"{consumer} {journey}: passed"
                if phrase not in lowered:
                    failures.append(f"{phrase} evidence is missing")
        return failures

    def local_two_user_failures():
        if not LOCAL_TWO_USER_EVIDENCE.is_file():
            return [f"{LOCAL_TWO_USER_EVIDENCE.name} is missing"]

        evidence_text = LOCAL_TWO_USER_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "local two-user: passed": "local two-user evidence",
            "representative two-device run: passed": (
                "representative two-device run evidence"
            ),
            "mutual exchange: passed": "mutual exchange evidence",
            "update propagation: passed": "update propagation evidence",
            "exact-value assertions: passed": "exact-value assertion evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def ohttp_relay_two_user_failures():
        if not OHTTP_RELAY_TWO_USER_EVIDENCE.is_file():
            return [f"{OHTTP_RELAY_TWO_USER_EVIDENCE.name} is missing"]

        evidence_text = OHTTP_RELAY_TWO_USER_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "split-ohttp two-user: passed": "split-OHTTP two-user evidence",
            "both privacy hops: passed": "both privacy hops evidence",
            "ohttp relay: passed": "OHTTP relay evidence",
            "application relay: passed": "application relay evidence",
            "exchange propagation: passed": "exchange propagation evidence",
            "update propagation: passed": "update propagation evidence",
            "exact-value assertions: passed": "exact-value assertion evidence",
            "blocking e2e pipeline: passed": "blocking E2E pipeline evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def six_device_convergence_failures():
        if not SIX_DEVICE_CONVERGENCE_EVIDENCE.is_file():
            return [f"{SIX_DEVICE_CONVERGENCE_EVIDENCE.name} is missing"]

        evidence_text = SIX_DEVICE_CONVERGENCE_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "six-device topology: passed": "six-device topology evidence",
            "alice devices: a1, a2, a3": "Alice A1/A2/A3 evidence",
            "bob devices: b1, b2, b3": "Bob B1/B2/B3 evidence",
            "three linked devices per user: passed": (
                "three-linked-devices-per-user evidence"
            ),
            "socket-backed topology: passed": "socket-backed topology evidence",
            "real link ceremony: passed": "real link ceremony evidence",
            "convergence at every target: passed": (
                "convergence-at-every-target evidence"
            ),
            "reorder and duplicate handling: passed": (
                "reorder/duplicate handling evidence"
            ),
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        # Fault and device-lifecycle contract from the multi-device ratchet
        # topology record's six-device matrix: convergence must also hold
        # under concurrent writes, offline catch-up, relay restart, and the
        # device lifecycle (revocation, replacement, clock skew).
        for phrase in (
            "simultaneous edits: passed",
            "offline catch-up: passed",
            "relay restart during delivery: passed",
            "device revocation: passed",
            "device replacement: passed",
            "clock skew: passed",
        ):
            if phrase not in lowered:
                failures.append(f"{phrase} evidence is missing")
        return failures

    def every_linked_device_failures():
        if not EVERY_LINKED_DEVICE_EVIDENCE.is_file():
            return [f"{EVERY_LINKED_DEVICE_EVIDENCE.name} is missing"]

        evidence_text = EVERY_LINKED_DEVICE_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "active linked devices: a1, a2, a3, b1, b2, b3": (
                "active linked device inventory evidence"
            ),
            "exchange from every active device: passed": (
                "exchange-from-every-active-device evidence"
            ),
            "update from every active device: passed": (
                "update-from-every-active-device evidence"
            ),
            "secondary device initiation: passed": "secondary device initiation evidence",
            "third device initiation: passed": "third device initiation evidence",
            "independent per-device ratchet sessions: passed": (
                "independent per-device ratchet evidence"
            ),
            "nine-pair ratchet matrix: passed": "nine-pair ratchet matrix evidence",
            "sender-token wire inspection: passed": (
                "sender-token wire inspection evidence"
            ),
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        # The ratchet-topology record lists Bob-originated updates as
        # remaining six-device work; per-device exchange evidence must
        # prove both directions, not only Alice-originated fan-out.
        phrase = "bob-originated updates: passed"
        if phrase not in lowered:
            failures.append(f"{phrase} evidence is missing")
        return failures

    def selectable_exchange_failures():
        if not SELECTABLE_EXCHANGE_EVIDENCE.is_file():
            return [f"{SELECTABLE_EXCHANGE_EVIDENCE.name} is missing"]

        evidence_text = SELECTABLE_EXCHANGE_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "selectable exchange modes: passed": (
                "selectable exchange modes acceptance evidence"
            ),
            "functionality: passed": "functionality acceptance evidence",
            "latency: accepted": "latency acceptance evidence",
            "enjoyment: accepted": "enjoyment acceptance evidence",
            "accessibility: passed": "accessibility acceptance evidence",
            "cancellation: passed": "cancellation acceptance evidence",
            "retry: passed": "retry acceptance evidence",
            "recovery: passed": "recovery acceptance evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def long_lived_contact_failures():
        if not LONG_LIVED_CONTACT_EVIDENCE.is_file():
            return [f"{LONG_LIVED_CONTACT_EVIDENCE.name} is missing"]

        evidence_text = LONG_LIVED_CONTACT_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "long-lived contact continuity: passed": (
                "long-lived contact continuity evidence"
            ),
            "composite longitudinal scenario: passed": (
                "composite longitudinal scenario evidence"
            ),
            "clock-driven scenario: passed": "clock-driven scenario evidence",
            "exchange remains useful: passed": (
                "exchange remains useful evidence"
            ),
            "permitted detail changes: passed": (
                "permitted detail change evidence"
            ),
            "offline catch-up: passed": "offline catch-up evidence",
            "device add/revoke/replace: passed": (
                "device add/revoke/replace evidence"
            ),
            "archive/unarchive: passed": "archive/unarchive evidence",
            "block behavior: passed": "block behavior evidence",
            "ignore semantics: accepted": "accepted ignore semantics evidence",
            "ignored relationship behavior: passed": (
                "ignored relationship behavior evidence"
            ),
            "no re-exchange required: passed": "no re-exchange evidence",
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    def production_distribution_failures():
        if not PRODUCTION_DISTRIBUTION_EVIDENCE.is_file():
            return [f"{PRODUCTION_DISTRIBUTION_EVIDENCE.name} is missing"]

        evidence_text = PRODUCTION_DISTRIBUTION_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        # Per-consumer matrix: every consumer proves signing, packaging,
        # installation, and its distribution-channel acceptance. Store
        # submission applies to the P0 store platforms (App Store, Google
        # Play — problem 2026-06-11-store-submission-blockers); notarization
        # applies to the Apple platforms.
        steps = (
            "signing",
            "packaging",
            "installation",
            "distribution-channel acceptance",
        )
        for consumer in PRODUCTION_CONSUMERS:
            for step in steps:
                phrase = f"{consumer} {step}: passed"
                if phrase not in lowered:
                    failures.append(f"{phrase} evidence is missing")
        for consumer in ("android", "ios"):
            phrase = f"{consumer} store submission: passed"
            if phrase not in lowered:
                failures.append(f"{phrase} evidence is missing")
        for consumer in ("ios", "macos"):
            phrase = f"{consumer} notarization: passed"
            if phrase not in lowered:
                failures.append(f"{phrase} evidence is missing")
        return failures

    def user_data_convergence_failures():
        if not USER_DATA_CONVERGENCE_EVIDENCE.is_file():
            return [f"{USER_DATA_CONVERGENCE_EVIDENCE.name} is missing"]

        evidence_text = USER_DATA_CONVERGENCE_EVIDENCE.read_text(errors="ignore")
        lowered = evidence_text.lower()
        failures = []
        required_phrases = {
            "user data convergence: passed": "user data convergence evidence",
            "complete owner-private state convergence: passed": (
                "complete owner-private state convergence evidence"
            ),
            "myinfo update/removal: passed": "MyInfo update/removal evidence",
            "presentation cards: passed": "presentation-card evidence",
            "group identity/membership/visibility/overrides: passed": (
                "group identity/membership/visibility/override evidence"
            ),
            "tag change/deletion: passed": "tag change/deletion evidence",
            "contacts/private notes: passed": "contacts/private notes evidence",
            "all six devices synchronized: passed": (
                "all-six-devices synchronized evidence"
            ),
            "canonical owner-private state: passed": (
                "canonical owner-private state evidence"
            ),
            "permitted presentation state only: passed": (
                "permitted presentation state evidence"
            ),
            "no private state leaked to bob or relay: passed": (
                "private-state non-leakage evidence"
            ),
            "adr-020 deterministic convergence: passed": (
                "ADR-020 deterministic convergence evidence"
            ),
        }
        for phrase, label in required_phrases.items():
            if phrase not in lowered:
                failures.append(f"{label} is missing")
        return failures

    try:
        with open(PLAN) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"ERROR: {PLAN} not found", file=sys.stderr)
        sys.exit(1)

    gate_matches = list(re.finditer(
        r'^\s+-\s+(?:(\[x\])\s+)?(RG-(\d+))\s+—\s+(.+?)\s*$',
        text,
        re.MULTILINE | re.IGNORECASE,
    ))
    if not gate_matches:
        print("ERROR: no RG release gates found in master plan", file=sys.stderr)
        sys.exit(2)

    expected_ids = {f"RG-{number}" for number in range(1, 16)}
    found_ids = {match.group(2).upper() for match in gate_matches}
    if found_ids != expected_ids or len(gate_matches) != len(expected_ids):
        missing = sorted(expected_ids - found_ids, key=lambda gid: int(gid[3:]))
        unexpected = sorted(found_ids - expected_ids)
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if unexpected:
            details.append(f"unexpected: {', '.join(unexpected)}")
        if len(gate_matches) != len(found_ids):
            details.append("duplicate RG task IDs")
        print(
            "ERROR: expected RG-1 through RG-15 exactly once"
            + (f" ({'; '.join(details)})" if details else ""),
            file=sys.stderr,
        )
        sys.exit(2)

    ship_criteria = []
    expected_ship_criteria = {
        "Protocol v2",
        "E2E ignored tests",
    }
    table_match = re.search(
        r"(?ms)^\*\*Ship criteria\*\*\n\n(?P<table>(?:^\|.*\|\n)+)",
        text,
    )
    if not table_match:
        print("ERROR: Ship criteria table not found in master plan", file=sys.stderr)
        sys.exit(2)

    for row in table_match.group("table").splitlines():
        cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
        if len(cells) != 3:
            continue
        criterion, required_state, classification = cells
        if (
            criterion == "Criterion"
            or set(criterion) == {"-"}
            or classification.lower() != "hard"
        ):
            continue
        # Rows that name RG coverage are enforced by the RG checkbox list
        # above. Keep this section for hard criteria that otherwise had no
        # executable representation.
        if re.search(r"\bRG-\d+\b", criterion):
            continue
        done = False
        done_match = re.match(r"^\[x\]\s+(.+)$", criterion, re.IGNORECASE)
        if done_match:
            done = True
            criterion = done_match.group(1).strip()
        ship_criteria.append(
            (
                criterion,
                required_state,
                done,
            )
        )

    found_ship_criteria = {criterion for criterion, _state, _done in ship_criteria}
    if found_ship_criteria != expected_ship_criteria:
        missing = sorted(expected_ship_criteria - found_ship_criteria)
        unexpected = sorted(found_ship_criteria - expected_ship_criteria)
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if unexpected:
            details.append(f"unexpected: {', '.join(unexpected)}")
        print(
            "ERROR: expected hard ship criteria exactly once"
            + (f" ({'; '.join(details)})" if details else ""),
            file=sys.stderr,
        )
        sys.exit(2)

    hard = sorted(
        [
            (
                match.group(2).upper(),
                match.group(4).strip(),
                match.group(1) is not None,
                "",
            )
            for match in gate_matches
        ],
        key=lambda gate: int(gate[0][3:]),
    )

    # --- Output ---
    done_hard = [h for h in hard if h[2]]
    open_hard = [h for h in hard if not h[2]]
    done_ship = [criterion for criterion in ship_criteria if criterion[2]]
    open_ship = [criterion for criterion in ship_criteria if not criterion[2]]
    frontend_journey_done = any(
        gid == "RG-1" and done
        for gid, _name, done, _detail in hard
    )
    local_two_user_done = any(
        gid == "RG-2" and done
        for gid, _name, done, _detail in hard
    )
    ohttp_relay_two_user_done = any(
        gid == "RG-3" and done
        for gid, _name, done, _detail in hard
    )
    six_device_convergence_done = any(
        gid == "RG-4" and done
        for gid, _name, done, _detail in hard
    )
    every_linked_device_done = any(
        gid == "RG-5" and done
        for gid, _name, done, _detail in hard
    )
    rg7_done = any(gid == "RG-7" and done for gid, _name, done, _detail in hard)
    privacy_done = any(
        gid == "RG-6" and done
        for gid, _name, done, _detail in hard
    )
    ohttp_fail_closed_done = any(
        gid == "RG-8" and done
        for gid, _name, done, _detail in hard
    )
    selectable_exchange_done = any(
        gid == "RG-9" and done
        for gid, _name, done, _detail in hard
    )
    binding_release_done = any(
        gid in {"RG-10", "RG-14"} and done
        for gid, _name, done, _detail in hard
    )
    user_data_convergence_done = any(
        gid == "RG-10" and done
        for gid, _name, done, _detail in hard
    )
    production_distribution_done = any(
        gid == "RG-14" and done
        for gid, _name, done, _detail in hard
    )
    humble_ui_done = any(
        gid == "RG-11" and done
        for gid, _name, done, _detail in hard
    )
    accessibility_done = any(
        gid == "RG-12" and done
        for gid, _name, done, _detail in hard
    )
    usability_done = any(
        gid == "RG-13" and done
        for gid, _name, done, _detail in hard
    )
    long_lived_contact_done = any(
        gid == "RG-15" and done
        for gid, _name, done, _detail in hard
    )
    frontend_journey_failures = (
        frontend_journey_failures() if frontend_journey_done else []
    )
    local_two_user_failures = (
        local_two_user_failures() if local_two_user_done else []
    )
    ohttp_relay_two_user_failures = (
        ohttp_relay_two_user_failures() if ohttp_relay_two_user_done else []
    )
    six_device_convergence_failures = (
        six_device_convergence_failures() if six_device_convergence_done else []
    )
    every_linked_device_failures = (
        every_linked_device_failures() if every_linked_device_done else []
    )
    stage = release_stage(text)
    config_failures, config_deferrals = (
        release_config_report(stage) if rg7_done else ([], [])
    )
    service_boundary_privacy_failures = (
        service_boundary_privacy_failures() if privacy_done else []
    )
    ohttp_fail_closed_failures = (
        ohttp_fail_closed_failures() if ohttp_fail_closed_done else []
    )
    selectable_exchange_failures = (
        selectable_exchange_failures() if selectable_exchange_done else []
    )
    core_binding_release_failures = (
        core_binding_release_failures() if binding_release_done else []
    )
    user_data_convergence_failures = (
        user_data_convergence_failures() if user_data_convergence_done else []
    )
    production_distribution_failures = (
        production_distribution_failures() if production_distribution_done else []
    )
    humble_ui_failures = humble_ui_failures() if humble_ui_done else []
    accessibility_evidence_failures = (
        accessibility_evidence_failures() if accessibility_done else []
    )
    usability_evidence_failures = (
        usability_evidence_failures() if usability_done else []
    )
    long_lived_contact_failures = (
        long_lived_contact_failures() if long_lived_contact_done else []
    )
    protocol_v2_done = any(
        criterion == "Protocol v2" and done
        for criterion, _required_state, done in ship_criteria
    )
    protocol_v2_evidence_failures = (
        protocol_v2_failures(text) if protocol_v2_done else []
    )
    e2e_ignored_done = any(
        criterion == "E2E ignored tests" and done
        for criterion, _required_state, done in ship_criteria
    )
    e2e_ignored_required_state = next(
        (
            required_state
            for criterion, required_state, _done in ship_criteria
            if criterion == "E2E ignored tests"
        ),
        "",
    )
    e2e_ignored_test_failures = (
        e2e_ignored_test_failures(e2e_ignored_required_state)
        if e2e_ignored_done else []
    )
    status_failures = []
    if done_hard and re.search(
        r"\bAll\s+15\s+release\s+gates\s+are\s+open\b",
        text,
        re.IGNORECASE,
    ):
        status_failures.append(
            "master plan says all 15 gates are open but "
            f"{len(done_hard)} RG gate(s) are checked complete"
        )

    print(f"Production Release Readiness — {date.today()}")
    print(f"Source: master-plan.plan.md (single source of truth)\n")

    print(f"HARD GATES ({len(done_hard)}/{len(hard)} done):")
    for gid, name, done, detail in hard:
        icon = "DONE" if done else "TODO"
        suffix = f"  ({detail})" if detail and not done else ""
        print(f"  [{icon}]  #{gid:<6s} {name}{suffix}")

    if ship_criteria:
        print(f"\nHARD SHIP CRITERIA ({len(done_ship)}/{len(ship_criteria)} done):")
        for criterion, required_state, done in ship_criteria:
            icon = "DONE" if done else "TODO"
            print(f"  [{icon}]  {criterion} — {required_state}")

    if open_hard:
        print(f"\n  >>> {len(open_hard)} HARD GATE(s) block release <<<")
    if open_ship:
        print(f"\n  >>> {len(open_ship)} HARD SHIP CRITERIA block release <<<")
    if status_failures:
        print("\n  >>> master-plan status contradiction <<<")
        for failure in status_failures:
            print(f"      - {failure}")
    if config_failures:
        print("\n  >>> RG-7 release config failure <<<")
        for failure in config_failures:
            print(f"      - {failure}")
        print(
            "      ADR-037 requires distinct OHTTP gateway and application "
            "relay operators."
        )
    if config_deferrals:
        print(
            f"\n  >>> RG-7 distinct-operator requirement deferred "
            f"({stage} stage) <<<"
        )
        for deferral in config_deferrals:
            print(f"      - {deferral}")
        print(
            "      Owner decision 2026-09-08: one operator runs both hops "
            "until the first release (ADR-037 addendum 2026-09-08)."
        )
    if service_boundary_privacy_failures:
        print("\n  >>> RG-6 service-boundary privacy evidence failure <<<")
        for failure in service_boundary_privacy_failures:
            print(f"      - {failure}")
    if frontend_journey_failures:
        print("\n  >>> RG-1 frontend journey evidence failure <<<")
        for failure in frontend_journey_failures:
            print(f"      - {failure}")
    if local_two_user_failures:
        print("\n  >>> RG-2 local two-user evidence failure <<<")
        for failure in local_two_user_failures:
            print(f"      - {failure}")
    if ohttp_relay_two_user_failures:
        print("\n  >>> RG-3 OHTTP relay evidence failure <<<")
        for failure in ohttp_relay_two_user_failures:
            print(f"      - {failure}")
    if six_device_convergence_failures:
        print("\n  >>> RG-4 six-device convergence evidence failure <<<")
        for failure in six_device_convergence_failures:
            print(f"      - {failure}")
    if every_linked_device_failures:
        print("\n  >>> RG-5 every-linked-device evidence failure <<<")
        for failure in every_linked_device_failures:
            print(f"      - {failure}")
    if ohttp_fail_closed_failures:
        print("\n  >>> RG-8 OHTTP fail-closed evidence failure <<<")
        for failure in ohttp_fail_closed_failures:
            print(f"      - {failure}")
    if selectable_exchange_failures:
        print("\n  >>> RG-9 selectable exchange evidence failure <<<")
        for failure in selectable_exchange_failures:
            print(f"      - {failure}")
    if protocol_v2_evidence_failures:
        print("\n  >>> Protocol v2 evidence failure <<<")
        for failure in protocol_v2_evidence_failures:
            print(f"      - {failure}")
    if e2e_ignored_test_failures:
        print("\n  >>> E2E ignored-test evidence failure <<<")
        for failure in e2e_ignored_test_failures:
            print(f"      - {failure}")
    if core_binding_release_failures:
        print("\n  >>> Core binding release evidence failure <<<")
        for failure in core_binding_release_failures:
            print(f"      - {failure}")
    if user_data_convergence_failures:
        print("\n  >>> RG-10 user-data convergence evidence failure <<<")
        for failure in user_data_convergence_failures:
            print(f"      - {failure}")
    if production_distribution_failures:
        print("\n  >>> RG-14 production distribution evidence failure <<<")
        for failure in production_distribution_failures:
            print(f"      - {failure}")
    if humble_ui_failures:
        print("\n  >>> RG-11 Humble UI evidence failure <<<")
        for failure in humble_ui_failures:
            print(f"      - {failure}")
    if accessibility_evidence_failures:
        print("\n  >>> RG-12 accessibility evidence failure <<<")
        for failure in accessibility_evidence_failures:
            print(f"      - {failure}")
    if usability_evidence_failures:
        print("\n  >>> RG-13 usability evidence failure <<<")
        for failure in usability_evidence_failures:
            print(f"      - {failure}")
    if long_lived_contact_failures:
        print("\n  >>> RG-15 long-lived contact evidence failure <<<")
        for failure in long_lived_contact_failures:
            print(f"      - {failure}")
    if (
        not open_hard
        and (
            config_failures
            or frontend_journey_failures
            or local_two_user_failures
            or ohttp_relay_two_user_failures
            or six_device_convergence_failures
            or every_linked_device_failures
            or service_boundary_privacy_failures
            or ohttp_fail_closed_failures
            or selectable_exchange_failures
            or status_failures
            or protocol_v2_evidence_failures
            or e2e_ignored_test_failures
            or core_binding_release_failures
            or user_data_convergence_failures
            or production_distribution_failures
            or humble_ui_failures
            or accessibility_evidence_failures
            or usability_evidence_failures
            or long_lived_contact_failures
        )
    ):
        print("\n  Release remains blocked by release-configuration evidence.")
    elif open_hard:
        pass
    else:
        print(f"\n  All hard gates passed!")

    sys.exit(
        0
        if not open_hard
        and not open_ship
        and not config_failures
        and not frontend_journey_failures
        and not local_two_user_failures
        and not ohttp_relay_two_user_failures
        and not six_device_convergence_failures
        and not every_linked_device_failures
        and not service_boundary_privacy_failures
        and not ohttp_fail_closed_failures
        and not selectable_exchange_failures
        and not status_failures
        and not protocol_v2_evidence_failures
        and not e2e_ignored_test_failures
        and not core_binding_release_failures
        and not user_data_convergence_failures
        and not production_distribution_failures
        and not humble_ui_failures
        and not accessibility_evidence_failures
        and not usability_evidence_failures
        and not long_lived_contact_failures
        else 1
    )
    PYEOF

# Detect satellite docs that duplicate master plan status (run in session-init)
# Only flags docs with **DONE** annotations or gate keywords — not implementation
# plans that have [x] checkboxes for their own internal tasks.
[group('tools')]
[script]
plan-drift:
    set -euo pipefail
    python3 << 'PYEOF'
    import os, re, sys

    PLAN = "_private/docs/planning/master-plan.plan.md"
    TODO_DIR = "_private/docs/planning/todo"

    if not os.path.isfile(PLAN):
        print(f"ERROR: {PLAN} not found", file=sys.stderr)
        sys.exit(1)

    # Patterns that indicate master plan STATUS duplication (not just task tracking)
    DRIFT_PATTERNS = [
        (r'\*\*DONE\*\*', "**DONE** annotations"),
        (r'HARD GATE|SOFT GATE', "gate classification keywords"),
        (r'T[0-3]-\d+.*(?:DONE|done|complete)', "tier item status"),
    ]

    def check_drift(path):
        """Returns list of (pattern_desc, count) for patterns that indicate drift.
        Only flags if doc has master-plan-specific patterns (gate keywords or tier status),
        not just **DONE** annotations which are normal in implementation plans."""
        with open(path) as f:
            text = f.read()
        # Exempt files with explicit reference-only header
        header = text[:500].lower()
        if 'reference only' in header or 'canonical in master' in header:
            return []
        findings = []
        has_gate_or_tier = False
        for pat, desc in DRIFT_PATTERNS:
            count = len(re.findall(pat, text))
            if count > 0:
                findings.append((desc, count))
                if 'gate' in desc or 'tier' in desc:
                    has_gate_or_tier = True
        # Only flag if the doc duplicates master-plan-level concepts (gates or tiers),
        # not if it just uses **DONE** for its own internal task tracking
        return findings if has_gate_or_tier else []

    warnings = []
    for fname in sorted(os.listdir(TODO_DIR)):
        fpath = os.path.join(TODO_DIR, fname)
        if not fpath.endswith('.md') or not os.path.isfile(fpath):
            continue
        if fname == 'README.md' or fname.endswith('.plan.md'):
            continue
        findings = check_drift(fpath)
        if findings:
            total = sum(c for _, c in findings)
            if total >= 3:  # only flag if 3+ drift indicators
                warnings.append((fname, findings, total))

    if not warnings:
        print("plan-drift: OK — no satellite docs duplicating master plan status")
        sys.exit(0)

    print(f"plan-drift: {len(warnings)} satellite doc(s) may duplicate master plan status\n")
    for fname, findings, total in warnings:
        print(f"  {TODO_DIR}/{fname} ({total} indicators):")
        for desc, count in findings:
            print(f"    {count:3d}x {desc}")
    print(f"\n  Fix: archive to planning/archived/, or add '> Status canonical in master-plan.plan.md' header.")
    sys.exit(1)
    PYEOF

# Risk dashboard — surfaces blockers, stalled plans, recurring failures
[group('tools')]
risk *FLAGS:
    scripts/scripts/risk-dashboard.sh {{FLAGS}}

# Dry-run plan sync — show what CI would update
[group('tools')]
[script]
plan-sync *FLAGS:
    set -euo pipefail
    SINCE="${PLAN_SYNC_SINCE:-$(git log --all --format=%H --grep='chore: sync plans' -1 2>/dev/null || git rev-list --max-parents=0 HEAD)}"
    cd drift-detector && node dist/index.js sync --since "$SINCE" {{FLAGS}}

# Apply plan sync changes to working tree (no commit)
plan-sync-apply:
    just plan-sync --apply
