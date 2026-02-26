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
    import sys
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
