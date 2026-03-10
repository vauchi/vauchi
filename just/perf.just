# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Build performance measurement and optimization recipes

# Measure build time for a repo (baseline benchmark)
[group('perf')]
@perf-build repo='core':
    echo "=== Build Time Benchmark ({{repo}}) ==="
    echo "Clean build (cold cache):"
    /usr/bin/time -p cargo -C {{repo}} build 2>&1 | grep real
    echo ""
    echo "Incremental build (warm cache):"
    /usr/bin/time -p cargo -C {{repo}} build 2>&1 | grep real

# Measure test time for a repo
[group('perf')]
@perf-test repo='core':
    echo "=== Test Time Benchmark ({{repo}}) ==="
    /usr/bin/time -p cargo -C {{repo}} test --lib 2>&1 | grep real

# Check for duplicate dependencies in repo dependency graph
[group('perf')]
@perf-duplicates repo='core':
    echo "=== Duplicate Dependencies ({{repo}}) ==="
    cargo -C {{repo}} duplicates || echo "No duplicates or cargo-duplicates not installed"

# Analyze binary bloat and find largest dependencies
[group('perf')]
@perf-bloat repo='core' binary='vauchi-core':
    #!/bin/bash
    echo "=== Binary Bloat Analysis ({{repo}}) ==="
    # Build in release mode if not already built
    if ! [[ -f "{{repo}}/target/release/{{binary}}" ]]; then
        echo "Building release binary..."
        cargo -C {{repo}} build --release
    fi

    if command -v cargo-bloat &>/dev/null; then
        cargo -C {{repo}} bloat --release -n 20
    else
        echo "cargo-bloat not installed. Install with: cargo install cargo-bloat"
        exit 1
    fi

# Show sccache statistics (hit/miss rates)
[group('perf')]
@perf-sccache-stats:
    #!/bin/bash
    if command -v sccache &>/dev/null; then
        echo "=== Sccache Statistics ==="
        sccache --show-stats
    else
        echo "sccache not installed. Install with: cargo install sccache"
        exit 1
    fi

# Clear sccache and rebuild to measure cold-cache performance
[group('perf')]
@perf-cold-cache repo='core':
    #!/bin/bash
    echo "=== Cold Cache Rebuild ({{repo}}) ==="
    if command -v sccache &>/dev/null; then
        echo "Clearing sccache..."
        sccache --clear
        echo ""
    fi
    echo "Clean rebuild (no cache):"
    /usr/bin/time -p cargo -C {{repo}} build --release 2>&1 | grep real

# Show current sccache configuration
[group('perf')]
@perf-sccache-config:
    #!/bin/bash
    if command -v sccache &>/dev/null; then
        echo "=== Sccache Configuration ==="
        sccache --show-config
    else
        echo "sccache not installed. Install with: cargo install sccache"
        exit 1
    fi

# Full build performance report (duplicates + bloat + build time)
[group('perf')]
@perf-report repo='core':
    #!/bin/bash
    set -e

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Build Performance Report for {{repo}}              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Duplicates
    echo "1. Duplicate Dependencies"
    echo "──────────────────────────"
    if command -v cargo-duplicates &>/dev/null; then
        cargo -C {{repo}} duplicates 2>/dev/null | head -20 || echo "   (no duplicates)"
    else
        echo "   (cargo-duplicates not installed)"
    fi
    echo ""

    # Build time (warm cache)
    echo "2. Build Time (warm cache)"
    echo "──────────────────────────"
    /usr/bin/time -p cargo -C {{repo}} build 2>&1 | grep real
    echo ""

    # sccache stats
    if command -v sccache &>/dev/null; then
        echo "3. Sccache Statistics"
        echo "─────────────────────"
        sccache --show-stats | head -10
        echo ""
    fi

    # Binary size (release)
    echo "4. Binary Size Analysis"
    echo "──────────────────────"
    if [[ -f "{{repo}}/target/release/{{repo}}" ]]; then
        ls -lh "{{repo}}/target/release/{{repo}}"
    elif [[ -f "{{repo}}/target/release/vauchi-core" ]]; then
        ls -lh "{{repo}}/target/release/vauchi-core"
    else
        echo "   (release binary not built yet)"
    fi
    echo ""

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Tips for optimization:                                         ║"
    echo "║ • Use 'just perf-sccache-config' to verify sccache is enabled  ║"
    echo "║ • Use 'just perf-bloat core' to analyze release binary         ║"
    echo "║ • Use 'just perf-cold-cache' to test with empty cache         ║"
    echo "║ • Check Cargo.toml for unused dependencies with 'cargo tree'  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"

# Compare build time before and after a change (baseline vs current)
[group('perf')]
@perf-compare repo='core':
    #!/bin/bash
    set -e

    BASELINE_FILE="cache/perf-baseline-{{repo}}.txt"
    CURRENT_FILE="cache/perf-current-{{repo}}.txt"

    mkdir -p cache

    if [[ ! -f "$BASELINE_FILE" ]]; then
        echo "Recording baseline build time..."
        /usr/bin/time -p cargo -C {{repo}} build 2>&1 | grep real > "$BASELINE_FILE"
        echo "Baseline saved. Run again to compare."
        cat "$BASELINE_FILE"
    else
        echo "=== Build Time Comparison ({{repo}}) ==="
        echo "Measuring current build time..."
        /usr/bin/time -p cargo -C {{repo}} build 2>&1 | grep real > "$CURRENT_FILE"

        echo ""
        echo "Baseline: $(cat $BASELINE_FILE | awk '{print $2}')"
        echo "Current:  $(cat $CURRENT_FILE | awk '{print $2}')"
        echo ""

        baseline=$(cat "$BASELINE_FILE" | awk '{print $2}' | sed 's/s//')
        current=$(cat "$CURRENT_FILE" | awk '{print $2}' | sed 's/s//')

        if (( $(echo "$current < $baseline" | bc -l) )); then
            improvement=$(echo "scale=2; ($baseline - $current) / $baseline * 100" | bc)
            echo "✓ Improved by ${improvement}%"
        elif (( $(echo "$current > $baseline" | bc -l) )); then
            regression=$(echo "scale=2; ($current - $baseline) / $baseline * 100" | bc)
            echo "✗ Regressed by ${regression}%"
        else
            echo "≈ No significant change"
        fi

        # Clean up for next run
        rm "$CURRENT_FILE"
    fi

# Reset baseline for comparison
[group('perf')]
@perf-baseline-reset repo='core':
    #!/bin/bash
    BASELINE_FILE="cache/perf-baseline-{{repo}}.txt"
    if [[ -f "$BASELINE_FILE" ]]; then
        rm "$BASELINE_FILE"
        echo "Baseline reset. Run 'just perf-compare {{repo}}' to record new baseline."
    else
        echo "No baseline found."
    fi
