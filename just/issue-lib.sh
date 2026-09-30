# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Issue claims (ADR-073 stage 1): work is queued as issues in vauchi/private.
# Claiming #N creates branch issue/<N> there — branch creation is GitLab's
# only atomic primitive, so two sessions cannot both win — and comments the
# claim stamp (session + slot) on the issue, since the bot is shared and no
# stamp commit may land on the work branch. Needs slot-lib.sh sourced first.

ISSUE_REPO="${ISSUE_REPO:-vauchi%2Fprivate}"
ISSUE_STALE_HOURS="${ISSUE_STALE_HOURS:-72}"
ISSUE_CLAIM_LOG="${ISSUE_CLAIM_LOG:-_private/docs/2026-09-25-claim-collisions.md}"

# Hours since an ISO-8601 timestamp; jq keeps it identical on BSD, GNU and
# BusyBox. Notes end in Z but commit dates carry the committer's offset
# (+02:00), which fromdateiso8601 rejects, so offsets are folded in by hand.
_issue_age_hours() {
    printf '"%s"' "$1" | jq -r '
        sub("\\.[0-9]+"; "")
        | if test("Z$") then fromdateiso8601
          else capture("^(?<t>.{19})(?<sign>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")
               | ((.t + "Z") | fromdateiso8601)
                 - (if .sign == "+" then 1 else -1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60)
          end
        | ((now - .) / 3600 | floor)'
}

# Latest claim or takeover note on #N, as JSON; empty when none.
_issue_holder_note() {
    glab api "projects/$ISSUE_REPO/issues/$1/notes?sort=desc&order_by=created_at&per_page=50" 2>/dev/null \
        | jq -c '[.[] | select(.body | test("^(claim|takeover): "))][0] // empty'
}

_issue_log_refusal() {
    [ -f "$ISSUE_CLAIM_LOG" ] || return 0
    printf -- '- %s | #%s | %s | %sh\n' "$(date -u +%Y-%m-%d)" "$1" "$2" "$3" >> "$ISSUE_CLAIM_LOG"
}

issue_claim() {
    local number="$1" tag state note body holder branch_date age note_age
    tag=$(slot_claim_tag .)
    state=$(glab api "projects/$ISSUE_REPO/issues/$number" 2>/dev/null | jq -r '.state // empty' || true)
    if [ "$state" != opened ]; then
        echo "ERROR: #$number is not an open issue in vauchi/private"
        return 1
    fi
    if glab api -X POST "projects/$ISSUE_REPO/repository/branches" \
        -f "branch=issue/$number" -f ref=main >/dev/null 2>&1; then
        glab api -X POST "projects/$ISSUE_REPO/issues/$number/notes" -f "body=claim: $tag" >/dev/null
        echo "✓ Claimed #$number ($tag)"
        echo "  Work on branch issue/$number: git -C _private fetch origin issue/$number && git -C _private switch issue/$number"
        echo "  Other repos: just git branch issue/$number <repos>"
        return 0
    fi
    note=$(_issue_holder_note "$number")
    body=$(printf '%s' "$note" | jq -r '.body // ""')
    holder=$(printf '%s' "$body" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
    if [ -n "$holder" ] && [ "$holder" = "$(slot_session_id)" ]; then
        echo "✓ #$number is already yours ($tag)"
        return 0
    fi
    branch_date=$(glab api "projects/$ISSUE_REPO/repository/branches/issue%2F$number" | jq -r '.commit.committed_date')
    age=$(_issue_age_hours "$branch_date")
    if [ -n "$note" ]; then
        note_age=$(_issue_age_hours "$(printf '%s' "$note" | jq -r '.created_at')")
        [ "$note_age" -lt "$age" ] && age=$note_age
    fi
    if [ "$age" -ge "$ISSUE_STALE_HOURS" ]; then
        glab api -X POST "projects/$ISSUE_REPO/issues/$number/notes" \
            -f "body=takeover: $tag (previous: $(slot_claim_owner "$body"), idle ${age}h)" >/dev/null
        echo "✓ Took over stale #$number (idle ${age}h) — fetch issue/$number into this slot"
        return 0
    fi
    echo "BLOCKED: #$number is held by $(slot_claim_owner "$body") (active ${age}h ago)"
    _issue_log_refusal "$number" held-by-other "$age"
    return 1
}

issue_release() {
    local number="$1" tag body holder ahead siblings repository
    tag=$(slot_claim_tag .)
    body=$(_issue_holder_note "$number" | jq -r '.body // ""')
    holder=$(printf '%s' "$body" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
    if [ "$holder" != "$(slot_session_id)" ]; then
        echo "  #$number is not held by this session ($(slot_claim_owner "$body")) — left as is"
        return 1
    fi
    # Merged-ness is patch equivalence (git cherry, VGT03), not ancestry:
    # GitLab rebases a branch that is behind main when it merges it.
    if [ -e _private/.git ] && git -C _private fetch -q origin \
        "+refs/heads/issue/$number:refs/remotes/origin/issue/$number" \
        "+refs/heads/main:refs/remotes/origin/main" 2>/dev/null; then
        ahead=$(git -C _private cherry origin/main "origin/issue/$number" | grep -c '^+' || true)
    else
        ahead=$(glab api "projects/$ISSUE_REPO/repository/compare?from=main&to=issue%2F$number" \
            | jq '.commits | length')
    fi
    if [ "$ahead" -gt 0 ]; then
        echo "  issue/$number has $ahead commit(s) not on main — merge them first; the claim stays"
        return 1
    fi
    siblings=$(_issue_sibling_branches "$number")
    if printf '%s\n' "$siblings" | grep -q '^unmerged '; then
        for repository in $(printf '%s\n' "$siblings" | sed -n 's/^unmerged //p'); do
            echo "  issue/$number in $(basename "$repository") has commits not on main — merge them first; the claim stays"
        done
        return 1
    fi
    glab api -X DELETE "projects/$ISSUE_REPO/repository/branches/issue%2F$number" >/dev/null
    glab api -X POST "projects/$ISSUE_REPO/issues/$number/notes" -f "body=release: $tag" >/dev/null
    for repository in $(printf '%s\n' "$siblings" | sed -n 's/^merged //p'); do
        git -C "$repository" push -q origin --delete "issue/$number" \
            && echo "  removed merged issue/$number in $(basename "$repository")"
    done
    echo "✓ Released #$number"
}

# "merged <dir>" / "unmerged <dir>" for every other repo of the slot whose
# remote still has issue/<N>; the vauchi/private lock is handled via the API.
_issue_sibling_branches() {
    local number="$1" repository
    for repository in $(slot_repositories "$(pwd -P)"); do
        [ "$(basename "$repository")" = _private ] && continue
        git -C "$repository" ls-remote --exit-code --heads origin "issue/$number" >/dev/null 2>&1 || continue
        git -C "$repository" fetch -q origin \
            "+refs/heads/issue/$number:refs/remotes/origin/issue/$number" \
            "+refs/heads/main:refs/remotes/origin/main" || continue
        if ! git -C "$repository" cherry origin/main "origin/issue/$number" | grep -q '^+'; then
            echo "merged $repository"
        else
            echo "unmerged $repository"
        fi
    done
}

# The bot account is shared, so a comment names the session that wrote it.
_issue_signed_body() {
    printf '%s\n\n— %s' "$1" "$(slot_claim_tag .)"
}

issue_comment() {
    local number="$1" body="$2" response
    if [ -z "${body//[[:space:]]/}" ]; then
        echo "ERROR: empty comment — nothing posted to #$number"
        return 1
    fi
    response=$(glab api -X POST "projects/$ISSUE_REPO/issues/$number/notes" \
        -f "body=$(_issue_signed_body "$body")") || {
        echo "ERROR: GitLab refused the comment on #$number: $response"
        return 1
    }
    echo "✓ Commented on #$number (note $(printf '%s' "$response" | jq -r '.id'))"
}

# Replies land in the thread of an existing note, found through the issue's
# discussions: GitLab addresses a reply by discussion id, not note id.
issue_comment_respond() {
    local number="$1" note="$2" body="$3" discussions thread response
    case "$note" in
        '' | *[!0-9]*)
            echo "ERROR: note id must be a number, got '$note'"
            return 1
            ;;
    esac
    if [ -z "${body//[[:space:]]/}" ]; then
        echo "ERROR: empty reply — nothing posted to #$number"
        return 1
    fi
    discussions=$(glab api "projects/$ISSUE_REPO/issues/$number/discussions?per_page=100" --paginate) || {
        echo "ERROR: could not list the discussions on #$number: $discussions"
        return 1
    }
    thread=$(printf '%s' "$discussions" | jq -rs --argjson id "$note" \
        'add | map(select(.notes | any(.id == $id))) | .[0].id // empty')
    if [ -z "$thread" ]; then
        echo "ERROR: #$number has no note $note — nothing posted"
        return 1
    fi
    response=$(glab api -X POST "projects/$ISSUE_REPO/issues/$number/discussions/$thread/notes" \
        -f "body=$(_issue_signed_body "$body")") || {
        echo "ERROR: GitLab refused the reply on #$number: $response"
        return 1
    }
    echo "✓ Replied to note $note on #$number (note $(printf '%s' "$response" | jq -r '.id'))"
}

# Open issues by priority, marking the claimed ones: one issue listing and
# one branch listing, never a per-issue call (ADR-073 consequence).
# Group-board columns in lifecycle order (ADR-073 §Decision 13).
ISSUE_BOARD_COLUMNS="backlog deferred intake refreshing investigating select-solution planning planned implementing review testing blocked"

# Every open issue as {iid, title, priority, status, rank, blocked}, sorted by
# priority. Paginated: the backlog alone is over 100 issues.
_issue_open_issues() {
    glab api "projects/$ISSUE_REPO/issues?state=opened&per_page=100" --paginate | jq -s '
        def with_prefix($prefix): map(select(startswith($prefix)) | sub($prefix; ""))[0];
        add // [] | map({iid, title,
            priority: (.labels | with_prefix("priority::") // "-"),
            status: (.labels | with_prefix("status::") // "intake"),
            blocked: (.labels | index("blocked") != null)})
        | map(.rank = ({"critical": 0, "high": 1, "medium": 2, "low": 3}[.priority] // 4))
        | sort_by(.rank, .iid)'
}

issue_queue() {
    local claimed
    claimed=$(glab api "projects/$ISSUE_REPO/repository/branches?search=^issue/&per_page=100" \
        | jq -r '[.[].name | sub("^issue/"; "")] | join(" ")')
    _issue_open_issues | jq -r --arg claimed " $claimed " '
        def row: "  #\(.iid)\t\(.priority)\t\(if .claimed then "[claimed] " else "" end)\(if .blocked then "[blocked] " else "" end)\(.status)\t\(.title)";
        def section($title; $items): if ($items | length) > 0 then "  \($title)", ($items[] | row) else empty end;
        map(.iid as $number | .claimed = ($claimed | contains(" \($number) "))) as $all
        | ["backlog", "deferred"] as $shelf
        # Closest to done first within a priority (#449): finish before starting.
        | ["planned", "planning", "investigating", "refreshing", "intake"] as $agents
        | ["testing"] as $verify
        | ["select-solution", "review"] as $maintainer
        | section("verify first (testing: close it if you can check it)";
                  [$all[] | select(.status as $s | $verify | index($s))]),
          section("ready for agents"; [$all[] | select(.status as $s | $agents | index($s))]
                  | sort_by(.rank, (.status as $s | $agents | index($s)), .iid)),
          section("waiting on maintainer"; [$all[] | select(.status as $s | $maintainer | index($s))]),
          section("in flight"; [$all[] | select(.status as $s | ($shelf + $agents + $verify + $maintainer) | index($s) | not)]),
          "  (\([$all[] | select(.status == "backlog")] | length) backlog, \([$all[] | select(.status == "deferred")] | length) deferred — just gitlab board)"'
}

# The group board in the terminal: one section per non-empty column. Backlog
# and deferred show only their count unless called with "all".
issue_board() {
    local fold=1
    [[ "${1:-}" == "all" ]] && fold=0
    _issue_open_issues | jq -r --arg columns "$ISSUE_BOARD_COLUMNS" --argjson fold "$fold" '
        . as $all | ($columns | split(" ")) as $order
        | ($order + ([$all[].status] | unique | map(select(. as $s | $order | index($s) | not))))[]
        | . as $column | [$all[] | select(.status == $column)] as $items
        | select($items | length > 0)
        | "── \($column) (\($items | length)) ──",
          (if $fold == 1 and ($column == "backlog" or $column == "deferred") then empty
           else $items[] | "  #\(.iid)\t\(.priority)\t\(.title)" end)'
}

# Current issue claims with their holder: one note query per claimed issue,
# bounded by the handful of live claims.
issue_claims() {
    local number body branch_date
    for number in $(glab api "projects/$ISSUE_REPO/repository/branches?search=^issue/&per_page=100" \
        | jq -r '.[].name | sub("^issue/"; "")'); do
        body=$(_issue_holder_note "$number" | jq -r '.body // ""')
        branch_date=$(glab api "projects/$ISSUE_REPO/repository/branches/issue%2F$number" \
            | jq -r '.commit.committed_date')
        printf '  #%-6s %-32s branch %sh old\n' "$number" "$(slot_claim_owner "$body")" \
            "$(_issue_age_hours "$branch_date")"
    done
}

# Issue numbers of the live claims (issue/<N> branches) whose holder note
# names the current session — what session-end must release or hand off (#415).
issue_session_claims() {
    local number me
    me=$(slot_session_id)
    for number in $(glab api "projects/$ISSUE_REPO/repository/branches?search=^issue/&per_page=100" \
        | jq -r '.[].name | sub("^issue/"; "")'); do
        [[ "$(slot_claim_owner "$(_issue_holder_note "$number" | jq -r '.body // ""')")" == "$me"* ]] \
            && echo "$number"
    done
    return 0
}

# Prints the first GitLab closing reference in the text ("close #14",
# "Fixes vauchi/private#7") and succeeds; fails when there is none. GitLab
# closes such issues on merge, before issue-status-sync can derive their
# status, so ADR-073 MRs must not use them (#70). Mirrors GitLab's default
# closing pattern: close/fix/resolve/implement and their -s/-d/-ing forms.
issue_closing_reference() {
    printf '%s\n' "$1" | grep -oiE \
        '(^|[^A-Za-z])(close[sd]?|closing|fix(e[sd]|ing)?|resolve[sd]?|resolving|implement(s|ed|ing)?):? +(issues? +)?[A-Za-z0-9_./-]*#[0-9]+' \
        | head -1 | grep .
}

# Keeps an ADR-073 claim branch alive past its MR's merge: every repo
# deletes source branches by default, even on API-made MRs. GitLab has
# answered this PUT with HTTP 500 immediately after creating the MR and
# accepted the same call moments later (!2804, core!1640), so it is retried.
issue_keep_mr_branch() {
    local project=${1//\//%2F} branch=$2 iid attempt
    local delay=${ISSUE_KEEP_BRANCH_RETRY_DELAY:-3}
    iid=$(glab api "projects/${project}/merge_requests?state=opened&source_branch=${branch//\//%2F}" \
        | jq -r '.[0].iid // empty')
    [[ -n "$iid" ]] || return 0
    for attempt in 1 2 3; do
        if glab api -X PUT "projects/${project}/merge_requests/${iid}" \
            -f remove_source_branch=false >/dev/null; then
            echo "  !${iid} keeps $branch after merge (ADR-073 claim branch)"
            return 0
        fi
        [[ $attempt -lt 3 ]] && sleep "$delay"
    done
    echo "ERROR: !${iid} would delete $branch on merge — set remove_source_branch=false by hand" >&2
    return 1
}
