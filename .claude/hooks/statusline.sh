#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Claude Code status line — Catppuccin Mocha palette
#
# Layout:
#   [⚠ DRIFT] [⎇ worktree] directory  branch  [problem→]next-action
#   [⚠ STALE|→ push|✓ clean]  [Nt Nf Nr]  commit-age  model ctx
#   ctx%  +lines -lines  CHF cost
#
# Performance budget: ~36ms total (JSON: 0ms, git: ~30ms, file: ~1ms)

input=$(cat)

# === JSON fields (free, no subprocess) ===
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
model_id=$(echo "$input" | jq -r '.model.id // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
worktree_name=$(echo "$input" | jq -r '.worktree.name // empty')

# === Git fields (~30ms total) ===
git_dir="${project_dir:-$cwd}"
branch=$(git -C "$git_dir" branch --show-current 2>/dev/null)
last_commit=$(git -C "$git_dir" log -1 --format='%s:%ct' 2>/dev/null)

# Uncommitted changes (for session nudges, ~10ms)
dirty_count=$(git -C "$git_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Unpushed commits (for session nudges, ~5ms)
unpushed=0
if [ -n "$branch" ] && [ "$branch" != "main" ]; then
  unpushed=$(git -C "$git_dir" rev-list "@{u}..HEAD" --count 2>/dev/null || echo "0")
fi

# TDD discipline ratio: count commit types on branch since main (~15ms)
tdd_tests=0; tdd_feats=0; tdd_refactors=0; tdd_tidies=0
if [ -n "$branch" ] && [ "$branch" != "main" ]; then
  while IFS= read -r msg; do
    case "$msg" in
      test:*|test\(*) tdd_tests=$((tdd_tests + 1)) ;;
      feat:*|feat\(*|fix:*|fix\(*) tdd_feats=$((tdd_feats + 1)) ;;
      refactor:*|refactor\(*) tdd_refactors=$((tdd_refactors + 1)) ;;
      tidy:*|tidy\(*) tdd_tidies=$((tdd_tidies + 1)) ;;
    esac
  done < <(git -C "$git_dir" log --oneline --format='%s' main..HEAD 2>/dev/null)
fi

# === Work context file (~1ms) ===
workcontext_file="${project_dir:-.}/.claude/.workcontext"
problem_phase=""
problem_name=""
if [ -f "$workcontext_file" ]; then
  problem_phase=$(jq -r '.phase // empty' "$workcontext_file" 2>/dev/null)
  problem_name=$(jq -r '.problem // empty' "$workcontext_file" 2>/dev/null)
fi

# === Derived values ===

# Truncate cwd: show last 3 path components
short_dir=""
if [ -n "$cwd" ]; then
  short_dir=$(echo "$cwd" | awk -F'/' '{
    n = NF
    if (n <= 3) { print $0 }
    else { print "…/" $(n-2) "/" $(n-1) "/" $n }
  }')
fi

# Drift detection: CWD ≠ project root
drifted=""
if [ -n "$project_dir" ] && [ -n "$cwd" ] && [ "$cwd" != "$project_dir" ]; then
  drifted="1"
fi

# Context window size from model_id (e.g. "claude-opus-4-6[1m]" → "1M")
ctx_size=""
if [[ "$model_id" =~ \[([0-9]+[km])\] ]]; then
  ctx_size=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
fi

# TDD next-action from last commit subject prefix
tdd_next=""
tdd_next_color=""
if [ -n "$last_commit" ]; then
  subject="${last_commit%%:*}"
  case "$subject" in
    tidy:*|tidy\(*)       tdd_next="test" ;;   # after tidy → write failing test
    test:*|test\(*)       tdd_next="impl" ;;   # after test → make it pass
    feat:*|feat\(*|fix:*|fix\(*) tdd_next="tidy" ;;  # after feat/fix → refactor or new cycle
    refactor:*|refactor\(*) tdd_next="test" ;;   # after refactor → new cycle
    docs:*|chore:*)       tdd_next="test" ;;   # back to TDD
  esac
fi

# Combined next-action: problem phase + TDD
# When implementing, TDD indicator takes over; otherwise show problem next-action
next_action=""
next_color=""
if [ -n "$problem_phase" ]; then
  case "$problem_phase" in
    intake)        next_action="investigate" ;;
    investigating) next_action="plan" ;;
    planning)      next_action="implement" ;;
    implementing)  next_action="$tdd_next" ;;  # defer to TDD
    testing)       next_action="close" ;;
  esac
fi
# If no problem context, use TDD directly
if [ -z "$next_action" ] && [ -n "$tdd_next" ]; then
  next_action="$tdd_next"
fi
# Branch-derived fallback when no commit prefix match
if [ -z "$next_action" ] && [ -n "$branch" ]; then
  case "$branch" in
    main) next_action="branch" ;;
    investigation/*) next_action="document" ;;
  esac
fi

# Time since last commit
commit_age=""
elapsed=0
if [ -n "$last_commit" ]; then
  commit_ts="${last_commit##*:}"
  now=$(date +%s)
  if [ -n "$commit_ts" ] && [ "$commit_ts" -gt 0 ] 2>/dev/null; then
    elapsed=$(( now - commit_ts ))
    if [ "$elapsed" -lt 60 ]; then
      commit_age="${elapsed}s"
    elif [ "$elapsed" -lt 3600 ]; then
      commit_age="$(( elapsed / 60 ))m"
    else
      commit_age="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
    fi
  fi
fi

# Session nudge: what needs attention?
session_nudge=""
if [ "$dirty_count" -gt 0 ] && [ "$elapsed" -gt 1800 ]; then
  session_nudge="STALE"      # uncommitted changes + >30min = forgot to commit
elif [ "$dirty_count" -gt 0 ]; then
  session_nudge="dirty"      # uncommitted but recent — working
elif [ "$unpushed" -gt 0 ] && [ "$elapsed" -gt 3600 ]; then
  session_nudge="push"       # unpushed commits + >1hr
elif [ "$dirty_count" -eq 0 ] && [ "$unpushed" -eq 0 ] && [ -n "$branch" ]; then
  session_nudge="clean"      # everything committed + pushed
fi

# Cost: USD → CHF (approximate)
cost_chf=""
if [ -n "$cost_usd" ] && [ "$cost_usd" != "0" ]; then
  cost_chf=$(echo "$cost_usd" | awk '{ printf "%.2f", $1 * 0.89 }')
fi

# === ANSI colours (Catppuccin Mocha) ===
blue="\033[38;2;137;180;250m"    # #89B4FA — directory
pink="\033[38;2;245;194;231m"    # #F5C2E7 — model
yellow="\033[38;2;249;226;175m"  # #F9E2AF — context (normal)
orange="\033[38;2;250;179;135m"  # #FAB387 — context (warning)
red="\033[38;2;243;139;168m"     # #F38BA8 — critical / drift / stale
green="\033[38;2;166;227;161m"   # #A6E3A1 — clean / lines added
teal="\033[38;2;148;226;213m"    # #94E2D5 — branch
mauve="\033[38;2;203;166;247m"   # #CBA6F7 — next-action / refactor
dim="\033[38;2;147;153;178m"     # #939AB2 — secondary info
reset="\033[0m"

# === Build output ===
parts=()

# Drift warning (red, prominent)
[ -n "$drifted" ] && parts+=("$(printf "${red}⚠ DRIFT${reset}")")

# Worktree badge
[ -n "$worktree_name" ] && parts+=("$(printf "${teal}⎇ %s${reset}" "$worktree_name")")

# Directory
[ -n "$short_dir" ] && parts+=("$(printf "${blue}%s${reset}" "$short_dir")")

# Git branch
[ -n "$branch" ] && parts+=("$(printf "${teal}%s${reset}" "$branch")")

# Combined next-action indicator (problem phase prefix + TDD next)
if [ -n "$next_action" ]; then
  # Color based on what the next action IS
  na_color="$mauve"
  case "$next_action" in
    test|investigate) na_color="$red" ;;     # write test / research
    impl|implement)   na_color="$green" ;;   # make it pass / start coding
    tidy|plan)        na_color="$mauve" ;;   # refactor / design
    close|branch)     na_color="$dim" ;;     # wrap up
    document)         na_color="$yellow" ;;  # document findings
  esac
  # Show problem phase prefix when not implementing (implementing defers to TDD)
  if [ -n "$problem_phase" ] && [ "$problem_phase" != "implementing" ] && [ "$problem_phase" != "done" ]; then
    parts+=("$(printf "${dim}%s${reset}${na_color}→ %s${reset}" "$problem_phase" "$next_action")")
  else
    parts+=("$(printf "${na_color}→ %s${reset}" "$next_action")")
  fi
fi

# Session nudge (contextual — only when noteworthy)
case "$session_nudge" in
  STALE) parts+=("$(printf "${red}⚠ STALE${reset}")") ;;
  push)  parts+=("$(printf "${orange}→ push${reset}")") ;;
  clean) parts+=("$(printf "${green}✓${reset}")") ;;
  # dirty: no indicator — you're actively working, don't nag
esac

# TDD discipline ratio (only on feature branches with commits)
tdd_total=$((tdd_tests + tdd_feats + tdd_refactors + tdd_tidies))
if [ "$tdd_total" -gt 0 ]; then
  # Color the ratio: red if no tests, green if healthy
  ratio_color="$dim"
  if [ "$tdd_feats" -gt 0 ] && [ "$tdd_tests" -eq 0 ]; then
    ratio_color="$red"  # features without tests = violation
  elif [ "$tdd_tests" -ge "$tdd_feats" ]; then
    ratio_color="$green"  # at least 1:1 test:feat ratio
  fi
  ratio_str="${tdd_tests}t ${tdd_feats}f"
  [ "$tdd_refactors" -gt 0 ] && ratio_str="$ratio_str ${tdd_refactors}r"
  [ "$tdd_tidies" -gt 0 ] && ratio_str="$ratio_str ${tdd_tidies}y"
  parts+=("$(printf "${ratio_color}[%s]${reset}" "$ratio_str")")
fi

# Time since last commit
[ -n "$commit_age" ] && parts+=("$(printf "${dim}%s${reset}" "$commit_age")")

# Model + context size
if [ -n "$model_name" ]; then
  model_display="$model_name"
  [ -n "$ctx_size" ] && model_display="$model_name ${dim}${ctx_size}${reset}"
  parts+=("$(printf "${pink}%s" "$model_display")")
fi

# Context usage (color-coded by pressure)
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_color="$yellow"
  [ "$used_int" -ge 60 ] && ctx_color="$red"
  [ "$used_int" -ge 30 ] && [ "$used_int" -lt 60 ] && ctx_color="$orange"
  parts+=("$(printf "${ctx_color}ctx %s%%${reset}" "$used_int")")
fi

# Lines delta
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
  line_str=""
  [ -n "$lines_added" ] && [ "$lines_added" != "0" ] && line_str="${green}+${lines_added}${reset}"
  if [ -n "$lines_removed" ] && [ "$lines_removed" != "0" ]; then
    [ -n "$line_str" ] && line_str="$line_str "
    line_str="${line_str}${red}-${lines_removed}${reset}"
  fi
  [ -n "$line_str" ] && parts+=("$line_str")
fi

# Cost in CHF
[ -n "$cost_chf" ] && parts+=("$(printf "${dim}CHF %s${reset}" "$cost_chf")")

# === Join with separator ===
result=""
for part in "${parts[@]}"; do
  [ -z "$result" ] && result="$part" || result="$result  $part"
done

printf "%b" "$result"
