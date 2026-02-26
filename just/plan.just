# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Markdown-plan task tracking recipes

# Validate .plan.md files (single file or directory)
[group('tools')]
[script('bash')]
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
    import sys, types
    # Shim pygit2 to avoid ImportError (mdplan.__init__ imports .git which needs it)
    sys.modules.setdefault('pygit2', types.ModuleType('pygit2'))
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
[script('bash')]
plan-history file:
    set -euo pipefail
    if ! command -v mdplan &>/dev/null; then
        echo "ERROR: mdplan not installed — run 'just setup'"
        exit 1
    fi
    mdplan history "{{file}}"

# Open burn-up chart in browser (requires git history)
[group('tools')]
[script('bash')]
plan-plot file:
    set -euo pipefail
    if ! command -v mdplan &>/dev/null; then
        echo "ERROR: mdplan not installed — run 'just setup'"
        exit 1
    fi
    mdplan plot "{{file}}"

# List all .plan.md files with task counts
[group('tools')]
[script('bash')]
plan-list dir='_private/docs':
    set -euo pipefail
    WORKSPACE_ROOT="$(pwd)"
    echo "Plan files in {{dir}}:"
    echo ""
    printf "%-60s %s\n" "FILE" "STATUS"
    printf "%-60s %s\n" "----" "------"
    while IFS= read -r -d '' file; do
        relpath="${file#$WORKSPACE_ROOT/}"
        stats=$(python3 << PYEOF
    import sys, types
    sys.modules.setdefault('pygit2', types.ModuleType('pygit2'))
    sys.path.insert(0, '$WORKSPACE_ROOT/markdown-plan/python/src')
    from mdplan.count import count_all_tasks, count_remaining_tasks
    with open('$file') as f:
        text = f.read()
    total = count_all_tasks(text)
    remaining = count_remaining_tasks(text)
    done = total - remaining
    pct = int(100 * done / total) if total > 0 else 0
    print(f'{done}/{total} done ({pct}%)')
    PYEOF
        ) 2>/dev/null || echo "parse error"
        printf "%-60s %s\n" "$relpath" "$stats"
    done < <(find "{{dir}}" -name "*.plan.md" -print0 | sort -z)

# Show remaining tasks from master plan
[group('tools')]
[script('bash')]
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
[script('bash')]
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
        readme = os.path.join(problems_dir, d, 'README.md')
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

    if not phase_filter:
        # Summary mode
        print(f'Problem records: {total} total\n')
        for phase in order:
            items = by_status.get(phase, [])
            if items:
                print(f'  {phase:15s} {len(items):3d}')
        unknown = [k for k in by_status if k not in order]
        for k in unknown:
            print(f'  {k:15s} {len(by_status[k]):3d}')
        print()
        active = sum(len(by_status.get(p, [])) for p in ['intake', 'investigating', 'planning', 'implementing', 'testing'])
        print(f'Active: {active}  Done: {len(by_status.get("done", []))}  Archived: {len(by_status.get("archived", []))}')
    else:
        items = by_status.get(phase_filter, [])
        if not items:
            print(f'No problems in phase: {phase_filter}')
        else:
            print(f'{phase_filter.upper()} ({len(items)})\n')
            for pr, d in items:
                print(f'  [{pr:6s}] {d}')
    PYEOF

# Show .plan.md files with no git changes in N days
[group('tools')]
[script('bash')]
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
    done < <(find _private/docs -name "*.plan.md" -print0)
    echo ""
    echo "$STALE stale plan(s) found."
