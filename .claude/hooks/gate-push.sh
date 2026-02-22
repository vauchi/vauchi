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

# Only intercept git push commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+(-C\s+\S+\s+)?push'; then
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
[[ "$REPO_NAME" == "desktop" ]] && WORK_DIR="$REPO_DIR/src-tauri"

if [[ -f "$WORK_DIR/Cargo.toml" ]]; then
  cd "$WORK_DIR"

  echo "[gate-push] Checking formatting ($REPO_NAME)..."
  if ! cargo fmt --all -- --check 2>&1; then
    echo "" >&2
    echo "Push blocked: cargo fmt check failed in $REPO_NAME. Run 'cargo fmt --all' to fix." >&2
    exit 2
  fi

  echo "[gate-push] Running clippy ($REPO_NAME)..."
  CLIPPY_EXTRA=()
  case "$REPO_NAME" in
    desktop) CLIPPY_EXTRA=(--no-default-features --features custom-protocol) ;;
  esac

  if ! cargo clippy --all-targets "${CLIPPY_EXTRA[@]}" -- -D warnings 2>&1; then
    echo "" >&2
    echo "Push blocked: clippy found issues in $REPO_NAME. Fix warnings before pushing." >&2
    exit 2
  fi

# ── Swift/iOS repo ──────────────────────────────────────────────────
elif [[ "$REPO_NAME" == "ios" ]]; then
  cd "$REPO_DIR"

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
    echo "[gate-push] Compiling Kotlin ($REPO_NAME)..."
    if ! ./gradlew compileDebugKotlin --quiet 2>&1; then
      echo "" >&2
      echo "Push blocked: Kotlin compilation failed. Fix errors before pushing." >&2
      exit 2
    fi
  fi
fi

# ── Web checks (repos with web source) ─────────────────────────────
# Runs for desktop/ui and other repos that have prettier as a dependency.
UI_DIR=""
if [[ "$REPO_NAME" == "desktop" && -f "$REPO_DIR/ui/package.json" ]]; then
  UI_DIR="$REPO_DIR/ui"
elif [[ -f "$REPO_DIR/package.json" ]] && grep -q '"prettier"' "$REPO_DIR/package.json" 2>/dev/null; then
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
    HTML_FILES=$(find "$UI_DIR" -maxdepth 2 -name '*.html' ! -path '*/node_modules/*' ! -path '*/dist/*' 2>/dev/null)
    if [[ -n "$HTML_FILES" ]]; then
      echo "[gate-push] Running htmlhint ($REPO_NAME)..."
      if ! echo "$HTML_FILES" | xargs "$HTMLHINT" 2>&1; then
        echo "" >&2
        echo "Push blocked: htmlhint found issues in $REPO_NAME. Fix before pushing." >&2
        exit 2
      fi
    fi
  fi
fi

exit 0
