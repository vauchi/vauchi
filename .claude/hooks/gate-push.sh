#!/bin/bash
# PreToolUse hook: intercepts git push commands.
# - Blocks --no-verify (prevents bypassing pre-push hooks)
# - Runs clippy before pushing Rust repos
# - Runs swiftlint before pushing Swift repos
# - Runs Kotlin compilation check before pushing Android repo

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
if echo "$COMMAND" | grep -qoP '(?<=git\s-C\s)\S+'; then
  REL_DIR=$(echo "$COMMAND" | grep -oP '(?<=git\s-C\s)\S+')
  if [[ "$REL_DIR" = /* ]]; then
    REPO_DIR="$REL_DIR"
  else
    REPO_DIR="$CWD/$REL_DIR"
  fi
fi

# Resolve to absolute path
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) || exit 0
REPO_NAME=$(basename "$REPO_DIR")

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
    if ! swiftlint lint --strict --quiet 2>&1; then
      echo "" >&2
      echo "Push blocked: swiftlint found violations. Fix before pushing." >&2
      exit 2
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

exit 0
