# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Build performance measurement and optimization recipes
# See also: just setup-fast-builds (configures sccache + mold)

# Measure build time for a repo (baseline benchmark)
[group('perf')]
@perf-build repo='core':
    echo "── Build Time Benchmark ({{repo}}) ──"
    echo "Clean build (cold cache):"
    /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml 2>&1 | grep real
    echo ""
    echo "Incremental build (warm cache):"
    /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml 2>&1 | grep real

# Measure test time for a repo
[group('perf')]
@perf-test repo='core':
    echo "── Test Time Benchmark ({{repo}}) ──"
    /usr/bin/time -p cargo test --manifest-path {{repo}}/Cargo.toml --lib 2>&1 | grep real

# Check for duplicate dependencies in repo dependency graph
[group('perf')]
@perf-duplicates repo='core':
    #!/bin/bash
    echo "── Duplicate Dependencies ({{repo}}) ──"
    if command -v cargo-duplicates &>/dev/null; then
        cd {{repo}} && cargo duplicates || echo "   (no duplicates)"
    else
        echo "   cargo-duplicates not installed. Run: just install-dev-deps"
    fi

# Analyze binary bloat and find largest dependencies
[group('perf')]
@perf-bloat repo='core':
    #!/bin/bash
    echo "── Binary Bloat Analysis ({{repo}}) ──"
    if ! command -v cargo-bloat &>/dev/null; then
        echo "cargo-bloat not installed. Run: just install-dev-deps"
        exit 1
    fi
    cd {{repo}} && cargo bloat --release -n 20

# Show sccache statistics (hit/miss rates)
[group('perf')]
@perf-sccache-stats:
    #!/bin/bash
    if command -v sccache &>/dev/null; then
        echo "── Sccache Statistics ──"
        sccache --show-stats
    else
        echo "sccache not installed. Run: just install-dev-deps"
    fi

# Clear sccache and rebuild to measure cold-cache performance
[group('perf')]
@perf-cold-cache repo='core':
    #!/bin/bash
    echo "── Cold Cache Rebuild ({{repo}}) ──"
    if command -v sccache &>/dev/null; then
        echo "Clearing sccache..."
        sccache --clear
        echo ""
    fi
    echo "Clean rebuild (no cache):"
    /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml --release 2>&1 | grep real

# Show current sccache configuration
[group('perf')]
@perf-sccache-config:
    #!/bin/bash
    if command -v sccache &>/dev/null; then
        echo "── Sccache Configuration ──"
        sccache --show-config
    else
        echo "sccache not installed. Run: just install-dev-deps"
    fi

# Full build performance report (duplicates + bloat + build time)
[group('perf')]
@perf-report repo='core':
    #!/bin/bash
    set -e

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Build Performance Report: {{repo}}"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Duplicates
    echo "1. Duplicate Dependencies"
    echo "──────────────────────────"
    if command -v cargo-duplicates &>/dev/null; then
        (cd {{repo}} && cargo duplicates 2>/dev/null | head -20) || echo "   (no duplicates)"
    else
        echo "   (cargo-duplicates not installed)"
    fi
    echo ""

    # Build time (warm cache)
    echo "2. Build Time (warm cache)"
    echo "──────────────────────────"
    /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml 2>&1 | grep real
    echo ""

    # sccache stats
    if command -v sccache &>/dev/null; then
        echo "3. Sccache Statistics"
        echo "─────────────────────"
        sccache --show-stats | head -10
        echo ""
    fi

    # Binary size (release)
    echo "4. Release Binary Size"
    echo "──────────────────────"
    found=false
    for bin in {{repo}}/target/release/*; do
        if [[ -f "$bin" && -x "$bin" && ! "$bin" =~ \.(d|o|rmeta)$ && ! "$bin" =~ /build/ ]]; then
            ls -lh "$bin" 2>/dev/null && found=true
        fi
    done
    if ! $found; then
        echo "   (no release binary found — run: cargo build --manifest-path {{repo}}/Cargo.toml --release)"
    fi
    echo ""

    echo "Tips:"
    echo "  just perf-sccache-config    — verify sccache is enabled"
    echo "  just perf-bloat {{repo}}       — analyze release binary size"
    echo "  just perf-cold-cache {{repo}}  — test with empty cache"
    echo "  just perf-compare {{repo}}     — A/B build time comparison"

# Compare build time before and after a change (baseline vs current)
[group('perf')]
@perf-compare repo='core':
    #!/bin/bash
    set -e

    BASELINE_FILE=".cache/perf-baseline-{{repo}}.txt"
    CURRENT_FILE=".cache/perf-current-{{repo}}.txt"

    mkdir -p .cache

    if [[ ! -f "$BASELINE_FILE" ]]; then
        echo "Recording baseline build time..."
        /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml 2>&1 | grep real > "$BASELINE_FILE"
        echo "Baseline saved. Make your changes and run again to compare."
        cat "$BASELINE_FILE"
    else
        echo "── Build Time Comparison ({{repo}}) ──"
        echo "Measuring current build time..."
        /usr/bin/time -p cargo build --manifest-path {{repo}}/Cargo.toml 2>&1 | grep real > "$CURRENT_FILE"

        echo ""
        echo "Baseline: $(awk '{print $2}' "$BASELINE_FILE")"
        echo "Current:  $(awk '{print $2}' "$CURRENT_FILE")"
        echo ""

        baseline=$(awk '{print $2}' "$BASELINE_FILE")
        current=$(awk '{print $2}' "$CURRENT_FILE")

        if (( $(echo "$current < $baseline" | bc -l) )); then
            improvement=$(echo "scale=1; ($baseline - $current) / $baseline * 100" | bc)
            echo "Improved by ${improvement}%"
        elif (( $(echo "$current > $baseline" | bc -l) )); then
            regression=$(echo "scale=1; ($current - $baseline) / $baseline * 100" | bc)
            echo "Regressed by ${regression}%"
        else
            echo "No significant change"
        fi

        rm "$CURRENT_FILE"
    fi

# Reset baseline for comparison
[group('perf')]
@perf-baseline-reset repo='core':
    #!/bin/bash
    BASELINE_FILE=".cache/perf-baseline-{{repo}}.txt"
    if [[ -f "$BASELINE_FILE" ]]; then
        rm "$BASELINE_FILE"
        echo "Baseline reset. Run 'just perf-compare {{repo}}' to record new baseline."
    else
        echo "No baseline found."
    fi
