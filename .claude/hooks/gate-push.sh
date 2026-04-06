#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: intercepts git push commands.
# - Blocks --no-verify (prevents bypassing pre-push hooks)
# - Runs clippy before pushing Rust repos
# - Runs swiftlint before pushing Swift repos
# - Runs Kotlin compilation check before pushing Android repo
# - Runs prettier, stylelint, htmlhint before pushing web repos

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

# Only intercept commands containing git push — anywhere in the string.
# No start-of-line anchor: catches chained (&&, ||, ;), subshell, pipe,
# and any other construct that embeds a push.
if ! echo "$COMMAND" | grep -qE '\bgit\s+(-C\s+\S+\s+)?push\b'; then
  exit 0
fi

# Skip checks for branch/tag deletions (no code pushed)
if echo "$COMMAND" | grep -qF -- '--delete'; then
  exit 0
fi

# Block --no-verify (prevents bypassing pre-push hooks)
if echo "$COMMAND" | grep -qF -- '--no-verify'; then
  echo "--no-verify is blocked. Pre-push hooks exist to prevent CI failures. Fix the issues instead of bypassing." >&2
  exit 2
fi

# Determine the repo directory
REPO_DIR="$CWD"
if REL_DIR=$(echo "$COMMAND" | sed -n 's/.*git[[:space:]]\+-C[[:space:]]\+\([^[:space:]]\+\).*/\1/p') && [[ -n "$REL_DIR" ]]; then
  true  # REL_DIR already set by sed above
  if [[ "$REL_DIR" = /* ]]; then
    REPO_DIR="$REL_DIR"
  else
    REPO_DIR="$CWD/$REL_DIR"
  fi
fi

# Resolve to absolute path
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) || exit 0
REPO_NAME=$(basename "$REPO_DIR")

# Block pushing WIP checkpoint commits (created by `just git wip`)
HEAD_MSG="$(git -C "$REPO_DIR" log -1 --format=%s 2>/dev/null || true)"
if [[ "$HEAD_MSG" == wip:* ]]; then
  echo "Push blocked: HEAD is a WIP checkpoint commit ($HEAD_MSG). Run 'just git wip-undo' first." >&2
  exit 2
fi

# Block direct pushes to main — all repos must use MRs.
# GitLab Owner role bypasses branch protection; this hook enforces it locally.
# Exemption: --tags (tag pushes don't modify the branch).
if ! echo "$COMMAND" | grep -qF -- '--tags'; then
  CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || true)
  PUSH_TO_MAIN=false

  # Case 1: on main and pushing without an explicit non-main branch.
  # Strip shell redirects/pipes before checking for a refspec — prevents
  # "2>&1", "| tail", etc. from being mistaken for branch names.
  if [[ "$CURRENT_BRANCH" == "main" ]]; then
    # Extract just the git push portion (before any redirect/pipe/semicolon)
    PUSH_ARGS=$(echo "$COMMAND" | sed 's/[;|&].*//' | sed 's/[0-9]*>&[0-9]*//')
    # Check if a non-main branch is explicitly named after the remote
    if ! echo "$PUSH_ARGS" | grep -qE 'push\s+\S+\s+[a-zA-Z]'; then
      PUSH_TO_MAIN=true
    fi
  fi

  # Case 2: explicit push to main (e.g. "git push origin main", "git push origin HEAD:main")
  if echo "$COMMAND" | grep -qE 'push\s+\S+\s+(.*:)?main(\s|$)'; then
    PUSH_TO_MAIN=true
  fi

  if [[ "$PUSH_TO_MAIN" == "true" ]]; then
    echo "" >&2
    echo "Push to main blocked in $REPO_NAME. Use a branch + MR:" >&2
    echo "  1. git -C $REPO_NAME checkout -b feature/<topic>" >&2
    echo "  2. ... make changes ..." >&2
    echo "  3. git -C $REPO_NAME push -u origin feature/<topic>" >&2
    echo "  4. /create-mr" >&2
    exit 2
  fi
fi

# ── TDD stamp check ──────────────────────────────────────────────────
# If `just check` already passed for this commit, skip all gate checks.
STAMP_SH="$REPO_DIR/../scripts/scripts/stamp.sh"
if [[ -f "$STAMP_SH" ]]; then
  source "$STAMP_SH"
  _GATE_STAMP_REPO=$(stamp_repo_from_dir "$REPO_NAME" 2>/dev/null) || _GATE_STAMP_REPO=""
  if [[ -n "$_GATE_STAMP_REPO" ]] && stamp_valid "$_GATE_STAMP_REPO"; then
    echo "[gate-push] Stamp valid — skipping checks ($REPO_NAME)"
    exit 0
  fi
fi

# Find a Node tool binary by walking up from a directory to the nearest node_modules/.bin.
find_node_bin() {
  local tool="$1" dir="$2"
  while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/node_modules/.bin/$tool" ]]; then
      echo "$dir/node_modules/.bin/$tool"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  if command -v "$tool" &>/dev/null; then
    command -v "$tool"
    return 0
  fi
  return 1
}

# ── Rust repos ──────────────────────────────────────────────────────
WORK_DIR="$REPO_DIR"

if [[ -f "$WORK_DIR/Cargo.toml" ]]; then
  cd "$WORK_DIR"

  # Note: this hook runs as a Claude Code PreToolUse hook, not via just.
  # It uses raw cargo commands because just recipes may not be available in this context.
  # The git pre-push hook (scripts/hooks/pre-push) uses the same raw commands for the same reason.
  # For interactive use, always prefer: just fmt <repo>, just lint <repo>, just check <repo>.

  echo "[gate-push] Checking formatting ($REPO_NAME)..."
  if ! cargo fmt --all -- --check 2>&1; then
    echo "" >&2
    echo "Push blocked: format check failed in $REPO_NAME. Run 'just fmt $REPO_NAME' to fix." >&2
    exit 2
  fi

  echo "[gate-push] Running clippy ($REPO_NAME)..."
  CLIPPY_EXTRA=()

  if ! cargo clippy --all-targets "${CLIPPY_EXTRA[@]}" -- -D warnings 2>&1; then
    echo "" >&2
    echo "Push blocked: clippy found issues in $REPO_NAME. Run 'just fix $REPO_NAME' to auto-fix." >&2
    exit 2
  fi

  # Write dedup marker so pre-push hook can skip fmt+clippy
  _DEDUP_FILE="/tmp/.vauchi-gate-${REPO_NAME}-$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo none)"
  touch "$_DEDUP_FILE" 2>/dev/null || true

# ── Swift/iOS repo ──────────────────────────────────────────────────
elif [[ "$REPO_NAME" == "ios" ]]; then
  cd "$REPO_DIR"

  if command -v xcodegen &>/dev/null; then
    echo "[gate-push] Regenerating Xcode project ($REPO_NAME)..."
    xcodegen generate 2>&1
    if ! git diff --quiet Vauchi.xcodeproj/; then
      echo "" >&2
      echo "Push blocked: Xcode project is out of date. Run 'xcodegen generate' and commit." >&2
      exit 2
    fi
  fi

  if command -v swiftformat &>/dev/null; then
    echo "[gate-push] Checking Swift formatting ($REPO_NAME)..."
    if ! swiftformat --lint . 2>&1; then
      echo "" >&2
      echo "Push blocked: swiftformat check failed. Run 'swiftformat .' to fix." >&2
      exit 2
    fi
  fi

  if command -v swiftlint &>/dev/null; then
    echo "[gate-push] Running SwiftLint ($REPO_NAME)..."
    # Advisory only: iOS has many pre-existing violations. CI enforces the
    # full lint check; the pre-push hook just reports a summary.
    SWIFTLINT_ERRORS=$(swiftlint lint --quiet 2>&1 | grep -c ": error:" || true)
    if [[ "$SWIFTLINT_ERRORS" -gt 0 ]]; then
      echo "  SwiftLint: $SWIFTLINT_ERRORS issues (advisory, CI enforces)"
    else
      echo "  SwiftLint OK"
    fi
  fi

# ── Android/Kotlin repo ────────────────────────────────────────────
elif [[ "$REPO_NAME" == "android" ]]; then
  cd "$REPO_DIR"

  if [[ -x "$REPO_DIR/gradlew" ]]; then
    # Use -PlocalBindings when local bindings are present (new types not yet in Maven AAR)
    GRADLE_ARGS=""
    if [[ -d "$REPO_DIR/app/src/local-bindings/kotlin/uniffi" ]]; then
      GRADLE_ARGS="-PlocalBindings"
      echo "[gate-push] Local bindings detected, using -PlocalBindings"
    fi
    echo "[gate-push] Compiling Kotlin ($REPO_NAME)..."
    if ! ./gradlew compileDebugKotlin $GRADLE_ARGS --quiet 2>&1; then
      echo "" >&2
      echo "Push blocked: Kotlin compilation failed. Fix errors before pushing." >&2
      exit 2
    fi
  fi
fi

# ── Web checks (repos with web source) ─────────────────────────────
UI_DIR=""
if [[ -f "$REPO_DIR/package.json" ]] && grep -q '"prettier"' "$REPO_DIR/package.json" 2>/dev/null; then
  UI_DIR="$REPO_DIR"
fi

if [[ -n "$UI_DIR" ]]; then
  # Prettier check
  PRETTIER=$(find_node_bin prettier "$UI_DIR")
  if [[ -n "$PRETTIER" ]]; then
    echo "[gate-push] Checking web formatting ($REPO_NAME)..."
    if ! "$PRETTIER" --check "$UI_DIR/src" 2>&1; then
      echo "" >&2
      echo "Push blocked: prettier check failed in $REPO_NAME. Run 'prettier --write src/' to fix." >&2
      exit 2
    fi
  fi

  # Stylelint check
  STYLELINT=$(find_node_bin stylelint "$UI_DIR")
  if [[ -n "$STYLELINT" ]]; then
    CSS_FILES=$(find "$UI_DIR/src" -name '*.css' -o -name '*.scss' 2>/dev/null)
    if [[ -n "$CSS_FILES" ]]; then
      echo "[gate-push] Running stylelint ($REPO_NAME)..."
      if ! "$STYLELINT" "$UI_DIR/src/**/*.css" "$UI_DIR/src/**/*.scss" 2>&1; then
        echo "" >&2
        echo "Push blocked: stylelint found issues in $REPO_NAME. Fix before pushing." >&2
        exit 2
      fi
    fi
  fi

  # HTMLHint check
  HTMLHINT=$(find_node_bin htmlhint "$UI_DIR")
  if [[ -n "$HTMLHINT" ]]; then
    HTML_FILES=$(find "$UI_DIR" -maxdepth 2 -name '*.html' ! -path '*/node_modules/*' ! -path '*/dist/*' ! -path '*/playwright-report/*' ! -path '*/test-results/*' 2>/dev/null)
    if [[ -n "$HTML_FILES" ]]; then
      # Build array to avoid xargs empty-input pitfall
      _HTML_ARGS=()
      while IFS= read -r f; do
        [[ -n "$f" ]] && _HTML_ARGS+=("$f")
      done <<< "$HTML_FILES"

      if [[ ${#_HTML_ARGS[@]} -gt 0 ]]; then
        echo "[gate-push] Running htmlhint ($REPO_NAME)..."
        if ! "$HTMLHINT" "${_HTML_ARGS[@]}" 2>&1; then
          echo "" >&2
          echo "Push blocked: htmlhint found issues in $REPO_NAME. Fix before pushing." >&2
          exit 2
        fi
      fi
    fi
  fi
fi

# ── Markdown linting (all repos) ──────────────────────────────────
if command -v markdownlint &>/dev/null; then
  # Lint only .md files changed on this branch vs origin/main
  MD_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  if [[ -n "$MD_BASE" ]]; then
    MD_FILES=$(git -C "$REPO_DIR" diff --name-only "$MD_BASE"...HEAD -- '*.md' 2>/dev/null | grep -v '^$' || true)
  else
    # No merge-base (e.g. new repo) — lint all .md files
    MD_FILES=$(git -C "$REPO_DIR" ls-files '*.md' 2>/dev/null || true)
  fi

  if [[ -n "$MD_FILES" ]]; then
    # Workspace root (parent of sub-repos)
    WS_ROOT="$REPO_DIR/.."

    # Resolve config: repo-local > _private > workspace root
    MD_CONFIG=""
    if [[ -f "$REPO_DIR/.markdownlint.json" ]]; then
      MD_CONFIG="$REPO_DIR/.markdownlint.json"
    elif [[ -f "$REPO_DIR/.markdownlint.jsonc" ]]; then
      MD_CONFIG="$REPO_DIR/.markdownlint.jsonc"
    elif [[ -f "$WS_ROOT/_private/.markdownlint.json" ]]; then
      MD_CONFIG="$WS_ROOT/_private/.markdownlint.json"
    elif [[ -f "$WS_ROOT/.markdownlint.json" ]]; then
      MD_CONFIG="$WS_ROOT/.markdownlint.json"
    fi

    MD_ARGS=()
    if [[ -n "$MD_CONFIG" ]]; then
      MD_ARGS+=(-c "$MD_CONFIG")
    fi

    # Use custom line-length rule if available (backtick-path exemption)
    CUSTOM_RULE="$WS_ROOT/_private/scripts/markdownlint-rule-line-length.js"
    if [[ -f "$CUSTOM_RULE" ]]; then
      MD_ARGS+=(-r "$CUSTOM_RULE")
    fi

    # Build array to avoid xargs empty-input pitfall
    _MD_FILE_ARGS=()
    while IFS= read -r f; do
      [[ -n "$f" ]] && _MD_FILE_ARGS+=("$f")
    done <<< "$MD_FILES"

    if [[ ${#_MD_FILE_ARGS[@]} -gt 0 ]]; then
      echo "[gate-push] Linting ${#_MD_FILE_ARGS[@]} changed .md file(s) ($REPO_NAME)..."
      # Run from repo dir so paths resolve correctly
      if ! (cd "$REPO_DIR" && markdownlint "${MD_ARGS[@]}" "${_MD_FILE_ARGS[@]}") 2>&1; then
        echo "" >&2
        echo "Push blocked: markdownlint found issues in $REPO_NAME. Fix before pushing." >&2
        exit 2
      fi
    fi
  fi
fi

# ── REUSE compliance (all repos) ──────────────────────────────────
if command -v reuse &>/dev/null; then
  # Only check if changed files include ones that need SPDX headers
  REUSE_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  CHANGED_FILES=""
  if [[ -n "$REUSE_BASE" ]]; then
    CHANGED_FILES=$(git -C "$REPO_DIR" diff --name-only "$REUSE_BASE"...HEAD 2>/dev/null | grep -v '^$' || true)
  fi

  if [[ -n "$CHANGED_FILES" ]]; then
    echo "[gate-push] Checking REUSE compliance ($REPO_NAME)..."
    if ! (cd "$REPO_DIR" && reuse lint --quiet) 2>&1; then
      echo "" >&2
      echo "Push blocked: REUSE compliance check failed in $REPO_NAME. Add SPDX headers." >&2
      exit 2
    fi
  fi
fi

# ── Typos spellcheck (all repos) ─────────────────────────────────
if command -v typos &>/dev/null; then
  TYPOS_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  if [[ -n "$TYPOS_BASE" ]]; then
    TYPOS_FILES=$(git -C "$REPO_DIR" diff --diff-filter=d --name-only "$TYPOS_BASE"...HEAD 2>/dev/null | grep -v '^$' || true)
  else
    TYPOS_FILES=""
  fi

  if [[ -n "$TYPOS_FILES" ]]; then
    # Workspace root for fallback config
    WS_ROOT="$REPO_DIR/.."

    # Resolve config: repo-local > workspace root
    TYPOS_ARGS=()
    if [[ -f "$REPO_DIR/_typos.toml" ]]; then
      TYPOS_ARGS+=(-c "$REPO_DIR/_typos.toml")
    elif [[ -f "$WS_ROOT/_typos.toml" ]]; then
      TYPOS_ARGS+=(-c "$WS_ROOT/_typos.toml")
    fi

    TYPOS_COUNT=$(echo "$TYPOS_FILES" | wc -l | tr -d ' ')
    echo "[gate-push] Spellchecking $TYPOS_COUNT changed file(s) ($REPO_NAME)..."

    # Build file list as array to avoid xargs empty-input pitfall
    TYPOS_FILE_ARGS=()
    while IFS= read -r f; do
      [[ -n "$f" ]] && TYPOS_FILE_ARGS+=("$f")
    done <<< "$TYPOS_FILES"

    if [[ ${#TYPOS_FILE_ARGS[@]} -gt 0 ]]; then
      if ! (cd "$REPO_DIR" && typos "${TYPOS_ARGS[@]}" "${TYPOS_FILE_ARGS[@]}") 2>&1; then
        echo "" >&2
        echo "Push blocked: typos found spelling issues in $REPO_NAME. Fix before pushing." >&2
        exit 2
      fi
    fi
  fi
fi

# ── Doc naming convention (repos with doc-naming CI) ─────────────
# Applies to: _private, features, scripts (repos that include lint-docs.yml)
DOC_NAMING_REPOS="features:_private:scripts"
if echo ":$DOC_NAMING_REPOS:" | grep -q ":$REPO_NAME:"; then
  DN_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  if [[ -n "$DN_BASE" ]]; then
    DN_FILES=$(git -C "$REPO_DIR" diff --name-only "$DN_BASE"...HEAD -- '*.md' 2>/dev/null | grep -v '^$' || true)
  fi

  if [[ -n "${DN_FILES:-}" ]]; then
    DN_ERRORS=0
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      filename=$(basename "$file")
      dirname=$(dirname "$file")

      # Skip well-known filenames
      case "$filename" in
        README.md|CLAUDE.md|CONTRIBUTING.md|roadmap.md|PRINCIPLES.md|VISIBILITY_POLICY.md|INDEX.md) continue ;;
        assumptions.md|master-plan.plan.md|work-board.md) continue ;;
        STRUCTURE.md|ARCHITECTURE.md|SECURITY.md|CHECKLIST.md) continue ;;
        investigation.md|implementation-plan.md|retrospective.md|post-mortem.md|rejected-solutions.md|design.md|plan.md) continue ;;
        *-audit.md|*-report.md|*-checklist.md|*-analysis.md) continue ;;
      esac

      # Skip .plan.md task DAG files
      if echo "$filename" | grep -qE '\.plan\.md$'; then continue; fi

      # Skip directories where date prefix doesn't apply
      if echo "$dirname" | grep -qE "(diagrams|ideas|strategy|infra|knowledge|audit-review-frameworks|decisions|guides|reference|testing|admin-guides|components)"; then continue; fi

      # Skip root level files
      if [[ "$dirname" == "." ]]; then continue; fi

      # Check for date prefix (YYYY-MM-DD-)
      if ! echo "$filename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
        echo "ERROR: $file does not follow YYYY-MM-DD-name.md convention"
        DN_ERRORS=$((DN_ERRORS + 1))
      fi
    done <<< "$DN_FILES"

    if [[ "$DN_ERRORS" -gt 0 ]]; then
      echo "" >&2
      echo "Push blocked: $DN_ERRORS file(s) don't follow YYYY-MM-DD-name.md naming in $REPO_NAME." >&2
      exit 2
    fi
  fi
fi

# ── Zero-assertion test scanner (Rust repos) ─────────────────────
if [[ -f "$REPO_DIR/Cargo.toml" ]]; then
  ZA_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  ZA_RS_CHANGED=""
  if [[ -n "$ZA_BASE" ]]; then
    ZA_RS_CHANGED=$(git -C "$REPO_DIR" diff --name-only "$ZA_BASE"...HEAD -- '*.rs' 2>/dev/null | grep -v '^$' || true)
  fi

  if [[ -n "$ZA_RS_CHANGED" ]]; then
    WS_ROOT="$REPO_DIR/.."
    ZA_SCRIPT="$WS_ROOT/scripts/scripts/check-zero-assertions.sh"
    if [[ -x "$ZA_SCRIPT" ]]; then
      # Find test directories in the repo
      ZA_DIRS=""
      for d in "$REPO_DIR/src" "$REPO_DIR/tests"; do
        [[ -d "$d" ]] && ZA_DIRS="$ZA_DIRS $d"
      done
      # Workspace member directories
      for d in "$REPO_DIR"/*/src "$REPO_DIR"/*/tests; do
        [[ -d "$d" ]] && ZA_DIRS="$ZA_DIRS $d"
      done

      if [[ -n "$ZA_DIRS" ]]; then
        echo "[gate-push] Scanning for zero-assertion tests ($REPO_NAME)..."
        if ! "$ZA_SCRIPT" $ZA_DIRS 2>&1; then
          echo "" >&2
          echo "Push blocked: zero-assertion tests found in $REPO_NAME. Add assertions or suppress." >&2
          exit 2
        fi
      fi
    fi
  fi
fi

# ── Gherkin syntax validation (features repo) ────────────────────
if [[ "$REPO_NAME" == "features" ]]; then
  GH_BASE=$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null || echo "")
  GH_FILES=""
  if [[ -n "$GH_BASE" ]]; then
    GH_FILES=$(git -C "$REPO_DIR" diff --name-only "$GH_BASE"...HEAD -- '*.feature' 2>/dev/null | grep -v '^$' || true)
  fi

  if [[ -n "$GH_FILES" ]]; then
    # gherkin-utils: check node_modules, global, or npx fallback
    GHERKIN_BIN=""
    if [[ -x "$REPO_DIR/node_modules/.bin/gherkin-utils" ]]; then
      GHERKIN_BIN="$REPO_DIR/node_modules/.bin/gherkin-utils"
    elif command -v gherkin-utils &>/dev/null; then
      GHERKIN_BIN="gherkin-utils"
    elif command -v npx &>/dev/null; then
      GHERKIN_BIN="npx --yes @cucumber/gherkin-utils"
    fi

    if [[ -n "$GHERKIN_BIN" ]]; then
      echo "[gate-push] Validating $(echo "$GH_FILES" | wc -l | tr -d ' ') changed .feature file(s) ($REPO_NAME)..."
      GH_ERRORS=0
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if ! (cd "$REPO_DIR" && $GHERKIN_BIN format "$file" > /dev/null 2>&1); then
          echo "ERROR: Invalid Gherkin syntax in $file"
          GH_ERRORS=$((GH_ERRORS + 1))
        fi
      done <<< "$GH_FILES"

      if [[ "$GH_ERRORS" -gt 0 ]]; then
        echo "" >&2
        echo "Push blocked: $GH_ERRORS file(s) with Gherkin syntax errors in $REPO_NAME." >&2
        exit 2
      fi
    fi
  fi
fi

# ── ROADMAP.md guard (killed per F2 — master plan is SSOT) ────────
if [[ -f "$WORKSPACE_ROOT/ROADMAP.md" ]]; then
  echo "" >&2
  echo "Push blocked: ROADMAP.md exists at repo root." >&2
  echo "master-plan.plan.md is the single source of truth." >&2
  echo "Delete ROADMAP.md: rm ROADMAP.md" >&2
  exit 2
fi

exit 0
