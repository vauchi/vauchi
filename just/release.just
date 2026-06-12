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
