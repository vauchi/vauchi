# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab operations: MRs, pipelines, issues
# Usage: just gitlab <recipe>

set shell := ["bash", "-cu"]
set script-interpreter := ["bash", "-eu"]

# Metrics repo groups (non-overlapping — each repo in exactly one group)
metrics_coverage_repos := "core cli tui relay ohttp-relay"
metrics_binary_drift_repos := "linux-gtk"
metrics_drift_only_repos := "linux-qt macos windows web-demo"
metrics_all_repos := "core cli tui relay ohttp-relay linux-gtk linux-qt macos windows web-demo"

# ── Helpers ─────────────────────────────────────────────────────────

[private]
[no-cd]
[script]
_check-auth:
    if ! glab auth status &>/dev/null; then
        echo "ERROR: glab not authenticated — run 'glab auth login'"
        exit 1
    fi

# ── Pipeline Notifications ─────────────────────────────────────────

# Enable broken-pipeline email for a project's default branch.
# Usage: just gitlab pipeline-email-enable <repo> <recipient>
[no-cd]
[script]
pipeline-email-enable repo recipient:
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    endpoint="projects/vauchi%2F${r}/integrations/pipelines-email"
    glab api -X PUT "$endpoint" \
      -f "recipients={{recipient}}" \
      -f "notify_only_broken_pipelines=true" \
      -f "branches_to_be_notified=default" \
      -f "pipeline_events=true" >/dev/null
    settings=$(glab api "$endpoint")
    if ! printf '%s\n' "$settings" | jq -e --arg recipient "{{recipient}}" '
      .active == true
      and ((.pipeline_events // .properties.pipeline_events) == true)
      and ((.notify_only_broken_pipelines
            // .properties.notify_only_broken_pipelines) == true)
      and ((.branches_to_be_notified
            // .properties.branches_to_be_notified) == "default")
      and (((.recipients // .properties.recipients) | split(","))
            | index($recipient) != null)
    ' >/dev/null; then
        echo "ERROR: pipeline email integration verification failed for vauchi/$r" >&2
        exit 1
    fi
    echo "Enabled broken default-branch pipeline emails for vauchi/$r -> {{recipient}}"

# Disable pipeline failure emails for a project.
# Usage: just gitlab pipeline-email-disable <repo>
[no-cd]
[script]
pipeline-email-disable repo:
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab api -X DELETE \
      "projects/vauchi%2F${r}/integrations/pipelines-email" >/dev/null
    echo "Disabled pipeline emails for vauchi/$r"

# ── MR Operations ──────────────────────────────────────────────────

# List open merge requests
[no-cd]
[script]
mr-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab mr list -R "$p"

# View merge request details
[no-cd]
[script]
mr-view id repo='' comments='false':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    view_args=()
    if [[ {{ quote(comments) }} == true ]]; then
        view_args+=(--comments)
    fi
    glab mr view "{{id}}" -R "$p" "${view_args[@]}"

# Re-sync an existing MR's title + description to the current commits.
# Usage: just gitlab mr-update [repo] [title]
#   just gitlab mr-update core                     # rebuild title+body from commits
#   just gitlab mr-update core "feat: my feature"  # custom title, rebuild body
#
# Use when commits accumulate on a branch and the title/body auto-filled at
# mr-create time drift from the MR's actual contents (the recurring stale-title
# problem). Rebuilds the body from `origin/main..HEAD` with the same @-escaping
# as mr-create. Title defaults to the first commit subject; pass an explicit
# title to override (the usual reason to run this).
[no-cd]
[script]
mr-update repo='' title='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    workspace_root=$(pwd)
    branch=$(git -C "$dir" branch --show-current)
    if [[ "$branch" == "main" ]]; then
        echo "ERROR: cannot update an MR from the main branch"
        exit 1
    fi
    # Find the open MR for this branch.
    iid=$(glab api "projects/vauchi%2F${r}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
    if [[ -z "$iid" ]]; then
        echo "ERROR: no open MR found for branch '$branch' in $p"
        exit 1
    fi
    # Title: explicit arg, else the first commit subject (same as mr-create).
    # `quote()` shell-quotes the value. A bare "{{ title }}" splices the
    # argument in as raw text, so any double quote in a title closes the
    # string early and the script dies on a parse error before it runs.
    mr_title={{ quote(title) }}
    # `just gitlab` recipe args are positional (module recipe), so a
    # `title=...` invocation form leaks the prefix in verbatim — strip it.
    mr_title="${mr_title#title=}"
    if [[ -z "$mr_title" ]]; then
        mr_title=$(git -C "$dir" log origin/main..HEAD --reverse --format=%s | sed -n 1p)
    fi
    # Body: rebuild from commit bodies, strip Co-Authored-By, escape @mentions,
    # collapse blanks — identical pipeline to mr-create so the two stay in sync.
    mr_body=$(git -C "$dir" log origin/main..HEAD --reverse --format="- %s%n%n%b" \
        | grep -v '^Co-Authored-By:' \
        | "$workspace_root/scripts/scripts/escape-mr-mentions.py" \
        | awk 'length($0) > 0 { blank=0; print; next } blank == 0 { print; blank=1 }')
    if git -C "$dir" log origin/main..HEAD --format="%b" | grep -q '^Co-Authored-By:'; then
        coauthor=$(git -C "$dir" log origin/main..HEAD --format="%b" | grep '^Co-Authored-By:' | sed -n 1p)
        mr_body=$(printf '%s\n\n%s' "$mr_body" "$coauthor")
    fi
    # ADR-073: a closing keyword ("close #14") makes GitLab close the issue
    # on merge, before issue-status-sync can derive its status (#70).
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    if [[ "${MR_ALLOW_CLOSING:-}" != "1" ]] && closing=$(issue_closing_reference "$mr_title"$'\n'"$mr_body"); then
        echo "ERROR: MR text would close an issue on merge: '${closing# }'."
        echo "       Refer to the issue without a closing keyword, e.g. '(#14)';"
        echo "       override deliberately with MR_ALLOW_CLOSING=1."
        exit 1
    fi
    # Defence in depth: no bare `@word` reaches GitLab (mirrors mr-create).
    if ! printf '%s' "$mr_body" \
       | "$workspace_root/scripts/scripts/escape-mr-mentions.py" --check; then
        echo 'ERROR: aborting glab mr update — body has unsafe @-mentions.'
        echo '       (See script output above for the offending tags.)'
        exit 1
    fi
    glab mr update "$iid" -R "$p" --title "$mr_title" --description "$mr_body"
    echo "Updated $p!$iid (title + body) from $(git -C "$dir" rev-list --count origin/main..HEAD) commit(s) on $branch."
    # The rebuild above replaced the whole description, dropping any
    # auto-linked section. Re-run the pass so refreshing a stale title
    # does not cost the MR its cross-repo links.
    just gitlab _autolink "{{repo}}"

# Create merge request from current branch
# Usage: just gitlab mr-create [repo] [title] [description_file]
#   just gitlab mr-create core                    # auto-fill from commits
#   just gitlab mr-create core "feat: my feature" # custom title
#
# After creating, scans sibling repos on the same branch and auto-links
# any open MRs into a "## Related MRs (auto-linked)" section. Prevents
# the "forgot to mention related MR" cascade (E13→E14→E15 in
# .claude/docs/claude-errors-and-misjudgments.md). Set MR_NO_AUTOLINK=1
# to skip the auto-link pass.
[no-cd]
[script]
mr-create repo='' title='' description_file='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    workspace_root=$(pwd)
    branch=$(git -C "$dir" branch --show-current)
    if [[ "$branch" == "main" ]]; then
        echo "ERROR: cannot create MR from main branch"
        exit 1
    fi
    mr_description_file={{ quote(description_file) }}
    if [[ -n "$mr_description_file" && ! -s "$mr_description_file" ]]; then
        echo "ERROR: missing or empty description file: $mr_description_file" >&2
        exit 1
    fi
    # A rejected hook must stop publication; only the caller can classify a
    # rebase rejection and decide whether a lease-protected retry is valid.
    git -C "$dir" push -u origin "$branch"
    # Build title and description explicitly to sanitize @ mentions.
    # --fill passes commit body verbatim, which may contain @tags that
    # ping people on GitLab (e.g., Co-Authored-By: ... <noreply@anthropic.com>).
    # See mr-update: quote() is required, raw interpolation breaks on
    # any title containing a double quote.
    mr_title={{ quote(title) }}
    # `just gitlab` recipe args are positional (module recipe), so a
    # `title=...` invocation form leaks the prefix in verbatim — strip it.
    mr_title="${mr_title#title=}"
    if [[ -z "$mr_title" ]]; then
        mr_title=$(git -C "$dir" log origin/main..HEAD --reverse --format=%s | sed -n 1p)
    fi
    # Build description from commit bodies:
    # 1. Strip Co-Authored-By trailers (added once at the bottom instead)
    # 2. Escape `@word` to prevent GitLab mentions — markdown-aware so
    #    references already inside code spans (e.g. `@Published var x`)
    #    are NOT double-wrapped (which produces broken nesting that
    #    GitLab parses as a bare mention — see vauchi/ios!370).
    # 3. Collapse repeated blank lines
    mr_body=$(git -C "$dir" log origin/main..HEAD --reverse --format="- %s%n%n%b" \
        | grep -v '^Co-Authored-By:' \
        | "$workspace_root/scripts/scripts/escape-mr-mentions.py" \
        | awk 'length($0) > 0 { blank=0; print; next } blank == 0 { print; blank=1 }')
    # Append single co-author credit if any commit had one
    if git -C "$dir" log origin/main..HEAD --format="%b" | grep -q '^Co-Authored-By:'; then
        coauthor=$(git -C "$dir" log origin/main..HEAD --format="%b" | grep '^Co-Authored-By:' | sed -n 1p)
        mr_body=$(printf '%s\n\n%s' "$mr_body" "$coauthor")
    fi
    if [[ -n "$mr_description_file" ]]; then
        mr_body=$("$workspace_root/scripts/scripts/escape-mr-mentions.py" < "$mr_description_file")
    fi
    # ADR-073: a closing keyword ("close #14") makes GitLab close the issue
    # on merge, before issue-status-sync can derive its status (#70).
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    if [[ "${MR_ALLOW_CLOSING:-}" != "1" ]] && closing=$(issue_closing_reference "$mr_title"$'\n'"$mr_body"); then
        echo "ERROR: MR text would close an issue on merge: '${closing# }'."
        echo "       Refer to the issue without a closing keyword, e.g. '(#14)';"
        echo "       override deliberately with MR_ALLOW_CLOSING=1."
        exit 1
    fi
    # Defence in depth: validate that no bare `@word` survives the
    # escape pass before reaching GitLab. Catches edge cases the
    # escaper misses (e.g. fenced code blocks, mid-paragraph `@` that
    # the markdown parser interprets differently from our walker).
    if ! printf '%s' "$mr_body" \
       | "$workspace_root/scripts/scripts/escape-mr-mentions.py" --check; then
        echo 'ERROR: aborting glab mr create — body has unsafe @-mentions.'
        echo '       (See script output above for the offending tags.)'
        exit 1
    fi
    (
        cd "$dir"
        ARGS=(--yes --target-branch main -R "$p")
        ARGS+=(--title "$mr_title")
        ARGS+=(--description "$mr_body")
        # Branch cleanup is requested per MR, not left to the project default,
        # which is off so that ADR-073 issue/<N> branches survive web merges.
        [[ "$branch" =~ ^issue/[0-9]+$ ]] || ARGS+=(--remove-source-branch)
        # A Draft puts the issue in the board's implementing column and a
        # ready MR in review (ADR-073 Decision 4). Every MR opens as a Draft;
        # without MR_DRAFT=1 the ready queue below decides (private#1179).
        ARGS+=(--draft)
        glab mr create "${ARGS[@]}"
    )

    if [[ "$branch" =~ ^issue/[0-9]+$ ]]; then
        source "{{ justfile_directory() }}/just/issue-lib.sh"
        issue_keep_mr_branch "$p" "$branch"
    fi

    # ── Auto-link Related MRs (E13/E14/E15 fix) ────────────────────
    just gitlab _autolink "{{repo}}"

    if [[ "${MR_DRAFT:-}" != "1" ]]; then
        iid=$(glab api "projects/${p//\//%2F}/merge_requests?state=opened&source_branch=${branch//\//%2F}&per_page=1" \
          | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')")
        python3 "{{justfile_directory()}}/just/mr-ready-queue.py" "$p" "$iid" "{{repo}}"
    fi

# Cross-link every open MR that shares this branch across sibling repos.
# Idempotent: re-running rewrites the auto-generated section instead of
# duplicating it. Set MR_NO_AUTOLINK=1 to skip.
#
# Shared by mr-create (after creating) and mr-update (after rebuilding a
# body, which would otherwise silently delete the section — the links
# vanish exactly when someone fixes a stale title, which is the failure
# this pass exists to prevent).
[private]
[no-cd]
[script]
_autolink repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    workspace_root=$(pwd)
    branch=$(git -C "$dir" branch --show-current)
    if [[ "${MR_NO_AUTOLINK:-0}" == "1" ]]; then
        exit 0
    fi
    self_iid=$(glab api "projects/vauchi%2F${r}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
    if [[ -z "$self_iid" ]]; then
        echo "Note: could not detect new MR IID — skipping auto-link"
        exit 0
    fi
    # Self entry uses the gitlab name (r) as the label so identity is
    # stable regardless of how `dir` was resolved (absolute vs basename).
    mr_registry=("${r}:${r}:${self_iid}")
    _add_sibling_mr() {
        local s_dir="$1"
        [[ ! -e "${s_dir}/.git" ]] && return 0
        local s_branch
        s_branch=$(git -C "$s_dir" branch --show-current 2>/dev/null || true)
        [[ "$s_branch" != "$branch" ]] && return 0
        local s_name s_gl
        s_name=$(basename "$s_dir")
        s_gl=$(_dir_to_gitlab_name "$s_name")
        # Skip self by gitlab name (the authoritative repo identifier)
        [[ "$s_gl" == "$r" ]] && return 0
        local s_iid
        s_iid=$(glab api "projects/vauchi%2F${s_gl}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
        # Sibling has the branch but no MR yet — silently skip. Wrapping
        # in `if/fi` (rather than `[[ … ]] && …`) ensures the function
        # always returns 0; otherwise the implicit non-zero exit
        # propagates under `set -e` and kills the recipe AFTER the MR
        # has already been created (E13/E14/E15-style false-failure).
        if [[ -n "$s_iid" ]]; then
            mr_registry+=("${s_gl}:${s_gl}:${s_iid}")
        fi
        return 0
    }
    # Scan sub-directories
    for sibling_dir in "$workspace_root"/*/; do
        _add_sibling_mr "${sibling_dir%/}"
    done
    # Also include the workspace root itself (it's a git repo too)
    [[ -e "${workspace_root}/.git" ]] && _add_sibling_mr "$workspace_root"
    if [[ ${#mr_registry[@]} -le 1 ]]; then
        exit 0
    fi
    echo ""
    echo "── Auto-linking ${#mr_registry[@]} MRs on branch '${branch}' ──"
    for entry in "${mr_registry[@]}"; do
        IFS=: read -r el egl eiid <<< "$entry"
        cur_desc=$(glab api "projects/vauchi%2F${egl}/merge_requests/${eiid}" 2>/dev/null \
          | python3 -c "import sys,json; print(json.load(sys.stdin).get('description') or '')" 2>/dev/null || true)
        # Strip prior auto-generated section so re-runs are idempotent.
        # Uses HTML-comment markers so the regex cannot accidentally match
        # prose mentioning "Related MRs" inside commit bodies.
        cleaned=$(printf '%s' "$cur_desc" | python3 -c "import sys,re; t=sys.stdin.read(); sys.stdout.write(re.sub(r'\n*<!-- mr-auto-link-start -->.*?<!-- mr-auto-link-end -->', '', t, flags=re.DOTALL).rstrip())")
        others=""
        for other in "${mr_registry[@]}"; do
            IFS=: read -r ol ogl oiid <<< "$other"
            # Compare by gitlab name (egl/ogl) — stable identity per repo
            [[ "$ogl" == "$egl" ]] && continue
            others="${others}- vauchi/${ogl}!${oiid}"$'\n'
        done
        new_desc="${cleaned}"$'\n\n''<!-- mr-auto-link-start -->'$'\n''## Related MRs (auto-linked)'$'\n\n'"${others}"$'\n''<!-- mr-auto-link-end -->'
        if glab api -X PUT "projects/vauchi%2F${egl}/merge_requests/${eiid}" -f "description=${new_desc}" >/dev/null 2>&1; then
            printf "  ✓ %s !%s — linked %d sibling(s)\n" "$egl" "$eiid" "$(( ${#mr_registry[@]} - 1 ))"
        else
            printf "  ✗ %s !%s — link update failed\n" "$egl" "$eiid"
        fi
    done

# Approve a merge request
[no-cd]
[script]
mr-approve id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab mr approve "{{id}}" -R "$p"

# Merge a merge request
[no-cd]
[script]
mr-merge id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab mr merge "{{id}}" --yes -R "$p"

# Merge a merge request when its pipeline succeeds (auto-merge / MWPS).
# Unlike mr-merge (immediate), this queues the merge so you don't babysit the
# pipeline — the intended finisher for the dependent-mrs unblock flow once an
# upstream tier is in and the downstream MR's own pipeline is running/green.
[no-cd]
[script]
mr-merge-when-green id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab mr merge "{{id}}" --auto-merge --yes -R "$p"

# Close a merge request
[no-cd]
[script]
mr-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab mr close "{{id}}" -R "$p"

# Create or update MRs for all repos on the same feature branch
# Idempotent: creates MR if none exists, rebases + force-pushes if one does.
# After all MRs exist, auto-populates Related MRs and marks downstream as Draft.
#
# Usage: just gitlab mr-create-all                    # auto-fill title from commits
#        just gitlab mr-create-all "feat: my feature" # custom title
[no-cd]
[script]
mr-create-all title='':
    just gitlab _check-auth
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
    timer_start

    # ── Dependency graph for Draft detection ──────────────────────────
    # Tier 0 = upstream (no vauchi git deps). If tier 0 has an MR,
    # everything downstream is Draft. Derived from Cargo.toml git deps.
    UPSTREAM_REPOS="core"
    # Repos that depend on core via git (tier 1+)
    DOWNSTREAM_OF_CORE="cli tui relay ohttp-relay linux-gtk e2e"

    created=()
    updated=()
    uptodate=()
    failed=()

    # Collect MR IIDs + labels for the cross-reference pass
    # Format: "label:gl_name:iid" per entry
    mr_registry=()

    _process_repo() {
        local label="$1" dir="$2"
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)

        # Skip repos on main or detached HEAD
        [[ "$branch" == "main" || -z "$branch" ]] && return 0

        # Skip repos with no commits ahead
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        [[ "$ahead" -eq 0 ]] && return 0

        echo ""
        echo "── $label ($branch, $ahead commits) ──"

        gl_name=$(_dir_to_gitlab_name "$label")

        # Check for existing MR
        existing_iid=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
        has_mr=$([[ -n "$existing_iid" ]] && echo "yes" || echo "no")

        # Rebase on origin/main
        git -C "$dir" fetch origin main --quiet 2>/dev/null
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
        rebased=no
        if [[ "$behind" -gt 0 ]]; then
            printf "  ↓ %s commits behind — rebasing...\n" "$behind"
            local rebase_output
            if rebase_output=$(git -C "$dir" rebase origin/main 2>&1); then
                echo "$rebase_output" | sed 's/^/  /'
                rebased=yes
            else
                echo "$rebase_output" | sed 's/^/  /'
                echo "  ✗ CONFLICT — skipping (resolve manually: git -C $dir rebase --continue)"
                git -C "$dir" rebase --abort 2>/dev/null
                failed+=("$label")
                return 0
            fi
        fi

        export SKIP_TESTS=1

        if [[ "$has_mr" == "yes" ]]; then
            # MR exists — force-push if rebased, otherwise up-to-date
            if [[ "$rebased" == "yes" ]]; then
                echo "  MR exists (!${existing_iid}) — force-pushing rebased branch..."
                local push_output
                if push_output=$(git -C "$dir" push --force-with-lease origin "$branch" 2>&1); then
                    echo "$push_output" | sed 's/^/  /'
                    updated+=("$label")
                else
                    echo "$push_output" | sed 's/^/  /'
                    echo "  ✗ Force-push failed — check branch protection or remote state"
                    failed+=("$label")
                    return 0
                fi
            else
                echo "  MR exists (!${existing_iid}), already up to date"
                uptodate+=("$label")
            fi
            mr_registry+=("${label}:${gl_name}:${existing_iid}")
        else
            # No MR — create one via push options
            PUSH_OPTS=(-u origin "$branch")
            PUSH_OPTS+=(-o merge_request.create)
            PUSH_OPTS+=(-o merge_request.target=main)
            # issue/<N> is the ADR-073 claim branch: it must outlive its MRs,
            # and every repo deletes source branches by default.
            keep_branch=false
            if [[ "$branch" =~ ^issue/[0-9]+$ ]]; then
                keep_branch=true
            else
                PUSH_OPTS+=(-o merge_request.remove_source_branch)
            fi

            # quote() required — see mr-update.
            mr_title={{ quote(title) }}
            # Positional module args: a `title=...` form leaks the prefix.
            mr_title="${mr_title#title=}"
            if [[ -z "$mr_title" ]]; then
                mr_title=$(git -C "$dir" log origin/main..HEAD --reverse --format=%s | sed -n 1p)
            fi
            PUSH_OPTS+=(-o "merge_request.title=$mr_title")
            # Build description with @ escaped to prevent GitLab mentions
            local mr_desc
            mr_desc=$(git -C "$dir" log origin/main..HEAD --reverse --format="- %s" \
                | sed 's/@\([a-zA-Z][a-zA-Z0-9_-]*\)/`@\1`/g')
            # Append single co-author credit if any commit had one
            if git -C "$dir" log origin/main..HEAD --format="%b" | grep -q '^Co-Authored-By:'; then
                local coauthor
                coauthor=$(git -C "$dir" log origin/main..HEAD --format="%b" | grep '^Co-Authored-By:' | sed -n 1p)
                mr_desc=$(printf '%s\n\n%s' "$mr_desc" "$coauthor")
            fi
            # ADR-073 / #70: no closing keyword may reach GitLab.
            source "{{ justfile_directory() }}/just/issue-lib.sh"
            if [[ "${MR_ALLOW_CLOSING:-}" != "1" ]] && closing=$(issue_closing_reference "$mr_title"$'\n'"$mr_desc"); then
                echo "  ✗ MR text would close an issue on merge: '${closing# }' (MR_ALLOW_CLOSING=1 overrides)"
                failed+=("$label")
                return
            fi
            PUSH_OPTS+=(-o "merge_request.description=$mr_desc")

            echo "  Pushing and creating MR..."
            local push_mr_output
            if push_mr_output=$(git -C "$dir" push "${PUSH_OPTS[@]}" 2>&1); then
                echo "$push_mr_output" | sed 's/^/  /'
                created+=("$label")
                # Fetch the new MR IID
                new_iid=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
                  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
                [[ -n "$new_iid" ]] && mr_registry+=("${label}:${gl_name}:${new_iid}")
                if [[ "$keep_branch" == true && -n "$new_iid" ]]; then
                    issue_keep_mr_branch "vauchi/${gl_name}" "$branch" || failed+=("$label")
                fi
            else
                echo "$push_mr_output" | sed 's/^/  /'
                echo "  ✗ Push failed — check branch protection or network"
                failed+=("$label")
            fi
        fi
    }
    for_each_repo --no-root _process_repo

    # ── Pass 2: Cross-reference Related MRs + Draft downstream ────────
    if [[ ${#mr_registry[@]} -gt 1 ]]; then
        echo ""
        echo "── Cross-referencing ${#mr_registry[@]} MRs ──"

        # Determine if upstream (core) has an MR — if so, downstream should be Draft
        upstream_has_mr=false
        for entry in "${mr_registry[@]}"; do
            entry_label="${entry%%:*}"
            if echo " $UPSTREAM_REPOS " | grep -q " $entry_label "; then
                upstream_has_mr=true
                break
            fi
        done

        for entry in "${mr_registry[@]}"; do
            IFS=: read -r elabel egl eiid <<< "$entry"

            # Build description: commits + related MRs
            commits=$(git -C "$elabel" log origin/main..HEAD --reverse --format="- %s" 2>/dev/null || true)
            files=$(git -C "$elabel" diff --stat origin/main..HEAD 2>/dev/null | tail -1 | sed 's/^ //' || true)

            # Related MRs = all except self
            other_mrs=""
            for other in "${mr_registry[@]}"; do
                IFS=: read -r ol ogl oiid <<< "$other"
                [[ "$ol" == "$elabel" ]] && continue
                other_mrs="${other_mrs}- vauchi/${ogl}!${oiid}\n"
            done

            # Append single co-author credit if any commit had one
            coauthor_line=""
            if git -C "$elabel" log origin/main..HEAD --format="%b" 2>/dev/null | grep -q '^Co-Authored-By:'; then
                local ca
                ca=$(git -C "$elabel" log origin/main..HEAD --format="%b" 2>/dev/null | grep '^Co-Authored-By:' | sed -n 1p)
                coauthor_line="\n${ca}"
            fi
            desc="## Summary\n\n${commits}\n\n## Related MRs\n\n${other_mrs}\n---\n_${files}_${coauthor_line}"

            # Mark downstream repos as Draft if upstream has an MR
            is_downstream=false
            if $upstream_has_mr && echo " $DOWNSTREAM_OF_CORE " | grep -q " $elabel "; then
                is_downstream=true
            fi

            update_args=(-f "description=${desc}")
            if $is_downstream; then
                # Get current title and prepend Draft: if not already
                current_title=$(glab api "projects/vauchi%2F${egl}/merge_requests/${eiid}" 2>/dev/null \
                  | python3 -c "import sys,json; print(json.load(sys.stdin).get('title',''))" 2>/dev/null || true)
                if [[ -n "$current_title" && "$current_title" != Draft:* ]]; then
                    update_args+=(-f "title=Draft: ${current_title}")
                fi
            fi

            glab api -X PUT "projects/vauchi%2F${egl}/merge_requests/${eiid}" "${update_args[@]}" >/dev/null 2>&1 || true

            if $is_downstream; then
                printf "  ✓ %s !%s — Related MRs + Draft\n" "$elabel" "$eiid"
            else
                printf "  ✓ %s !%s — Related MRs\n" "$elabel" "$eiid"
            fi
        done
    fi

    elapsed=$(timer_elapsed)
    echo ""
    echo "── Summary (${elapsed}s) ──"
    [[ ${#created[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Created  (%d):  %s\n" "${#created[@]}" "${created[*]}"
    [[ ${#updated[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Updated  (%d):  %s\n" "${#updated[@]}" "${updated[*]}"
    [[ ${#uptodate[@]} -gt 0 ]] && printf "  ${DIM}·${NC} Up-to-date (%d): %s\n" "${#uptodate[@]}" "${uptodate[*]}"
    [[ ${#failed[@]}   -gt 0 ]] && printf "  ${RED}✗${NC} Failed   (%d):   %s\n" "${#failed[@]}" "${failed[*]}"
    if [[ ${#mr_registry[@]} -gt 1 ]]; then
        printf "  ${GREEN}✓${NC} Cross-referenced %d MRs\n" "${#mr_registry[@]}"
    fi
    [[ ${#failed[@]}   -gt 0 ]] && exit 1 || true

# ── Pipeline Operations ────────────────────────────────────────────

# Deterministically classify a failed job's trace (no model tokens).
# Prints {category, escalate, signature, fix}. escalate=true → novel
# signature, hand to /ci-fix. Usage: just gitlab ci-classify <repo> <job_id>
[no-cd]
[script]
ci-classify repo job_id:
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    failure_reason=$(glab api "projects/${enc}/jobs/{{job_id}}" | jq -r ".failure_reason // empty")
    glab api "projects/${enc}/jobs/{{job_id}}/trace" \
        | scripts/scripts/classify-ci-failure.sh --failure-reason "$failure_reason"

# The current branch's pipeline as "<id> <source> <status> <url> <tested>":
# <tested> is the branch commit it ran on. A merged-results pipeline runs on
# a merge commit whose second parent is that commit.
# the open MR's head pipeline, else the branch's latest. Not `glab ci
# status --branch`: MR pipelines run on refs/merge-requests/<iid>/merge, and
# on an issue/<N> branch reused across several MRs glab refuses to pick one
# (private#408). Fails when there is none.
[private]
[no-cd]
[script]
_branch-pipeline repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(git -C "$dir" branch --show-current)
    branch_enc=$(printf '%s' "$branch" | jq -sRr @uri)
    pipeline=""
    # The MR list omits head_pipeline; only the single-MR endpoint has it.
    mr=$(glab api "projects/${enc}/merge_requests?source_branch=${branch_enc}&state=opened" \
        | jq -r 'first.iid // empty')
    if [[ -n "$mr" ]]; then
        pipeline=$(glab api "projects/${enc}/merge_requests/${mr}" \
            | jq -r '.head_pipeline // empty
                     | "\(.id) !'"$mr"' \(.status) \(.web_url) \(.sha) \(.ref)"')
    fi
    if [[ -z "$pipeline" ]]; then
        pipeline=$(glab api "projects/${enc}/pipelines?ref=${branch_enc}&per_page=1" \
            | jq -r 'first // empty | "\(.id) branch \(.status) \(.web_url) \(.sha) \(.ref)"')
    fi
    if [[ -z "$pipeline" ]]; then
        echo "no pipeline for ${branch} in ${p}" >&2
        exit 1
    fi
    set -- $pipeline
    tested=$5
    if [[ "$6" =~ ^refs/merge-requests/[0-9]+/merge$ ]]; then
        tested=$(glab api "projects/${enc}/repository/commits/$5" | jq -r '.parent_ids[-1]')
    fi
    echo "$1 $2 $3 $4 $tested"

# Show pipeline status for current branch, with its jobs.
[no-cd]
[script]
pipeline-status repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    pipeline=$(just gitlab _branch-pipeline "{{repo}}")
    set -- $pipeline
    id=$1
    echo "pipeline ${id} (${2}): ${3} ${4}"
    glab api "projects/${enc}/pipelines/${id}/jobs?per_page=100" \
        | jq -r '.[] | "  \(.status)\t\(.name)"'

# List recent pipelines
[no-cd]
[script]
pipeline-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab ci list -R "$p"

# Trigger a new pipeline on a ref (default main). Validate-only unless a
# deploy trigger var is passed, so it is safe to run on protected main.
[no-cd]
[script]
pipeline-run ref='main' repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    # A refused call (403 for a token without the pipeline scope) answers
    # with {"message": ...} and no id — say so instead of a KeyError.
    glab api "projects/${enc}/pipeline" -X POST -f "ref={{ref}}" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(f\"GitLab refused: {d.get('message', d)}\") if 'id' not in d else print(f\"Triggered pipeline {d['id']} on {d['ref']}: {d['status']} — {d['web_url']}\")"

# List jobs in a pipeline. `glab ci list` has no `--pipeline` flag
# (removed upstream) — hit the pipeline jobs API directly instead. Prints the
# numeric job id first (feed it to pipeline-log).
[no-cd]
[script]
pipeline-jobs id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    glab api "projects/${enc}/pipelines/{{id}}/jobs" --paginate \
      | python3 -c "import sys,json; jobs=json.load(sys.stdin); [print(f\"{j['id']:>10} {j['name']:40s} {j['status']:10s} allow_failure={j['allow_failure']}\") for j in jobs]"

# Failed test cases of a pipeline, with their assertion messages, from the
# parsed JUnit report. Parallel xcodebuild logs name a failing test but drop
# its XCTAssert message, and a JUnit file is not fetchable by artifact path
# (404) — the pipeline test_report endpoint is where the message survives.
# Covers every job's JUnit upload, allow_failure jobs (e.g. macOS test:ui)
# included; match the class name against `pipeline-jobs` to tell which.
[no-cd]
[script]
test-report id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    glab api "projects/${enc}/pipelines/{{id}}/test_report" \
      | python3 -c "import sys,json; r=json.load(sys.stdin); failed=[c for s in r.get('test_suites',[]) for c in s.get('test_cases',[]) if c.get('status') in ('failed','error')]; print(f\"{r.get('total_count',0)} tests, {len(failed)} failed\"); [print(f\"{c.get('classname','')}.{c.get('name','')}\n  {(c.get('system_output') or '').strip()}\") for c in failed]"

# List the test classes each job of a pipeline reported (a class missing from
# a job's list is the one that was running when its test process died)
[no-cd]
[script]
test-report-classes id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    glab api "projects/${enc}/pipelines/{{id}}/test_report" \
      | python3 -c "import sys,json; r=json.load(sys.stdin); [print(s.get('name',''), c) for s in r.get('test_suites',[]) for c in sorted({t.get('classname','') for t in s.get('test_cases',[])})]"

# View job log output
[no-cd]
[script]
pipeline-log job_id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab ci trace "{{job_id}}" -R "$p"

# Download a job's artifacts from the latest successful pipeline on a ref
# into <dest> (default: the current directory).
# Usage: just gitlab job-artifacts <repo> <job> [ref] [dest]
[no-cd]
[script]
job-artifacts repo job ref='main' dest='.':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    mkdir -p "{{dest}}"
    glab job artifact "{{ref}}" "{{job}}" -R "$p" --path="{{dest}}/"

# Retry a failed pipeline (all failed jobs). `glab ci retry` takes a JOB
# id, not a pipeline id — passing a pipeline id 404s — so hit the
# pipelines retry API directly.
[no-cd]
[script]
pipeline-retry id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    enc=$(printf '%s' "$p" | sed 's|/|%2F|g')
    # Same refusal shape as pipeline-run: the bot token gets 403 here, so
    # name the refusal rather than crash on the missing id.
    glab api "projects/${enc}/pipelines/{{id}}/retry" -X POST \
      | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(f\"GitLab refused: {d.get('message', d)}\") if 'id' not in d else print(f\"Retried pipeline {d['id']}: {d['status']} — {d['web_url']}\")"

# Cancel a running pipeline
[no-cd]
[script]
pipeline-cancel id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab ci cancel pipeline "{{id}}" -R "$p"

# ── Issue Operations ───────────────────────────────────────────────

# List open issues
[no-cd]
[script]
issue-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab issue list -R "$p"

# List the group's open vulnerabilities (detected or confirmed), one per
# line: id, severity, project, scanner, state, whether the latest scan of
# the default branch still finds it, detected at, title, location.
# Read-only.
[no-cd]
[script]
vulnerabilities group='vauchi':
    just gitlab _check-auth
    set -euo pipefail
    glab api graphql --paginate -f query='
      query($endCursor: String) {
        group(fullPath: "{{ group }}") {
          vulnerabilities(state: [DETECTED, CONFIRMED], first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id severity state reportType title detectedAt resolvedOnDefaultBranch
              project { fullPath }
              location {
                ... on VulnerabilityLocationDependencyScanning { file dependency { version package { name } } }
                ... on VulnerabilityLocationContainerScanning { image dependency { version package { name } } }
                ... on VulnerabilityLocationSast { file startLine }
                ... on VulnerabilityLocationSecretDetection { file startLine }
              }
            }
          }
        }
      }' | jq -r '.data.group.vulnerabilities.nodes[]
        | [(.id | sub(".*/"; "")), .severity, .project.fullPath, .reportType, .state, (if .resolvedOnDefaultBranch then "gone-from-main" else "on-main" end), .detectedAt, .title,
           ((.location.file // .location.image // "")
            + (if .location.dependency then " " + .location.dependency.package.name + "@" + .location.dependency.version else "" end)
            + (if .location.startLine then ":" + (.location.startLine | tostring) else "" end))]
        | @tsv'

# View issue details; extra flags go to glab (e.g. --comments)
[no-cd]
[script]
issue-view id repo='' *flags='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab issue view "{{id}}" -R "$p" {{flags}}

# Create an issue
# Usage: just gitlab issue-create "<title>" [repo] [glab issue create flags...]
[no-cd]
[script]
[positional-arguments]
issue-create title repo='' *args='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    # Positional module args: a `title=...` form leaks the prefix — strip it.
    issue_title="${1#title=}"
    # Positional arguments keep each flag value intact; interpolating the
    # variadic parameter would re-split it on spaces and paste quotes and
    # newlines into this script.
    shift
    [ $# -gt 0 ] && shift
    has_description=false
    for arg in "$@"; do
        case "$arg" in --description|--description=*|-d) has_description=true ;; esac
    done
    if [ "$has_description" = true ]; then
        glab issue create --title "$issue_title" --no-editor --yes -R "$p" "$@"
    else
        # glab prompts for a description when none is given, which fails in a
        # non-interactive session; default one that names the opening session.
        source "{{ justfile_directory() }}/just/slot-lib.sh"
        glab issue create --title "$issue_title" --no-editor --yes -R "$p" \
            --description "Opened by $(slot_claim_tag "{{ justfile_directory() }}") via just gitlab issue-create." "$@"
    fi

# Close an issue
[no-cd]
[script]
issue-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    glab issue close "{{id}}" -R "$p"

# Mark a Draft MR ready: its issue moves from implementing to review on the board (ADR-073).
# One live ready MR per repository, rebased on main (private#1179): behind
# another, it stays Draft, cancels its pipeline and both MRs get a comment.
[no-cd]
[script]
mr-ready id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    python3 "{{justfile_directory()}}/just/mr-ready-queue.py" "$p" "{{id}}" "{{repo}}"

# Kanban board in the terminal: one section per derived status (ADR-073). Pass "all" to list backlog/deferred items
[no-cd]
[script]
board mode='':
    just gitlab _check-auth
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    issue_board "{{mode}}"

# Comment on an issue, signed with this session and slot
[no-cd]
[script]
issue-comment id body repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    # quote() required — see mr-update.
    ISSUE_REPO=$(printf '%s' "$p" | sed 's|/|%2F|g') issue_comment "{{id}}" {{ quote(body) }}

# Reply in the thread of an existing issue comment (note id from its #note_<id> link)
[no-cd]
[script]
issue-comment-respond id note body repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    # quote() required — see mr-update.
    ISSUE_REPO=$(printf '%s' "$p" | sed 's|/|%2F|g') issue_comment_respond "{{id}}" "{{note}}" {{ quote(body) }}

# ── Status & Wait ─────────────────────────────────────────────────

# Show MR status for current branch
[no-cd]
[script]
mr-status repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    p=$(resolve_gitlab_project "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(cd "$dir" && git branch --show-current)
    if [[ "$branch" == "main" ]]; then
        echo "On main branch — no MR to show"
        exit 0
    fi
    # Same lookup as `mr-update`: `glab mr list --json` is not a flag this
    # glab has, and the old `2>/dev/null || echo "[]"` turned that "Unknown
    # flag" into a confident "No MR found" for branches that had one. `-F
    # json` exists but embeds raw control characters from MR descriptions,
    # which jq then rejects — so read the API and parse in python.
    # Same lookup as `mr-update`: `glab mr list --json` is not a flag this
    # glab has, and the old `2>/dev/null || echo "[]"` turned that "Unknown
    # flag" into a confident "No MR found" for branches that had one. `-F
    # json` exists but embeds raw control characters from MR descriptions,
    # which jq then rejects — so read the API and format in python.
    summary=$(glab api "projects/vauchi%2F${r}/merge_requests?state=opened&source_branch=${branch}" \
      | python3 -c "import sys,json; print(''.join('MR !%s: %s\n  State: %s\n  URL:   %s\n' % (m['iid'], m['title'], m['state'], m['web_url']) for m in json.load(sys.stdin)))")
    if [[ -z "${summary//[[:space:]]/}" ]]; then
        echo "No open MR found for branch '$branch' in $p"
        exit 0
    fi
    echo "$summary"
    # Show pipeline status
    echo "Pipeline:"
    just gitlab pipeline-status "{{repo}}" 2>/dev/null || echo "  No pipeline found"

# Wait for the pipeline of the current commit to finish.
# Usage: just gitlab pipeline-wait [repo]
#   Polls every PIPELINE_WAIT_INTERVAL seconds (30). Only a pipeline on the
#   local HEAD counts: right after a push the MR still shows the previous
#   commit's. Gives up when none appears in PIPELINE_WAIT_APPEAR_POLLS polls (20).
[no-cd]
[script]
pipeline-wait repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    p=$(resolve_gitlab_project "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(git -C "$dir" branch --show-current)
    head=$(git -C "$dir" rev-parse HEAD)
    interval="${PIPELINE_WAIT_INTERVAL:-30}"
    appear_polls="${PIPELINE_WAIT_APPEAR_POLLS:-20}"
    echo "Waiting for the pipeline of ${head:0:8} on $branch in $p (every ${interval}s)"
    missing=0
    while true; do
        pipeline=$(just gitlab _branch-pipeline "{{repo}}" 2>/dev/null || true)
        set -- $pipeline
        if [[ $# -lt 5 || "$5" != "$head" ]]; then
            missing=$((missing + 1))
            if [[ "$missing" -ge "$appear_polls" ]]; then
                echo "no pipeline for $branch at ${head:0:8} in $p after $missing polls" >&2
                exit 1
            fi
            echo "  [$(date +%H:%M:%S)] no pipeline for ${head:0:8} yet"
            sleep "$interval"
            continue
        fi
        case "$3" in
            success)
                just gitlab pipeline-status "{{repo}}"
                echo ""
                echo "Pipeline PASSED"
                exit 0
                ;;
            failed|canceled|skipped)
                just gitlab pipeline-status "{{repo}}"
                echo ""
                echo "Pipeline $(printf '%s' "$3" | tr '[:lower:]' '[:upper:]')"
                exit 1
                ;;
            *)
                echo "  [$(date +%H:%M:%S)] pipeline $1 ($2): $3"
                ;;
        esac
        sleep "$interval"
    done
# ── Metrics Operations ────────────────────────────────────────────

# Trigger all metrics pipelines to refresh Grafana dashboard data
# Triggers: coverage, binary-size, design-drift, daily engineering metrics
[no-cd]
[group('metrics')]
metrics-refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    just gitlab _check-auth
    echo "── Metrics Refresh ──"
    echo ""
    # METRICS_REFRESH=true tells CI templates to run coverage + binary-size
    # jobs even on API-triggered pipelines (normally skipped to avoid
    # redundant work on downstream verification triggers)
    echo "  Triggering metrics:daily (scripts)..."
    glab ci run -R vauchi/scripts -b main 2>/dev/null \
      && echo "    ✓ scripts pipeline created" \
      || echo "    ⚠ scripts trigger failed"
    for repo in {{ metrics_coverage_repos }}; do
        echo "  Triggering coverage + binary-size ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    for repo in {{ metrics_binary_drift_repos }}; do
        echo "  Triggering binary-size + design-drift ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    for repo in {{ metrics_drift_only_repos }}; do
        echo "  Triggering design-drift ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    echo ""
    echo "── Triggered 11 pipelines ──"
    echo ""
    echo "Dashboard: https://grafana.vauchi.app/d/vauchi-engineering-metrics/engineering-metrics"
    echo ""
    echo "Metrics populate after pipelines complete (~5-15 min)."
    echo "Run 'just gitlab metrics-status' to check progress."

# Show status of metrics-related CI jobs across repos
[no-cd]
[group('metrics')]
metrics-status:
    #!/usr/bin/env bash
    set -euo pipefail
    just gitlab _check-auth
    printf "%-12s %-12s %-12s %-12s %-12s\n" "REPO" "COVERAGE" "BINARY-SIZE" "DESIGN-DRIFT" "PIPELINE"
    printf "%-12s %-12s %-12s %-12s %-12s\n" "----------" "----------" "----------" "----------" "----------"
    for repo in {{ metrics_all_repos }}; do
        pipeline_status=$(glab api "projects/vauchi%2F${repo}/pipelines?ref=main&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['status'] if d else 'none')" 2>/dev/null || echo "?")
        case "$repo" in
            core)     cov="yes" bs="yes"  dd="-"   ;;
            cli|tui)  cov="yes" bs="yes"  dd="yes"  ;;
            relay)    cov="yes" bs="yes"  dd="-"   ;;
            ohttp-relay) cov="yes" bs="-"  dd="-"   ;;
            linux-gtk) cov="-" bs="yes"  dd="yes"  ;;
            linux-qt|macos|windows|web-demo) cov="-" bs="-" dd="yes" ;;
            *) cov="-" bs="-" dd="-" ;;
        esac
        printf "%-12s %-12s %-12s %-12s %-12s\n" "$repo" "$cov" "$bs" "$dd" "$pipeline_status"
    done
    echo ""
    echo "Dashboard: https://grafana.vauchi.app/d/vauchi-engineering-metrics/engineering-metrics"

# ── Resource Group Operations ─────────────────────────────────────

# Reset a stuck resource group lock (GitLab bug: cancelled pipelines
# can fail to release resource_group locks, leaving jobs stuck in
# waiting_for_resource). Cancels stuck jobs to release the lock.
# Fallback: rename the group suffix in .gitlab-ci.yml (e.g. v2 → v3).
#
# Usage: just gitlab resource-group-reset ios ios-spm-v2
[no-cd]
[script]
resource-group-reset repo key:
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    encoded=$(echo "vauchi/$r" | sed 's|/|%2F|g')

    echo "── Resource group '{{key}}' in vauchi/$r ──"
    echo ""

    # List upcoming (stuck) jobs
    # printf, not echo: sh's echo turns the JSON's escaped \n into raw
    # newlines inside strings, which jq rejects (#483).
    JOBS=$(glab api "projects/${encoded}/resource_groups/{{key}}/upcoming_jobs" 2>/dev/null || echo "[]")
    COUNT=$(printf '%s\n' "$JOBS" | jq 'length')
    echo "Queued/stuck jobs: $COUNT"

    if [[ "$COUNT" == "0" ]]; then
        echo "  No stuck jobs — lock is clean."
        exit 0
    fi

    printf '%s\n' "$JOBS" | jq -r '.[] | "  \(.id): \(.name) [\(.status)]"'
    echo ""

    # Cancel each stuck job to release the lock
    printf '%s\n' "$JOBS" | jq -r '.[].id' | while read -r job_id; do
        printf "  Cancelling job %s..." "$job_id"
        if glab api --method POST "projects/${encoded}/jobs/${job_id}/cancel" >/dev/null 2>&1; then
            echo " done"
        else
            echo " (already finished or cannot cancel)"
        fi
    done

    echo ""
    echo "✓ Reset complete — new pipelines should get a fresh lock."
    echo ""
    echo "If jobs are still stuck, rename the resource_group in .gitlab-ci.yml:"
    echo "  resource_group: {{key}} → {{key}}-v2"

# ── Package Registry ──────────────────────────────────────────────

# Show latest published binding versions across all distribution channels
# Usage: just gitlab published
[no-cd]
[script]
published:
    just gitlab _check-auth
    set -euo pipefail

    # Workspace root: just sets this to the directory containing the justfile
    WS="${JUST_INVOCATION_DIRECTORY:-$(dirname "$(dirname "$0")")}"
    # Fallback: walk up from cwd until we find the top-level justfile
    if [[ ! -f "$WS/justfile" ]]; then
        WS="$(pwd)"
        while [[ "$WS" != "/" && ! -f "$WS/justfile" ]]; do WS="$(dirname "$WS")"; done
    fi

    printf "\n%-22s %-22s %-22s %s\n" "Channel" "Latest" "Previous" "Published"
    printf "%-22s %-22s %-22s %s\n" "─────────────────────" "─────────────────────" "─────────────────────" "──────────────────"

    # Helper: query GitLab package registry (latest 2 by creation date, descending)
    query_packages() {
        local project="$1" label="$2"
        glab api "projects/${project}/packages?per_page=2&sort=desc&order_by=created_at" 2>/dev/null \
        | python3 -c "
    import sys,json
    pkgs=json.load(sys.stdin)[:2]
    label='$label'
    if len(pkgs)>=2: print(f'{label:22s} {pkgs[0][\"version\"]:22s} {pkgs[1][\"version\"]:22s} {pkgs[0][\"created_at\"][:16]}')
    elif len(pkgs)==1: print(f'{label:22s} {pkgs[0][\"version\"]:22s} {\"—\":22s} {pkgs[0][\"created_at\"][:16]}')
    else: print(f'{label:22s} {\"(none)\":22s}')
    " 2>/dev/null || printf "%-22s (query failed)\n" "$label"
    }

    query_packages "vauchi%2Fcore"                     "core (generic)"
    # Note: vauchi-platform-kotlin is archived — Maven AAR now published
    # directly from core. Query kept for visibility of last published version.
    query_packages "vauchi%2Fvauchi-platform-kotlin"    "kotlin (maven, archived)"

    # Swift SPM (uses git tags, not package registry)
    git -C "$WS/vauchi-platform-swift" ls-remote --tags origin 2>/dev/null \
    | sed 's|.*refs/tags/||' | grep -E '^v[0-9]' | sort -V | tail -2 \
    | python3 -c "
    import sys
    tags=[l.strip() for l in sys.stdin if l.strip()]
    if len(tags)>=2: print(f\"{'swift (spm tags)':22s} {tags[1]:22s} {tags[0]:22s}\")
    elif len(tags)==1: print(f\"{'swift (spm tags)':22s} {tags[0]:22s}\")
    else: print(f\"{'swift (spm tags)':22s} {'(none)':22s}\")
    " 2>/dev/null || printf "%-22s (query failed)\n" "swift (spm tags)"

    # Local versions (source vs consumer) — use git show to avoid branch drift
    printf "%-22s %-22s\n" "──────────────────────" "──────────────────────"
    CARGO_VER=$(git -C "$WS/core" show origin/main:Cargo.toml 2>/dev/null | grep '^version' | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "?")
    printf "%-22s %-22s\n" "core (Cargo.toml)" "$CARGO_VER"
    ANDROID_VER=$(git -C "$WS/android" show origin/main:app/build.gradle.kts 2>/dev/null | grep -E 'vauchi-platform:' | grep -v '//' | sed 's/.*vauchi-platform:\(.*\)").*/\1/' | head -1 || echo "?")
    printf "%-22s %-22s\n" "android (consumer)" "$ANDROID_VER"
    # iOS uses SPM git tags directly — consumer version is the swift tag
    IOS_VER=$(git -C "$WS/ios" show origin/main:Vauchi.xcodeproj/project.pbxproj 2>/dev/null | grep -E 'version.*=.*"[0-9]' | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "(uses spm tag)")
    printf "%-22s %-22s\n" "ios (consumer)" "$IOS_VER"
    echo ""

# ── Work item claims (atomic lock via GitLab branch creation) ──
#
# Prevents duplicate work when multiple sessions pick up the same
# work board item. Branch creation is atomic on the server — of two
# workers racing to create the same branch, exactly one succeeds; the
# loser's status code is not pinned here, so any failure is a lost race.
#
# Claims auto-expire after 4 hours (stale claims can be force-claimed).
# The lock repo is _private (vauchi/private on GitLab).
# Refusals are appended to _private/docs/2026-09-25-claim-collisions.md so the
# collision rate is measured, not guessed (ADR-073 revisit input).

_claim_repo := "vauchi%2Fprivate"
_claim_prefix := "claim/"
_claim_expiry_hours := "4"
_claim_log := "_private/docs/2026-09-25-claim-collisions.md"

# Session ID: hash of the harness session id when one exists, because
# hostname + workspace path is identical for parallel sessions in one
# checkout. `just harness codex|kimi` sets VAUCHI_SESSION_ID for those two.
_session_id := `printf '%s' "${VAUCHI_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-$(hostname -s):${CLAUDE_PROJECT_DIR:-$(pwd)}}}" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-12`

# Claim a work item (atomic). Fails if already claimed by another session.
# Idempotent: re-claiming your own item succeeds silently.
# Usage: just gitlab claim "problem-triage"
#        just gitlab claim 764 "<reason>"  (maintainer-authorized takeover of an active claim)
[no-cd]
[positional-arguments]
[script]
claim slug reason='':
    just gitlab _check-auth
    set -euo pipefail
    SLUG="{{ slug }}"
    # An issue number (12 or #12) claims issue #N (ADR-073); a slug is a
    # legacy claim/<slug> branch.
    case "${SLUG#\#}" in
        ''|*[!0-9]*) ;;
        *)
            source "{{ justfile_directory() }}/just/slot-lib.sh"
            source "{{ justfile_directory() }}/just/issue-lib.sh"
            # The reason arrives as "$2", never pasted into this source (#679).
            ISSUE_CLAIM_LOG="{{ _claim_log }}" issue_claim "${SLUG#\#}" "${2:-}"
            exit $?
            ;;
    esac
    BRANCH="{{ _claim_prefix }}${SLUG}"
    REPO="{{ _claim_repo }}"
    EXPIRY_H="{{ _claim_expiry_hours }}"
    SESSION="{{ _session_id }}"

    # Check for existing claim
    EXISTING=$(glab api "projects/${REPO}/repository/branches/${BRANCH//\//%2F}" 2>/dev/null || true)
    if printf '%s\n' "$EXISTING" | jq -e '.name' &>/dev/null; then
        # Branch exists — check owner via commit message
        CLAIM_MSG=$(printf '%s\n' "$EXISTING" | tr -d '\000-\010\013-\037' | jq -r '.commit.message // ""')
        OWNER=$(printf '%s\n' "$CLAIM_MSG" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
        if [[ "$OWNER" == "$SESSION" ]]; then
            echo "✓ Already claimed by this session ($SESSION)"
            exit 0
        fi
        # Check if stale
        COMMITTED=$(printf '%s\n' "$EXISTING" | jq -r '.commit.committed_date')
        COMMIT_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${COMMITTED%%.*}" +%s 2>/dev/null \
            || date -d "${COMMITTED}" +%s 2>/dev/null || echo "0") # portable-shell-ok: BSD -j -f runs first and short-circuits on macOS; -d is the GNU fallback, and `|| echo 0` bounds a mismatch to a claim reading as stale
        NOW=$(date +%s)
        AGE_H=$(( (NOW - COMMIT_EPOCH) / 3600 ))
        if [[ "$AGE_H" -ge "$EXPIRY_H" ]]; then
            echo "⚠ Stale claim (${AGE_H}h old, session:${OWNER:-unknown}) — force-claiming..."
            glab api -X DELETE "projects/${REPO}/repository/branches/${BRANCH//\//%2F}" &>/dev/null || true
        else
            echo "BLOCKED: '$SLUG' claimed by session:${OWNER:-unknown} (${AGE_H}h ago)"
            echo "Wait for release, or force-claim after ${EXPIRY_H}h."
            printf -- '- %s | %s | held-by-other | %sh\n' "$(date -u +%Y-%m-%d)" "$SLUG" "$AGE_H" >> "{{ _claim_log }}"
            exit 1
        fi
    fi

    # Tag before the branch exists, so a claim is never left unstamped
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    TAG=$(slot_claim_tag "{{ justfile_directory() }}")

    # Atomic create — the race is decided here, server-side
    if RESULT=$(glab api -X POST "projects/${REPO}/repository/branches" \
        -f branch="$BRANCH" -f ref="main" 2>&1); then
        # Stamp session and slot via a commit on the claim branch
        jq -n --arg br "$BRANCH" --arg tag "$TAG" --arg slug "$SLUG" '{
            branch: $br,
            commit_message: ("claim: " + $slug + " " + $tag),
            actions: [{action:"create", file_path:".claim", content:($tag + "\n")}]
        }' | glab api -X POST "projects/${REPO}/repository/commits" --input - &>/dev/null || true
        echo "✓ Claimed '$SLUG' ($TAG)"
    else
        if printf '%s\n' "$RESULT" | grep -qi 'already exists'; then
            echo "BLOCKED: '$SLUG' was just claimed by another session (race lost)"
            printf -- '- %s | %s | race-lost | 0h\n' "$(date -u +%Y-%m-%d)" "$SLUG" >> "{{ _claim_log }}"
        else
            echo "ERROR: could not create claim branch for '$SLUG':" >&2
            echo "$RESULT" >&2
        fi
        exit 1
    fi

# Release a work item claim.
# Usage: just gitlab release "problem-triage"
[no-cd]
[script]
release slug:
    just gitlab _check-auth
    set -euo pipefail
    SLUG="{{ slug }}"
    # An issue number (12 or #12) claims issue #N (ADR-073); a slug is a
    # legacy claim/<slug> branch.
    case "${SLUG#\#}" in
        ''|*[!0-9]*) ;;
        *)
            source "{{ justfile_directory() }}/just/slot-lib.sh"
            source "{{ justfile_directory() }}/just/issue-lib.sh"
            ISSUE_CLAIM_LOG="{{ _claim_log }}" issue_release "${SLUG#\#}"
            exit $?
            ;;
    esac
    BRANCH="{{ _claim_prefix }}${SLUG}"
    REPO="{{ _claim_repo }}"
    glab api -X DELETE "projects/${REPO}/repository/branches/${BRANCH//\//%2F}" &>/dev/null \
        && echo "✓ Released '$SLUG'" \
        || echo "  (no active claim for '$SLUG')"

# List all active work item claims.
# Usage: just gitlab claims
[no-cd]
[script]
claims:
    just gitlab _check-auth
    set -euo pipefail
    REPO="{{ _claim_repo }}"
    PREFIX="{{ _claim_prefix }}"
    EXPIRY_H="{{ _claim_expiry_hours }}"
    SESSION="{{ _session_id }}"
    NOW=$(date +%s)

    # Strip control chars before jq (commit messages may contain them)
    CLAIMS=$(glab api "projects/${REPO}/repository/branches?search=claim/" 2>/dev/null \
        | tr -d '\000-\010\013-\037' \
        | jq '[.[] | {name: .name, msg: .commit.message, date: .commit.committed_date}]' 2>/dev/null \
        || echo "[]")
    COUNT=$(printf '%s\n' "$CLAIMS" | jq 'length')
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/issue-lib.sh"
    echo "ISSUE CLAIMS (issue/<N> branches in vauchi/private):"
    ISSUE_CLAIMS=$(issue_claims)
    printf '%s\n' "${ISSUE_CLAIMS:-  (none)}"
    echo ""
    echo "LEGACY CLAIMS (claim/<slug>):"
    if [[ "$COUNT" == "0" ]]; then
        echo "  (none)"
        exit 0
    fi
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    printf "%-25s %-32s %s\n" "ITEM" "SESSION @SLOT" "AGE"
    printf "%-25s %-32s %s\n" "─────────────────────────" "────────────────────────────────" "───"
    printf '%s\n' "$CLAIMS" | jq -c '.[]' | while IFS= read -r b; do
        NAME=$(printf '%s\n' "$b" | jq -r '.name' | sed "s|^${PREFIX}||")
        MSG=$(printf '%s\n' "$b" | jq -r '.msg // ""')
        OWNER=$(printf '%s\n' "$MSG" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
        COMMITTED=$(printf '%s\n' "$b" | jq -r '.date')
        COMMIT_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${COMMITTED%%.*}" +%s 2>/dev/null \
            || date -d "${COMMITTED}" +%s 2>/dev/null || echo "0") # portable-shell-ok: BSD -j -f runs first and short-circuits on macOS; -d is the GNU fallback, and `|| echo 0` bounds a mismatch to a claim reading as stale
        AGE_H=$(( (NOW - COMMIT_EPOCH) / 3600 ))
        STALE=""
        [[ "$AGE_H" -ge "$EXPIRY_H" ]] && STALE=" (STALE)"
        MARKER=""
        [[ "${OWNER:-}" == "$SESSION" ]] && MARKER=" (you)"
        printf "%-25s %-32s %s\n" "$NAME" "$(slot_claim_owner "$MSG")${MARKER}" "${AGE_H}h${STALE}"
    done
