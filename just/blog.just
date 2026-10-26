# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Blog drafts and publishing (vauchi/private#822).
# Drafts stay private in _private/future-blog-posts/; published posts live
# in website/blog/content/ and are edited at https://vauchi.app/blog/admin/.
# Usage: just blog drafts | publish <slug> | test

# Must match SVELTIA_VERSION / SVELTIA_SHA256 in website/Dockerfile.
sveltia_version := "0.237.0"
sveltia_sha256 := "562ff1cda6003b3265a5d5ed429347d4e52b344e5954ef09e8849ec786c5c887"
drafts_port := "8790"

[group('tests')]
test:
    python3 "{{ justfile_directory() }}/tests/test_blog_publish.py" "{{ justfile_directory() }}/just/blog-publish.sh"

# Edit private drafts in the browser at http://127.0.0.1:8790/ (Ctrl-C stops)
drafts:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{ justfile_directory() }}"
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/vauchi/sveltia-{{ sveltia_version }}"
    if [ ! -f "$cache/sveltia-cms.js" ]; then
        mkdir -p "$cache"
        tarball="$cache/cms.tgz"
        status=$(curl -sS -o "$tarball" -w '%{http_code}' \
            "https://registry.npmjs.org/@sveltia/cms/-/cms-{{ sveltia_version }}.tgz") || status=000
        [ "$status" = 200 ] || { echo "ERROR: Sveltia download → HTTP $status" >&2; exit 1; }
        actual=$( (sha256sum "$tarball" 2>/dev/null || shasum -a 256 "$tarball") | cut -d' ' -f1)
        [ "$actual" = "{{ sveltia_sha256 }}" ] || { echo "ERROR: Sveltia tarball sha256 $actual does not match the pin" >&2; rm -f "$tarball"; exit 1; }
        tar -xzf "$tarball" -C "$cache"
        mkdir -p "$cache/chunks"
        cp "$cache/package/dist/sveltia-cms.js" "$cache/"
        cp "$cache"/package/dist/chunks/*.js "$cache/chunks/"
    fi
    site=$(mktemp -d)
    trap 'rm -rf "$site"' EXIT
    cp "$root/_private/future-blog-posts/admin/index.html" "$root/_private/future-blog-posts/admin/config.yml" "$site/"
    ln -s "$cache/sveltia-cms.js" "$site/sveltia-cms.js"
    ln -s "$cache/chunks" "$site/chunks"
    echo "Drafts CMS: http://127.0.0.1:{{ drafts_port }}/  (saves open merge requests in vauchi/private)"
    python3 -m http.server {{ drafts_port }} --bind 127.0.0.1 --directory "$site"

# Move a finished draft to the public blog and open the website MR
publish slug:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{ justfile_directory() }}"
    if [ -n "$(git -C "$root/website" status --porcelain)" ]; then
        echo "ERROR: website has uncommitted changes; commit or 'just git wip' them first" >&2
        exit 1
    fi
    git -C "$root/website" fetch origin main
    git -C "$root/website" switch -c "docs/blog-{{ slug }}" origin/main
    post=$(sh "$root/just/blog-publish.sh" "$root/_private/future-blog-posts" "$root/website/blog/content" "{{ slug }}" "$(date +%Y-%m-%d)")
    title=$(sed -n 's/^title = "\(.*\)"$/\1/p' "$post" | head -n 1)
    git -C "$root/website" add "blog/content/{{ slug }}.md"
    git -C "$root/website" commit -m "docs: publish \"$title\""
    git -C "$root/website" push -u origin "docs/blog-{{ slug }}"
    cd "$root" && just gitlab mr-create website "docs: publish \"$title\""
    echo "Merge it to publish. Then delete the draft in 'just blog drafts'."
