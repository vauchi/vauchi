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
[group('tools')]
[script]
release-gates:
    set -euo pipefail
    python3 << 'PYEOF'
    import re, sys
    from datetime import date

    PLAN = "_private/docs/planning/master-plan.plan.md"

    try:
        with open(PLAN) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"ERROR: {PLAN} not found", file=sys.stderr)
        sys.exit(1)

    hard = []  # (id, name, done, detail)
    soft = []  # (id, name, done, detail)
    seen_ids = set()

    def add_hard(gid, name, done, detail=""):
        if gid not in seen_ids:
            seen_ids.add(gid)
            hard.append((gid, name, done, detail))

    # P0 Audit Hard Gates (items 44-47)
    # Done: "44. ~~**HARD GATE**: Name~~ **DONE**"
    for m in re.finditer(
        r'^(\d+)\.\s+~~\*\*HARD GATE\*\*:\s*(.+?)~~\s*\*\*DONE\*\*',
        text, re.MULTILINE
    ):
        add_hard(m.group(1), m.group(2).strip(), True)

    # Open: "45. **HARD GATE**: Name — status"
    for m in re.finditer(
        r'^(\d+)\.\s+\*\*HARD GATE\*\*:\s*(.+?)$',
        text, re.MULTILINE
    ):
        parts = m.group(2).split("\u2014", 1)  # em-dash
        name = parts[0].strip()
        detail = parts[1].strip() if len(parts) > 1 else ""
        add_hard(m.group(1), name, False, detail)

    # Items with ~~text~~ **DONE** but without HARD GATE prefix (e.g. item 47, 48-54)
    # "47. ~~core/SECURITY.md Wrong Crypto~~ **DONE**"
    for m in re.finditer(
        r'^(\d+)\.\s+~~(.+?)~~\s*\*\*DONE\*\*',
        text, re.MULTILINE
    ):
        add_hard(m.group(1), m.group(2).strip().rstrip(":"), True)

    # SP-33 Sealed Mailbox Tokens (skip if already captured under a numbered item)
    if not any("Sealed Mailbox" in h[1] for h in hard):
        if re.search(r'~~SP-33.*~~.*\*?\*?DONE', text):
            add_hard("SP-33", "Sealed Mailbox Tokens", True)

    # Remaining HARD GATES table — only data rows (skip header/separator)
    in_table = False
    for line in text.splitlines():
        if line.startswith("## Remaining HARD GATES"):
            in_table = True
            continue
        if in_table and line.startswith("## "):
            break
        if not in_table:
            continue
        # Skip header row and separator
        if re.match(r'^\|\s*#\s*\|', line) or re.match(r'^\|[-\s|]+\|$', line):
            continue
        # Split by | and clean up
        cells = [c.strip() for c in line.split('|')]
        cells = [c for c in cells if c]  # remove empty from leading/trailing |
        if len(cells) >= 3:
            gid = re.sub(r'\*', '', cells[0]).strip()
            name = re.sub(r'\*', '', cells[1]).strip()
            status = re.sub(r'[\*`]', '', cells[2]).strip()
            done = 'done' in status.lower() or 'merged' in status.lower()
            add_hard(gid, name, done, "" if done else status)

    # Inline hard gates in other sections
    if "Relay uptime monitoring" not in ' '.join(h[1] for h in hard):
        if re.search(r'Relay uptime monitoring.*HARD GATE', text):
            add_hard("SP-25", "Relay uptime monitoring", False, "config done, needs DNS + deploy")

    # Soft gates
    if re.search(r'SP-11.*soft gate', text, re.IGNORECASE):
        soft.append(("SP-11", "Accessibility (screen reader)", False, "~50%"))
    if re.search(r'SP-12c.*SOFT GATE', text):
        soft.append(("SP-12c", "Performance and Robustness", False, "intake, 0%"))

    # --- Output ---
    done_hard = [h for h in hard if h[2]]
    open_hard = [h for h in hard if not h[2]]

    print(f"v0.2.0 Release Readiness — {date.today()}")
    print(f"Source: master-plan.plan.md (single source of truth)\n")

    print(f"HARD GATES ({len(done_hard)}/{len(hard)} done):")
    for gid, name, done, detail in hard:
        icon = "DONE" if done else "TODO"
        suffix = f"  ({detail})" if detail and not done else ""
        print(f"  [{icon}]  #{gid:<6s} {name}{suffix}")

    if open_hard:
        print(f"\n  >>> {len(open_hard)} HARD GATE(s) block release <<<")
    else:
        print(f"\n  All hard gates passed!")

    if soft:
        done_soft = [s for s in soft if s[2]]
        print(f"\nSOFT GATES ({len(done_soft)}/{len(soft)} done):")
        for gid, name, done, detail in soft:
            icon = "DONE" if done else "    "
            suffix = f"  ({detail})" if detail else ""
            print(f"  [{icon}]  #{gid:<6s} {name}{suffix}")
        print(f"\n  Soft gates are recommended but do not block release.")

    sys.exit(0 if not open_hard else 1)
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
