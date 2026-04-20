#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SessionStart hook: environment health check for vauchi workspace.
# Silent on success — emits a structured summary only when something
# needs attention (FAIL/FIX/NOTE), or when BOOTSTRAP_VERBOSE=1.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ISSUES=0
VERBOSE="${BOOTSTRAP_VERBOSE:-0}"

# Output buffer — collects all check output, emitted at end with banner.
OUT=""
say() { OUT+="$1"$'\n'; }

# ---------- 0. Self-heal settings.local.json ----------
# Prevents junk accumulation from one-off "Allow" clicks.
# Canonical state: only disabledMcpjsonServers (machine-local preference).
# Any useful permissions belong in settings.json (tracked).
LOCAL_SETTINGS="$PROJECT_DIR/.claude/settings.local.json"
CANONICAL_LOCAL='{
  "disabledMcpjsonServers": [
    "context7"
  ]
}'

if [[ -f "$LOCAL_SETTINGS" ]]; then
  CURRENT_PERMS=$(jq -r '.permissions.allow // [] | length' "$LOCAL_SETTINGS" 2>/dev/null || echo "0")
  if [[ "$CURRENT_PERMS" -gt 0 ]]; then
    echo "$CANONICAL_LOCAL" > "$LOCAL_SETTINGS"
    say "[FIX ] Settings: reset settings.local.json (had $CURRENT_PERMS accumulated permissions)"
  fi
else
  echo "$CANONICAL_LOCAL" > "$LOCAL_SETTINGS"
fi

# ---------- 1. Required CLI tools ----------
TOOLS=(cargo rustfmt clippy-driver node npm just jq glab)
MISSING=()
VERSIONS=()

for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING+=("$tool")
  else
    case "$tool" in
      cargo)          ver=$(cargo --version 2>/dev/null | awk '{print $2}') ;;
      rustfmt)        ver=$(rustfmt --version 2>/dev/null | awk '{print $2}' | cut -d- -f1) ;;
      clippy-driver)  ver=$(clippy-driver --version 2>/dev/null | awk '{print $2}') ;;
      node)           ver=$(node --version 2>/dev/null | tr -d 'v') ;;
      npm)            ver=$(npm --version 2>/dev/null) ;;
      just)           ver=$(just --version 2>/dev/null | awk '{print $2}') ;;
      jq)             ver=$(jq --version 2>/dev/null | tr -d 'jq-') ;;
      glab)           ver=$(glab --version 2>/dev/null | awk '{print $2}') ;;
      *)              ver="?" ;;
    esac
    VERSIONS+=("${tool} ${ver}")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  say "[FAIL] CLI tools: missing: ${MISSING[*]}"
  ISSUES=$((ISSUES + ${#MISSING[@]}))
elif [[ "$VERBOSE" == "1" ]]; then
  say "[PASS] CLI tools: ${VERSIONS[*]}"
fi

# ---------- 2. Expected repos present ----------
# Note: vauchi-platform-kotlin is archived (see CLAUDE.md) — excluded from list.
REPOS=(core cli tui relay ohttp-relay e2e features docs scripts _private locales themes assets website android ios macos windows linux-gtk linux-qt web-demo vauchi-platform-swift drift-detector gitlab-profile markdown-plan)
MISSING_REPOS=()

for repo in "${REPOS[@]}"; do
  if [[ ! -d "$PROJECT_DIR/$repo/.git" ]]; then
    MISSING_REPOS+=("$repo")
  fi
done

PRESENT_COUNT=$(( ${#REPOS[@]} - ${#MISSING_REPOS[@]} ))
if [[ ${#MISSING_REPOS[@]} -gt 0 ]]; then
  say "[FAIL] Repos: ${PRESENT_COUNT}/${#REPOS[@]} present — missing: ${MISSING_REPOS[*]} — run \`just setup\`"
  ISSUES=$((ISSUES + 1))
elif [[ "$VERBOSE" == "1" ]]; then
  say "[PASS] Repos: ${PRESENT_COUNT}/${#REPOS[@]} present"
fi

# ---------- 3. Git state ----------
GIT_ISSUES=()
BRANCH_NOTES=()

for repo in "${REPOS[@]}"; do
  REPO_DIR="$PROJECT_DIR/$repo"
  [[ ! -d "$REPO_DIR/.git" ]] && continue

  # Current branch
  BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [[ "$BRANCH" != "main" ]]; then
    BRANCH_NOTES+=("${repo}/ on ${BRANCH}")
  fi

  # Tracking remote
  REMOTE=$(git -C "$REPO_DIR" config --get "branch.${BRANCH}.remote" 2>/dev/null || echo "none")
  if [[ "$REMOTE" != "origin" && "$REMOTE" != "none" ]]; then
    GIT_ISSUES+=("${repo}/ tracking ${REMOTE} (expected origin)")
  fi

  # Stale lock files (auto-heal if older than 1 hour)
  LOCK_FILE="$REPO_DIR/.git/index.lock"
  if [[ -f "$LOCK_FILE" ]]; then
    if stat -c %Y /dev/null &>/dev/null; then
      LOCK_MTIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")
    else
      LOCK_MTIME=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo "0")
    fi
    LOCK_AGE=$(( $(date +%s) - LOCK_MTIME ))
    if [[ $LOCK_AGE -gt 3600 ]]; then
      rm -f "$LOCK_FILE"
      GIT_ISSUES+=("${repo}/ had stale index.lock (auto-removed, was ${LOCK_AGE}s old)")
    else
      GIT_ISSUES+=("${repo}/ has index.lock (${LOCK_AGE}s old, not yet stale)")
    fi
  fi
done

if [[ ${#GIT_ISSUES[@]} -gt 0 || ${#BRANCH_NOTES[@]} -gt 0 ]]; then
  if [[ ${#BRANCH_NOTES[@]} -gt 0 ]]; then
    say "[NOTE] Git: ${BRANCH_NOTES[*]}"
  fi
  if [[ ${#GIT_ISSUES[@]} -gt 0 ]]; then
    for issue in "${GIT_ISSUES[@]}"; do
      say "[FAIL] Git: ${issue}"
    done
    ISSUES=$((ISSUES + ${#GIT_ISSUES[@]}))
  fi
elif [[ "$VERBOSE" == "1" ]]; then
  say "[PASS] Git: all repos on main, tracking origin"
fi

# ---------- 4. Drift detector ----------
MCP_ISSUES=()

# Check drift-detector is built — auto-fix if missing
if [[ ! -f "$PROJECT_DIR/drift-detector/dist/index.js" ]]; then
  if [[ -f "$PROJECT_DIR/drift-detector/package.json" ]]; then
    say "[FIX ] MCP: drift-detector not built — auto-building..."
    (
      cd "$PROJECT_DIR/drift-detector"
      [[ ! -d node_modules ]] && npm install --silent 2>/dev/null
      ./node_modules/.bin/tsc 2>/dev/null
    )
    if [[ -f "$PROJECT_DIR/drift-detector/dist/index.js" ]]; then
      say "[FIX ] MCP: drift-detector built successfully"
    else
      MCP_ISSUES+=("drift-detector auto-build failed — run \`cd drift-detector && npm install && npx tsc\`")
    fi
  else
    MCP_ISSUES+=("drift-detector/package.json not found — repo may be missing")
  fi
fi

if [[ ${#MCP_ISSUES[@]} -gt 0 ]]; then
  for issue in "${MCP_ISSUES[@]}"; do
    say "[FAIL] MCP: ${issue}"
  done
  ISSUES=$((ISSUES + ${#MCP_ISSUES[@]}))
elif [[ "$VERBOSE" == "1" ]]; then
  say "[PASS] MCP: drift-detector built"
fi

# ---------- 5. GitLab auth ----------
if command -v glab &>/dev/null; then
  GLAB_USER=$(glab auth status 2>&1 | sed -n 's/.*Logged in to .* as \([^ ]*\).*/\1/p' | head -1)
  if [[ -n "$GLAB_USER" ]]; then
    [[ "$VERBOSE" == "1" ]] && say "[PASS] GitLab: authenticated as ${GLAB_USER}"
  else
    say "[FAIL] GitLab: not authenticated — run \`glab auth login\`"
    ISSUES=$((ISSUES + 1))
  fi
fi

# ---------- Emit (silent on success) ----------
if [[ -n "$OUT" || "$VERBOSE" == "1" ]]; then
  echo "=== Vauchi Environment Bootstrap ==="
  printf "%s" "$OUT"
  if [[ $ISSUES -ne 0 ]]; then
    echo "Environment has ${ISSUES} issue(s). See above."
  elif [[ "$VERBOSE" == "1" ]]; then
    echo "Environment ready. 0 issues found."
  fi
fi

exit 0
