# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Branch health, cleanup, and audit recipes

# Branch cleanup: merged local/remote branches + stale tracking refs
# Usage: just git cleanup          (dry run — preview only)
#        just git cleanup run      (delete branches and prune refs)
[no-cd]
[script]
cleanup mode='dry-run':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    source scripts/scripts/git-helpers.sh
    set -euo pipefail

    MODE="{{ mode }}"

    if [[ "$MODE" != "dry-run" && "$MODE" != "run" ]]; then
        echo "Usage: just git cleanup [dry-run|run]"
        exit 1
    fi

    if [[ "$MODE" == "run" ]]; then
        echo "EXECUTING branch cleanup across all repos"
    else
        echo "DRY RUN — showing what would be cleaned"
        echo "(run 'just git cleanup run' to execute)"
    fi
    echo "Fetching all repos first..."
    _fetch_repo() {
        git -C "$2" fetch --all --prune --quiet 2>/dev/null \
            || echo "  WARN: fetch failed for $1" >&2
    }
    for_each_repo _fetch_repo
    echo ""

    total_local=0
    total_remote=0
    total_stale=0

    cleanup_repo() {
        local label="$1"
        local dir="$2"

        # Must have main branch and origin remote
        git -C "$dir" rev-parse --verify main &>/dev/null || return 0
        git -C "$dir" remote 2>/dev/null | grep -q '^origin$' || return 0

        local local_branches remote_branches stale_refs

        # Local branches merged into origin/main (ancestry + content-equivalent)
        local_branches=$(list_merged_branches "$dir")

        # Remote branches merged into origin/main (exclude main and HEAD pointer)
        remote_branches=$(git -C "$dir" branch -r --merged origin/main 2>/dev/null \
            | grep -E '^[[:space:]]+origin/' \
            | grep -vE 'origin/main$|origin/HEAD' \
            | sed 's|^[[:space:]]*origin/||' || true)

        # Stale remote-tracking refs (remote branch deleted but local ref remains)
        stale_refs=$(git -C "$dir" remote prune origin --dry-run 2>/dev/null \
            | grep '\[would prune\]' \
            | sed 's/.*\[would prune\] //' || true)

        local lc=0 rc=0 sc=0
        [[ -n "$local_branches" ]] && lc=$(echo "$local_branches" | wc -l | tr -d ' ')
        [[ -n "$remote_branches" ]] && rc=$(echo "$remote_branches" | wc -l | tr -d ' ')
        [[ -n "$stale_refs" ]] && sc=$(echo "$stale_refs" | wc -l | tr -d ' ')

        local total=$((lc + rc + sc))
        [[ "$total" -eq 0 ]] && return 0

        echo ""
        echo "── $label ──"

        _BS=30  # branch name column width for cleanup
        if [[ -n "$local_branches" ]]; then
            echo "  Local merged ($lc):"
            while IFS= read -r b; do
                [[ -z "$b" ]] && continue
                local _p=$(( _BS - ${#b} )); [[ $_p -lt 1 ]] && _p=1
                if [[ "$MODE" == "run" ]]; then
                    if git -C "$dir" branch -D "$b" &>/dev/null; then
                        printf "    ${GREEN}✓${NC} %s%*s deleted\n" "$b" "$_p" ""
                    else
                        printf "    ${RED}✗${NC} %s%*s FAILED (currently checked out?)\n" "$b" "$_p" ""
                    fi
                else
                    printf "    · %s\n" "$b"
                fi
            done <<< "$local_branches"
        fi

        if [[ -n "$remote_branches" ]]; then
            echo "  Remote merged ($rc):"
            while IFS= read -r b; do
                [[ -z "$b" ]] && continue
                local _ob="origin/$b"
                local _p=$(( _BS - ${#_ob} )); [[ $_p -lt 1 ]] && _p=1
                if [[ "$MODE" == "run" ]]; then
                    if git -C "$dir" push origin --delete "$b" 2>/dev/null; then
                        printf "    ${GREEN}✓${NC} %s%*s deleted\n" "$_ob" "$_p" ""
                    else
                        printf "    ${RED}✗${NC} %s%*s FAILED (already gone or protected)\n" "$_ob" "$_p" ""
                    fi
                else
                    printf "    · %s\n" "$_ob"
                fi
            done <<< "$remote_branches"
        fi

        if [[ -n "$stale_refs" ]]; then
            echo "  Stale refs ($sc):"
            while IFS= read -r ref; do
                [[ -z "$ref" ]] && continue
                printf "    · %s\n" "$ref"
            done <<< "$stale_refs"
            if [[ "$MODE" == "run" ]]; then
                git -C "$dir" remote prune origin &>/dev/null
                echo "    (pruned)"
            fi
        fi

        total_local=$((total_local + lc))
        total_remote=$((total_remote + rc))
        total_stale=$((total_stale + sc))
    }

    for_each_repo cleanup_repo

    # Summary
    grand_total=$((total_local + total_remote + total_stale))
    if [[ "$grand_total" -eq 0 ]]; then
        echo "All clean — no merged branches or stale refs found."
    else
        echo "Summary: $total_local local, $total_remote remote, $total_stale stale ($grand_total total)"
        if [[ "$MODE" == "dry-run" ]]; then
            echo "Run 'just git cleanup run' to delete these."
        else
            echo "Done."
        fi
    fi

# Clear all stashes across all repos
[no-cd]
[script]
stash-clear:
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh

    cleared=()

    _clear_stash() {
        local label="$1" dir="$2"
        local count
        count=$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            git -C "$dir" stash clear
            status_ok "$label" "cleared $count stash(es)"
            cleared+=("$label")
        fi
    }
    for_each_repo _clear_stash

    echo ""
    if [[ ${#cleared[@]} -eq 0 ]]; then
        echo "No stashes found in any repo."
    else
        echo "Cleared stashes in ${#cleared[@]} repo(s): ${cleared[*]}"
    fi

# Show stashes across all repos
[no-cd]
[script]
stash-list:
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    found=0

    _list_stash() {
        local label="$1" dir="$2"
        local stashes
        stashes=$(git -C "$dir" stash list 2>/dev/null)
        if [[ -n "$stashes" ]]; then
            local count
            count=$(echo "$stashes" | wc -l | tr -d ' ')
            echo "── $label ($count) ──"
            echo "$stashes" | sed 's/^/  /'
            echo ""
            found=1
        fi
    }
    for_each_repo _list_stash

    if [[ "$found" -eq 0 ]]; then
        echo "No stashes in any repo."
    fi

# Comprehensive branch health audit across all repos
# Usage: just git branch-health          (audit only)
#        just git branch-health cleanup  (audit + delete merged/in-main branches)
[no-cd]
[script]
branch-health mode='audit':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    source scripts/scripts/git-helpers.sh
    set -euo pipefail

    echo "── Branch Health Audit ──"
    echo ""
    echo "Fetching..."
    _bh_fetch() {
        git -C "$2" fetch --all --prune --quiet 2>/dev/null \
            || echo "  WARN: fetch failed for $1" >&2
    }
    for_each_repo_parallel _bh_fetch

    merged=0
    stale=0
    gone=0
    active=0

    cutoff_14d=$(date -v-14d +%s 2>/dev/null || date -d "14 days ago" +%s 2>/dev/null)

    _BH_C1=18  # repo column
    _BH_C2=32  # branch column
    _bh_row() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _BH_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _BH_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "%s%*s %s%*s %8s %-12s %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    echo ""
    _bh_row "REPO" "BRANCH" "AGE" "STATUS" "ACTION"
    printf "${DIM}%s${NC}\n" "$(printf '%*s' $(( _BH_C1 + _BH_C2 + 24 )) '' | tr ' ' '-')"

    _bh_check_repo() {
        local label="$1" d="$2"
        [[ "$label" == "vauchi (root)" ]] && label="root"

        local branches
        branches=$(git -C "$d" branch --no-color 2>/dev/null | sed 's/^[* ]*//' | grep -v '^main$' || true)
        [[ -z "$branches" ]] && return 0

        while IFS= read -r br; do
            [[ -z "$br" ]] && continue

            last_epoch=$(git -C "$d" log -1 --format=%ct "$br" 2>/dev/null || echo "0")
            now=$(date +%s)
            age_days=$(( (now - last_epoch) / 86400 ))

            status="active"
            action="-"
            has_remote=false
            git -C "$d" rev-parse --verify "origin/$br" &>/dev/null && has_remote=true
            is_gone=false
            if ! $has_remote; then
                upstream=$(git -C "$d" for-each-ref --format='%(upstream)' "refs/heads/$br" 2>/dev/null)
                [[ -n "$upstream" ]] && is_gone=true
            fi

            if git -C "$d" merge-base --is-ancestor "$br" origin/main 2>/dev/null; then
                if $has_remote; then
                    status="merged"
                    action="- (remote)"
                    active=$((active + 1))
                else
                    status="merged"
                    action="DELETE"
                    merged=$((merged + 1))
                fi
            elif is_branch_in_main "$d" "$br"; then
                if $has_remote; then
                    status="in-main"
                    action="- (remote)"
                    active=$((active + 1))
                else
                    status="in-main"
                    action="DELETE"
                    merged=$((merged + 1))
                fi
            elif $is_gone; then
                status="gone"
                action="RECOVER"
                gone=$((gone + 1))
            elif [[ "$last_epoch" -lt "$cutoff_14d" ]]; then
                status="stale"
                action="REVIEW"
                stale=$((stale + 1))
            else
                active=$((active + 1))
            fi

            if [[ "{{ mode }}" == "cleanup" && "$action" == "DELETE" ]]; then
                if git -C "$d" rev-parse --verify "origin/$br" &>/dev/null; then
                    action="SKIP (remote exists)"
                elif git -C "$d" branch -D "$br" &>/dev/null; then
                    action="DELETED"
                fi
            fi

            _sc=""
            case "$status" in
                merged|in-main) _sc="$GREEN" ;;
                stale) _sc="$YELLOW" ;;
                gone) _sc="$RED" ;;
            esac
            _ac=""
            case "$action" in
                DELETE|DELETED) _ac="$RED" ;;
                REVIEW|RECOVER) _ac="$YELLOW" ;;
            esac
            _p1=$(( _BH_C1 - ${#label} )); [[ $_p1 -lt 1 ]] && _p1=1
            _p2=$(( _BH_C2 - ${#br} )); [[ $_p2 -lt 1 ]] && _p2=1
            printf "%s%*s %s%*s %8s ${_sc}%-12s${NC} ${_ac}%s${NC}\n" \
                "$label" "$_p1" "" "$br" "$_p2" "" "${age_days}d" "$status" "$action"
        done <<< "$branches"
    }
    for_each_repo _bh_check_repo

    echo ""
    summary="Summary: $merged merged/in-main, $stale stale (>14d), $gone gone (remote deleted, unmerged), $active active"
    echo "$summary"
    if [[ "$merged" -gt 0 && "{{ mode }}" != "cleanup" ]]; then
        echo "Run 'just git branch-health cleanup' to delete merged branches"
    fi
    if [[ "$gone" -gt 0 ]]; then
        echo "Gone branches have unmerged commits — re-push with 'git -C <repo> push -u origin <branch>'"
    fi

# Inspect a specific branch across ALL repos
# Shows: which repos have it, commits ahead/behind main, last commit age, status
# Usage: just git branch-inspect tidy/phase1-audit-fixes
#        just git branch-inspect feature/my-feature
[no-cd]
[script]
branch-inspect name:
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    source scripts/scripts/git-helpers.sh
    set -euo pipefail

    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just git branch-inspect <branch-name>" >&2
        exit 1
    fi

    BRANCH="{{ name }}"
    echo "── Branch Inspection: $BRANCH ──"
    echo ""
    echo "Fetching..."
    _bi_fetch() {
        git -C "$2" fetch --all --prune --quiet 2>/dev/null \
            || echo "  WARN: fetch failed for $1" >&2
    }
    for_each_repo_parallel _bi_fetch
    echo ""

    found=0
    with_commits=0
    empty=0

    _BI_C1=24  # repo column
    _bi_row() {
        local c1="$1"; shift
        local _p=$(( _BI_C1 - ${#c1} )); [[ $_p -lt 1 ]] && _p=1
        printf "%s%*s %8s %8s %8s %-12s %s\n" "$c1" "$_p" "" "$@"
    }
    _bi_row "REPO" "AHEAD" "BEHIND" "AGE" "STATUS" "LAST COMMIT"
    printf "${DIM}%s${NC}\n" "$(printf '%*s' $(( _BI_C1 + 52 )) '' | tr ' ' '-')"

    _bi_check_repo() {
        local label="$1" d="$2"

        # Check if branch exists in this repo
        git -C "$d" rev-parse --verify "$BRANCH" &>/dev/null || return 0
        found=$((found + 1))

        local ahead behind last_epoch now age_days last_msg status
        ahead=$(git -C "$d" rev-list --count origin/main.."$BRANCH" 2>/dev/null || echo "?")
        behind=$(git -C "$d" rev-list --count "$BRANCH"..origin/main 2>/dev/null || echo "?")

        last_epoch=$(git -C "$d" log -1 --format=%ct "$BRANCH" 2>/dev/null || echo "0")
        now=$(date +%s)
        age_days=$(( (now - last_epoch) / 86400 ))

        last_msg=$(git -C "$d" log -1 --format=%s "$BRANCH" 2>/dev/null || echo "")
        [[ ${#last_msg} -gt 50 ]] && last_msg="${last_msg:0:47}..."

        if [[ "$ahead" == "0" ]]; then
            status="empty"
            empty=$((empty + 1))
        elif is_branch_in_main "$d" "$BRANCH"; then
            status="merged"
        else
            status="active"
            with_commits=$((with_commits + 1))
        fi

        local _sc=""
        case "$status" in
            merged|in-main|empty) _sc="$DIM" ;;
            active) _sc="$GREEN" ;;
        esac
        local _p=$(( _BI_C1 - ${#label} )); [[ $_p -lt 1 ]] && _p=1
        printf "%s%*s %8s %8s %7sd ${_sc}%-12s${NC} %s\n" "$label" "$_p" "" "$ahead" "$behind" "$age_days" "$status" "$last_msg"
    }
    for_each_repo _bi_check_repo

    echo ""
    if [[ "$found" -eq 0 ]]; then
        echo "Branch '$BRANCH' not found in any repo."
    else
        echo "Summary: $found repos have branch, $with_commits with commits, $empty empty (same as main)"
    fi

# Show branches with no commits in N days (default: 14)
# Usage: just git stale-branches         (14-day threshold)
#        just git stale-branches 7       (7-day threshold)
[no-cd]
[script]
stale-branches days='14':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    source scripts/scripts/git-helpers.sh
    set -euo pipefail
    threshold="{{ days }}"
    cutoff=$(date -v-${threshold}d +%s 2>/dev/null || date -d "$threshold days ago" +%s 2>/dev/null)

    # Fetch so origin/main is current for status checks
    _sb_fetch() {
        git -C "$2" fetch origin main --quiet 2>/dev/null \
            || echo "  WARN: fetch failed for $1" >&2
    }
    for_each_repo_parallel _sb_fetch

    _SB_C1=20  # repo column
    _SB_C2=30  # branch column
    _sb_row() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _SB_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _SB_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "%s%*s %s%*s %-12s %-6s %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    _sb_row "REPO" "BRANCH" "LAST COMMIT" "AGE" "STATUS"
    printf "${DIM}%s${NC}\n" "$(printf '%*s' $(( _SB_C1 + _SB_C2 + 22 )) '' | tr ' ' '-')"

    total=0
    deletable=0

    _sb_check_repo() {
        local label="$1" d="$2"

        local branches
        branches=$(git -C "$d" branch --no-color 2>/dev/null | grep -v 'main$' | sed 's/^[* ]*//' || true)
        [[ -z "$branches" ]] && return 0

        while IFS= read -r br; do
            [[ -z "$br" ]] && continue
            local last_epoch last_date
            last_epoch=$(git -C "$d" log -1 --format=%ct "$br" 2>/dev/null || echo "0")
            last_date=$(git -C "$d" log -1 --format=%ci "$br" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            if [[ "$last_epoch" -lt "$cutoff" ]]; then
                local now age_days status
                now=$(date +%s)
                age_days=$(( (now - last_epoch) / 86400 ))
                status="unmerged"
                if is_branch_in_main "$d" "$br"; then
                    status="merged"
                fi
                if [[ "$status" != "unmerged" ]]; then
                    deletable=$((deletable + 1))
                fi
                local _sc=""
                case "$status" in
                    merged|in-main) _sc="$GREEN" ;;
                    unmerged) _sc="$YELLOW" ;;
                esac
                local _p1=$(( _SB_C1 - ${#label} )); [[ $_p1 -lt 1 ]] && _p1=1
                local _p2=$(( _SB_C2 - ${#br} )); [[ $_p2 -lt 1 ]] && _p2=1
                printf "%s%*s %s%*s %-12s %-6s ${_sc}%s${NC}\n" "$label" "$_p1" "" "$br" "$_p2" "" "$last_date" "${age_days}d" "$status"
                total=$((total + 1))
            fi
        done <<< "$branches"
    }
    for_each_repo _sb_check_repo

    echo ""
    if [[ "$total" -eq 0 ]]; then
        echo "No branches older than ${threshold} days."
    else
        echo "$total stale branch(es) (no commits in ${threshold}+ days)"
        if [[ "$deletable" -gt 0 ]]; then
            echo "$deletable already in main — safe to delete"
        fi
        echo "Clean up with: just git cleanup run"
    fi
