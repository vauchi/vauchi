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
        echo "✓ Claimed #$number ($tag) — work on branch issue/$number"
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
    local number="$1" tag body holder ahead
    tag=$(slot_claim_tag .)
    body=$(_issue_holder_note "$number" | jq -r '.body // ""')
    holder=$(printf '%s' "$body" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
    if [ "$holder" != "$(slot_session_id)" ]; then
        echo "  #$number is not held by this session ($(slot_claim_owner "$body")) — left as is"
        return 1
    fi
    ahead=$(glab api "projects/$ISSUE_REPO/repository/compare?from=main&to=issue%2F$number" \
        | jq '.commits | length')
    if [ "$ahead" -gt 0 ]; then
        echo "  issue/$number has $ahead commit(s) not on main — merge them first; the claim stays"
        return 1
    fi
    glab api -X DELETE "projects/$ISSUE_REPO/repository/branches/issue%2F$number" >/dev/null
    glab api -X POST "projects/$ISSUE_REPO/issues/$number/notes" -f "body=release: $tag" >/dev/null
    echo "✓ Released #$number"
}

# Open issues by priority, marking the claimed ones: one issue listing and
# one branch listing, never a per-issue call (ADR-073 consequence).
issue_queue() {
    local claimed
    claimed=$(glab api "projects/$ISSUE_REPO/repository/branches?search=^issue/&per_page=100" \
        | jq -r '[.[].name | sub("^issue/"; "")] | join(" ")')
    glab api "projects/$ISSUE_REPO/issues?state=opened&per_page=100" | jq -r --arg claimed " $claimed " '
        def rank: (map(select(startswith("priority::")) | sub("priority::"; ""))[0] // "none") as $p
            | {"critical": 0, "high": 1, "medium": 2, "low": 3}[$p] // 4;
        map(.iid as $number | {iid, title, labels, rank: (.labels | rank),
             priority: ((.labels | map(select(startswith("priority::")) | sub("priority::"; "")))[0] // "-"),
             blocked: (.labels | index("blocked") != null),
             claimed: ($claimed | contains(" \($number) "))})
        | sort_by(.rank, .iid)[]
        | "  #\(.iid)\t\(.priority)\t\(if .claimed then "[claimed] " else "" end)\(if .blocked then "[blocked] " else "" end)\(.title)"'
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
