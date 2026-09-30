# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Self-healing health checks.
# Each recipe enforces an invariant that would otherwise drift silently.
# Run `just health` for the full suite, or individual recipes as gates.
#
# Ratchet protocol: after cleanup, lower the budget numbers in this file.
# The checks will enforce the new floor going forward.

# ── Problem record intake bucket ─────────────────────────────────
# Unbounded intake (never block creation), visible bucket level,
# backpressure when overflow (exit 1 on hard limit).

# Audit problem records: status, staleness, and the intake alert
[group('health')]
[script]
problem-audit:
    set -euo pipefail
    python3 << 'PYEOF'
    import os, re, sys
    from datetime import datetime, timezone

    # ── Budget (ratchet down after triage) ──────────────────────
    INTAKE_SOFT  = 10   # warn: triage soon
    INTAKE_HARD  = 15   # block: triage NOW
    TOTAL_SOFT   = 60   # warn: close/reject/merge
    TOTAL_HARD   = 80   # block: housekeeping required
    STALE_INTAKE = 14   # days
    STALE_ACTIVE = 30   # days

    # ── Parse ───────────────────────────────────────────────────
    problems_dir = "_private/docs/problems"
    if not os.path.isdir(problems_dir):
        print("ERROR: _private/docs/problems not found"); sys.exit(1)

    STATUS_PATS = [
        r'\*\*Status\*\*\s*\|\s*`?(\w+)',
        r'\*\*Status:\*\*\s*`?(\w+)',
        r'\*\*Status\*\*\s*:\s*`?(\w+)',
        r'##\s+Status:\s*(\w+)',
    ]

    by_status = {}
    stale = []
    now = datetime.now(tz=timezone.utc)

    for d in sorted(os.listdir(problems_dir)):
        if d in ("done", "rejected", "README.md"):
            continue
        readme = os.path.join(problems_dir, d, "README.md")
        if not os.path.isfile(readme):
            readme = os.path.join(problems_dir, d, "problem.md")
        if not os.path.isfile(readme):
            continue
        with open(readme) as f:
            header = "".join(f.readlines()[:20])
        st = "unknown"
        for pat in STATUS_PATS:
            m = re.search(pat, header)
            if m:
                st = m.group(1).lower()
                break
        by_status.setdefault(st, []).append(d)

        # Staleness: use dir name date prefix YYYY-MM-DD
        date_m = re.match(r"(\d{4}-\d{2}-\d{2})", d)
        if date_m:
            try:
                created = datetime.strptime(date_m.group(1), "%Y-%m-%d").replace(tzinfo=timezone.utc)
                age = (now - created).days
                if st == "intake" and age >= STALE_INTAKE:
                    stale.append((d, st, age, STALE_INTAKE))
                elif st in ("investigating", "planning", "implementing", "testing") and age >= STALE_ACTIVE:
                    stale.append((d, st, age, STALE_ACTIVE))
            except ValueError:
                pass

    # ── Counts ──────────────────────────────────────────────────
    active_phases = ["intake", "investigating", "planning", "implementing", "testing"]
    intake_count = len(by_status.get("intake", []))
    active_count = sum(len(by_status.get(p, [])) for p in active_phases)

    # ── Bucket visualization ────────────────────────────────────
    def bucket_bar(current, soft, hard, label):
        width = 30
        fill = min(current, hard)
        bar_len = int((fill / hard) * width) if hard > 0 else 0
        bar = "#" * bar_len + "." * (width - bar_len)
        if current > hard:
            tag = "OVERFLOW"
        elif current > soft:
            tag = "WARN"
        else:
            tag = "OK"
        return f"  {label:18s} [{bar}] {current:3d}/{hard} ({tag})"

    print("Problem Record Health")
    print("=" * 55)
    print()
    print(bucket_bar(intake_count, INTAKE_SOFT, INTAKE_HARD, "Intake bucket"))
    print(bucket_bar(active_count, TOTAL_SOFT, TOTAL_HARD, "Total active"))
    print()

    # ── Status distribution ─────────────────────────────────────
    order = ["intake", "investigating", "planning", "implementing", "testing", "deferred"]
    print("  Status distribution:")
    for phase in order:
        items = by_status.get(phase, [])
        if items:
            print(f"    {phase:15s} {len(items):3d}")
    unexpected = [k for k in by_status if k not in order]
    for k in sorted(unexpected):
        count = len(by_status[k])
        hint = ""
        if k in ("done", "closed", "resolved", "completed"):
            hint = " -> run `just problems-tidy` to move to done/"
        print(f"    {k:15s} {count:3d}  (unexpected{hint})")
    print()

    # ── Stale records ───────────────────────────────────────────
    if stale:
        print(f"  Stale records ({len(stale)}):")
        for name, st, age, threshold in sorted(stale, key=lambda x: -x[2]):
            print(f"    {age:3d}d  {st:15s}  {name}")
        print()

    # ── Verdict ─────────────────────────────────────────────────
    errors = []
    warnings = []

    if intake_count > INTAKE_HARD:
        errors.append(f"Intake bucket overflow: {intake_count} > {INTAKE_HARD} hard limit")
    elif intake_count > INTAKE_SOFT:
        warnings.append(f"Intake bucket filling: {intake_count} > {INTAKE_SOFT} soft limit — triage soon")

    if active_count > TOTAL_HARD:
        errors.append(f"Total active overflow: {active_count} > {TOTAL_HARD} hard limit")
    elif active_count > TOTAL_SOFT:
        warnings.append(f"Total active high: {active_count} > {TOTAL_SOFT} soft limit — close/reject/merge")

    if stale:
        warnings.append(f"{len(stale)} stale record(s) — review with `just problem-list intake`")

    if unexpected:
        for k in sorted(unexpected):
            if k in ("done", "closed", "resolved", "completed"):
                warnings.append(f"{len(by_status[k])} record(s) with status '{k}' still in active/ — run `just problems-tidy`")

    for w in warnings:
        print(f"  WARN: {w}")
    for e in errors:
        print(f"  ERROR: {e}")

    if errors:
        print("\n  ACTION REQUIRED: triage problem records before continuing feature work")
        sys.exit(1)
    elif warnings:
        print("\n  RESULT: PASS (with warnings)")
    else:
        print("  RESULT: PASS")
    PYEOF

# ── Unwrap budget ────────────────────────────────────────────────
# Each directory has a max unwrap budget. Ratchet down each release.
# Budget violations block push. To lower a budget after cleanup,
# just update the number below.
#
# v0.5.0 baseline (2026-03-27). Target: crypto/=0, total <100.

# Count unwrap() calls in vauchi-core source
[group('health')]
[script]
check-unwraps:
    set -euo pipefail
    CORE_SRC="core/vauchi-core/src"
    if [[ ! -d "$CORE_SRC" ]]; then
        echo "ERROR: $CORE_SRC not found"
        exit 1
    fi

    echo "Unwrap Budget Check"
    echo "==================="
    echo ""

    ERRORS=0
    TOTAL=0

    # Budget: directory, max allowed .unwrap() calls
    # v0.5.0 baseline (2026-03-27). Ratchet: lower after each cleanup pass.
    # Ultimate target: crypto=0, total <100.
    DIRS="crypto:30 exchange:100 network:150 storage:150 api:110 contact:55 diagnostic:15"
    TOTAL_BUDGET=625
    NAMED_SUM=0

    TOTAL=$(rg -c '\.unwrap\(\)' "$CORE_SRC" 2>/dev/null \
        | awk -F: '{s+=$NF} END {print s+0}')

    for ENTRY in $DIRS; do
        DIR_KEY="${ENTRY%%:*}"
        LIMIT="${ENTRY##*:}"
        COUNT=$(rg -c '\.unwrap\(\)' "$CORE_SRC/$DIR_KEY" 2>/dev/null \
            | awk -F: '{s+=$NF} END {print s+0}')
        NAMED_SUM=$((NAMED_SUM + COUNT))

        if [[ "$COUNT" -gt "$LIMIT" ]]; then
            echo "  FAIL  $DIR_KEY/: $COUNT unwraps (budget: $LIMIT)"
            ERRORS=$((ERRORS + 1))
        elif [[ "$COUNT" -gt 0 ]]; then
            echo "  OK    $DIR_KEY/: $COUNT unwraps (budget: $LIMIT)"
        else
            echo "  CLEAN $DIR_KEY/: 0 unwraps"
        fi
    done

    OTHER=$((TOTAL - NAMED_SUM))
    OTHER_BUDGET=15
    if [[ "$OTHER" -gt "$OTHER_BUDGET" ]]; then
        echo "  FAIL  _other/: $OTHER unwraps (budget: $OTHER_BUDGET)"
        ERRORS=$((ERRORS + 1))
    elif [[ "$OTHER" -gt 0 ]]; then
        echo "  OK    _other/: $OTHER unwraps (budget: $OTHER_BUDGET)"
    else
        echo "  CLEAN _other/: 0 unwraps"
    fi

    echo ""
    echo "  Total: $TOTAL unwraps (budget: $TOTAL_BUDGET)"
    echo ""

    if [[ "$TOTAL" -gt "$TOTAL_BUDGET" ]]; then
        echo "  FAIL: total $TOTAL exceeds budget $TOTAL_BUDGET"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ "$ERRORS" -gt 0 ]]; then
        echo "  $ERRORS budget(s) exceeded. Fix before pushing."
        exit 1
    else
        echo "  RESULT: PASS"
    fi

# ── Version consistency ──────────────────────────────────────────
# Stale product version references in planning docs get caught here.
# Update the STALE list when product version names change.
# Library version tags (v0.X.Y-dev, v0.X.Y-rc) are excluded — they
# track Cargo.toml versions, not product releases.

# Check version consistency across repos
[group('health')]
[script]
check-versions:
    set -euo pipefail
    echo "Version Consistency Check"
    echo "========================="
    echo ""

    ERRORS=0

    # Stale PRODUCT version patterns (old names, not library versions)
    for PAT in "v0\.2\.0" "v0\.3\.0" "v0\.4\.0"; do
        # Search active planning docs only
        # Exclude: archived/, done/, merge logs, infra assessments
        REAL_HITS=$(rg -n "$PAT" _private/docs/planning/ \
            --glob '!**/archived/**' \
            --glob '!**/done/**' \
            --glob '!**/*merge-pipeline*' \
            --glob '!**/*devinfra*' \
            --glob '!**/*assessment*' \
            2>/dev/null \
            | grep -v 'Updated 2026-' \
            | grep -v 'Version renaming' \
            | grep -v 'v0\.[0-9]\.[0-9]-dev' \
            | grep -v 'v0\.[0-9]\.[0-9]-rc' \
            | grep -v 'tag = "' \
            | grep -v '→v0\.' \
            | grep -v 'Rationale:' \
            || true)
        if [[ -n "$REAL_HITS" ]]; then
            echo "  STALE: pattern '$PAT' found outside historical notes:"
            echo "$REAL_HITS" | head -5 | sed 's/^/    /'
            ERRORS=$((ERRORS + 1))
        fi
    done

    # ROADMAP.md guard (killed per F2 — master plan is SSOT)
    if [[ -f "ROADMAP.md" ]]; then
        echo "  STALE: ROADMAP.md exists — it was replaced by master-plan.plan.md"
        ERRORS=$((ERRORS + 1))
    fi

    # Every consumer's Core pin against the latest release, read from
    # origin (ADR-026 amendment 2026-09-30, #434). A lagging pin, an
    # unreadable one, or a CI job that hard-codes a Core ref fails here.
    echo "Core pins"
    echo "---------"
    if ! python3 scripts/scripts/core-pins.py check --root . --fetch --strict; then
        echo "  STALE: a consumer's Core pin lags the latest release or disagrees with its CI"
        ERRORS=$((ERRORS + 1))
    fi

    echo ""
    if [[ "$ERRORS" -gt 0 ]]; then
        echo "  $ERRORS stale version reference(s) or Core pin problem(s) found."
        exit 1
    else
        echo "  RESULT: PASS"
    fi

# ── E2E ignore budget ───────────────────────────────────────────
# Ignored E2E tests rot silently. Budget ratchets down.
# v0.5.0 baseline: 47 ignores. Target: <10.

# Check that ignored e2e tests stay within budget
[group('health')]
[script]
check-e2e-ignores:
    set -euo pipefail
    E2E_DIR="e2e"
    BUDGET=50   # v0.5.0 baseline (actual: 47). Ratchet down.

    echo "E2E Ignore Budget Check"
    echo "======================="
    echo ""

    if [[ ! -d "$E2E_DIR" ]]; then
        echo "  SKIP: $E2E_DIR not found"
        exit 0
    fi

    COUNT=$(rg -c '#\[ignore' "$E2E_DIR" --type rust 2>/dev/null \
        | awk -F: '{s+=$NF} END {print s+0}')

    echo "  Ignored tests: $COUNT (budget: $BUDGET, target: <10)"
    echo ""

    if [[ "$COUNT" -gt "$BUDGET" ]]; then
        echo "  FAIL: $COUNT ignored tests exceeds budget of $BUDGET"
        exit 1
    else
        echo "  RESULT: PASS"
    fi

# ── Combined health check ───────────────────────────────────────
# Run all self-healing checks. Continues through all checks,
# reports combined result at end.

# ── Disk usage survey ────────────────────────────────────────────
# Reports current disk consumption hot spots in the dev environment:
# workspace target/.build/.spm-packages dirs, plus the largest of the
# global Xcode/SwiftPM/sccache caches. Read-only; does not delete.
# Use `just disk-clean` to reclaim.

# Survey disk usage: volume, cargo targets, caches
[group('health')]
[script]
disk:
    set -euo pipefail
    echo "── Disk usage survey ──"
    echo ""
    df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1
    echo ""
    echo "── Workspace target/ (Rust build artifacts) ──"
    du -sh */target 2>/dev/null | sort -hr | head -10 || true
    echo ""
    echo "── Workspace .build / .spm-packages / .derived-data ──"
    du -sh */{.build,.spm-packages,.derived-data} 2>/dev/null | sort -hr | head -10 || true
    echo ""
    echo "── Global caches (~/Library) ──"
    for path in \
        ~/Library/Caches/Mozilla.sccache \
        ~/Library/Caches/org.swift.swiftpm \
        ~/Library/Developer/CoreSimulator \
        ~/Library/Developer/Xcode/DerivedData \
        ~/Library/Caches/Homebrew \
        ~/Library/Caches/cargo-vet \
        ~/Library/Caches/pip; do
        if [[ -d "$path" ]]; then
            du -sh "$path" 2>/dev/null
        fi
    done | sort -hr | head -15
    echo ""
    echo "── sccache size config ──"
    grep '^size' ~/Library/Application\ Support/Mozilla.sccache/config 2>/dev/null \
        || cat ~/.config/sccache/config 2>/dev/null \
        || echo "  (no config — using defaults; consider capping via SCCACHE_CACHE_SIZE)"

# ── Disk cleanup (tiered, dry-run by default) ────────────────────
# Default tier=1: safe regeneratable caches only (SwiftPM artifacts,
# Xcode ModuleCache, orphaned WebDriverAgent, Homebrew old downloads).
# Reclaim ~10-15 GB; next iOS/macOS build is slightly slower while
# caches re-warm.
#
# tier=2 also clears Xcode DerivedData (slower next build, ~5 min)
# and per-project .build/.spm-packages (slower next SPM resolve).
#
# tier=3 also nukes Rust target/ dirs and resets sccache. Reclaim
# ~25 GB but next `cargo build` is a full rebuild (~30 min for core).
#
# Always dry-run unless --apply passed. Examples:
#   just disk-clean              # tier 1, dry-run
#   just disk-clean --apply      # tier 1, actually delete
#   just disk-clean --tier=2 --apply
#   just disk-clean --tier=3 --apply  # destructive, full rebuild after

# Free disk space by tier (dry run unless told to apply)
[group('health')]
[script]
disk-clean *args:
    set -euo pipefail
    TIER=1
    APPLY=0
    for arg in {{ args }}; do
        case "$arg" in
            --tier=1) TIER=1 ;;
            --tier=2) TIER=2 ;;
            --tier=3) TIER=3 ;;
            --apply) APPLY=1 ;;
            *) echo "Unknown arg: $arg"; exit 2 ;;
        esac
    done

    PATHS=()

    # Tier 1: safe regeneratable caches
    [[ -d ~/Library/Caches/org.swift.swiftpm/artifacts ]] && PATHS+=(~/Library/Caches/org.swift.swiftpm/artifacts)
    [[ -d ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex ]] && PATHS+=(~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex)
    [[ -d ~/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex ]] && PATHS+=(~/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex)
    [[ -d ~/Library/Developer/Xcode/DerivedData/SymbolCache.noindex ]] && PATHS+=(~/Library/Developer/Xcode/DerivedData/SymbolCache.noindex)
    for wda in ~/Library/Developer/Xcode/DerivedData/WebDriverAgent-*; do
        [[ -d "$wda" ]] && PATHS+=("$wda")
    done

    # Tier 2: full Xcode DerivedData + per-project SPM caches
    if [[ "$TIER" -ge 2 ]]; then
        [[ -d ~/Library/Developer/Xcode/DerivedData ]] && PATHS+=(~/Library/Developer/Xcode/DerivedData)
        for d in */{.build,.spm-packages,.derived-data}; do
            [[ -d "$d" ]] && PATHS+=("$d")
        done
    fi

    # Tier 3: Rust target/ + full sccache reset
    if [[ "$TIER" -ge 3 ]]; then
        for d in */target; do
            [[ -d "$d" ]] && PATHS+=("$d")
        done
        [[ -d ~/Library/Caches/Mozilla.sccache ]] && PATHS+=(~/Library/Caches/Mozilla.sccache)
    fi

    echo "── disk-clean tier $TIER ($([ "$APPLY" = 1 ] && echo APPLY || echo DRY-RUN)) ──"
    echo ""
    if [[ "${#PATHS[@]}" -eq 0 ]]; then
        echo "Nothing to clean at tier $TIER"
        exit 0
    fi
    TOTAL_K=0
    for p in "${PATHS[@]}"; do
        SIZE=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
        TOTAL_K=$((TOTAL_K + SIZE))
        printf "  %8s  %s\n" "$(du -sh "$p" 2>/dev/null | awk '{print $1}')" "$p"
    done
    TOTAL_GB=$(awk "BEGIN { printf \"%.1f\", $TOTAL_K / 1024 / 1024 }")
    echo ""
    echo "Total reclaimable: ${TOTAL_GB} GB"

    if [[ "$APPLY" -ne 1 ]]; then
        echo ""
        echo "(Dry-run. Pass --apply to actually delete.)"
        exit 0
    fi

    echo ""
    echo "Brew cleanup (always safe)…"
    brew cleanup --prune=all -s 2>&1 | tail -3 || true
    echo ""
    for p in "${PATHS[@]}"; do
        echo "rm -rf $p"
        rm -rf "$p"
    done
    echo ""
    echo "── after ──"
    df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1

[group('health')]
[script]
health:
    set -euo pipefail
    FAIL=0

    for CHECK in problem-audit check-unwraps check-versions check-e2e-ignores; do
        echo ""
        echo "--- just $CHECK ---"
        echo ""
        if ! just "$CHECK"; then
            FAIL=$((FAIL + 1))
        fi
    done

    echo ""
    echo "======================================"
    if [[ "$FAIL" -gt 0 ]]; then
        echo "HEALTH: $FAIL check(s) failed"
        exit 1
    else
        echo "HEALTH: ALL PASS"
    fi
