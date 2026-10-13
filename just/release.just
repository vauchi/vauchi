# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Show current version and latest tags across tiers
[group('release')]
release-status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Release Status ==="
    echo ""
    VERSION=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml \
      | grep '^version' | sed 's/.*"\(.*\)"/\1/')
    echo "Core Cargo.toml version: ${VERSION}"
    echo ""
    echo "Latest tags (core):"
    echo "  Stable: $(git -C core tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || echo '(none)')"
    echo "  RC:     $(git -C core tag -l 'v*-rc.*' --sort=-v:refname | head -1 || echo '(none)')"
    echo "  Dev:    $(git -C core tag -l 'v*-dev.*' --sort=-v:refname | head -1 || echo '(none)')"

# Show steps to promote RC to stable
[group('release')]
release-promote:
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST_RC=$(git -C core tag -l 'v*-rc.*' --sort=-v:refname | head -1)
    if [ -z "${LATEST_RC}" ]; then
      echo "No RC tags found. Create one first: just release-rc"
      exit 1
    fi
    BASE_VERSION=$(echo "${LATEST_RC}" | sed 's/^v//' | sed 's/-rc\..*//')
    echo "=== Promote RC to Stable ==="
    echo "  Latest RC: ${LATEST_RC}"
    echo "  Stable version: v${BASE_VERSION}"
    echo ""
    echo "Next steps:"
    echo "  1. Ensure core/Cargo.toml [workspace.package] version = \"${BASE_VERSION}\""
    echo "  2. Merge to main"
    echo "  3. auto-tag:version creates v${BASE_VERSION} tag"
    echo "  4. Release pipeline: build → package → publish → trigger"

# Clean up old dev and RC tags (keeps last 5 of each)
[group('release')]
release-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Release Tag Cleanup ==="
    for tier in dev rc; do
      TAGS=$(git -C core tag -l "v*-${tier}.*" --sort=-v:refname)
      COUNT=$(echo "$TAGS" | grep -c . || true)
      if [ "$COUNT" -le 5 ]; then
        echo "${tier}: ${COUNT} tags (keeping all)"
        continue
      fi
      echo "${tier}: ${COUNT} tags — removing oldest $(($COUNT - 5))"
      echo "$TAGS" | tail -n +6 | while read -r tag; do
        echo "  Deleting ${tag}"
        git -C core tag -d "${tag}" 2>/dev/null || true
        git -C core push origin --delete "${tag}" 2>/dev/null || true
      done
    done
    echo "Done: cleanup complete"

# Internal test build (vauchi/private#665): raise the app versions on a
# fresh branch from main and open the MRs. Merging one makes CI tag the
# release and upload it (iOS: TestFlight, Android: Play internal testing).
# --auto-merge sets each MR to merge once its pipeline passes; --dry-run
# stops before pushing.
# Usage: just test-build [ios|android|both] [--auto-merge] [--dry-run]
[group('release')]
[script]
test-build target='both' *flags:
    set -euo pipefail
    auto_merge=false
    dry_run=false
    for flag in {{ flags }}; do
        case "$flag" in
            --auto-merge) auto_merge=true ;;
            --dry-run) dry_run=true ;;
            *) echo "unknown flag: $flag (use --auto-merge or --dry-run)" >&2; exit 2 ;;
        esac
    done
    case "{{ target }}" in
        both) apps="ios android" ;;
        ios|android) apps="{{ target }}" ;;
        *) echo "usage: just test-build [ios|android|both] [--auto-merge] [--dry-run]" >&2; exit 2 ;;
    esac
    root=$(pwd)
    # Check every app first, so a dirty one stops the run before any changes.
    for app in $apps; do
        if [[ -n "$(git -C "$app" status --porcelain)" ]]; then
            echo "$app has uncommitted changes: commit or save them first" >&2
            exit 1
        fi
    done
    for app in $apps; do
        case "$app" in
            android) file=app/build.gradle.kts; name=Android; label=versionCode; store="Google Play internal testing" ;;
            ios) file=project.yml; name=iOS; label=build; store=TestFlight ;;
        esac
        git -C "$app" fetch -q origin main
        git -C "$app" switch -q --detach origin/main
        read -r version build < <(python3 "$root/just/test_build_version.py" "$app" "$app/$file")
        branch="chore/test-build-$version"
        git -C "$app" switch -q -c "$branch"
        if [[ "$app" == ios ]]; then
            (cd "$app" && xcodegen generate >/dev/null)
        fi
        git -C "$app" add -A
        title="chore: $name $version ($label $build) internal test build"
        message="$title"$'\n\n'"On merge, auto-tag creates v$version and CI uploads it to $store."
        if [[ -n "${TEST_BUILD_TRAILER:-}" ]]; then
            message="$message"$'\n\n'"$TEST_BUILD_TRAILER"
        fi
        git -C "$app" commit -q -m "$message"
        echo "$app: $version ($label $build) committed on $branch"
        if $dry_run; then
            continue
        fi
        git -C "$app" push -q -u origin "$branch"
        just gitlab mr-create "$app" "$title"
        if $auto_merge; then
            iid=$(glab api "projects/vauchi%2F$app/merge_requests?state=opened&source_branch=$branch" \
                | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['iid'])")
            glab api -X PUT "projects/vauchi%2F$app/merge_requests/$iid/merge" -f auto_merge=true >/dev/null
            echo "$app: !$iid merges when its pipeline passes"
        fi
    done

# Latest test build per app: its tag, the upload job's state, open test-build MRs.
[group('release')]
[script]
test-build-status:
    set -euo pipefail
    for app in ios android; do
        case "$app" in
            ios) job=deploy:testflight; field='MARKETING_VERSION: "'; file=project.yml ;;
            android) job=deploy:internal; field='versionName = "'; file=app/build.gradle.kts ;;
        esac
        # The tag of main's version: ios also carries an old v1.0.0, so the
        # highest tag is not the latest build.
        git -C "$app" fetch -q origin main
        tag="v$(git -C "$app" show origin/main:"$file" | grep -F "$field" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
        upload=$(glab api "projects/vauchi%2F$app/pipelines?ref=$tag&per_page=1" \
            | python3 -c "import sys, json; d = json.load(sys.stdin); print(d[0]['id'] if d else '')")
        state="no tag pipeline"
        if [[ -n "$upload" ]]; then
            state=$(glab api "projects/vauchi%2F$app/pipelines/$upload/jobs?per_page=100" \
                | python3 -c "import sys, json; print(next((j['status'] for j in json.load(sys.stdin) if j['name'] == '$job'), 'no $job job'))")
        fi
        open=$(glab api "projects/vauchi%2F$app/merge_requests?state=opened&search=internal%20test%20build&per_page=5" \
            | python3 -c "import sys, json; print(' '.join('!' + str(m['iid']) for m in json.load(sys.stdin)) or 'none')")
        echo "$app: latest $tag, $job $state, open test-build MRs: $open"
    done
