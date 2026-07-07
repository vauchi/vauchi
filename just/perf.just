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

# ═══════════════════════════════════════════════════════════════
# RUNTIME PROFILING — tracing-flame on E2E tests
# ═══════════════════════════════════════════════════════════════
#
# Captures `tracing` spans emitted in-process by vauchi-core,
# vauchi-app, and the e2e orchestrator. Renders to an SVG flamegraph
# via `inferno-flamegraph`. Subprocess CLIs/relays are NOT captured
# (they are separate processes); for those, attach `samply` per-pid.
#
# Output: e2e/artifacts/flame/  (gitignored)
# Override path: VAUCHI_FLAME_OUT=/path/to/trace.folded
# Override filter: VAUCHI_FLAME_FILTER='vauchi_core=trace,...'

# Run an E2E test with the tracing-flame layer; emits a `.folded` trace
[group('perf')]
[script]
flame-e2e test='five_user_exchange':
    set -euo pipefail
    echo "── tracing-flame: e2e test '{{test}}' ──"
    mkdir -p e2e/artifacts/flame
    cd e2e && cargo test --release --features flame --test it -- \
        --test-threads=1 --nocapture --include-ignored "{{test}}"
    echo ""
    echo "Latest trace:"
    ls -t e2e/artifacts/flame/*.folded 2>/dev/null | head -1 || echo "  (none)"
    echo ""
    echo "Render: just flame-render"

# Render the most recent folded trace (any source) to SVG via inferno-flamegraph
[group('perf')]
[script]
flame-render:
    set -euo pipefail
    if ! command -v inferno-flamegraph &>/dev/null; then
        echo "Error: inferno-flamegraph not installed."
        echo "  Install: cargo install inferno"
        exit 1
    fi
    LATEST=$(ls -t e2e/artifacts/flame/*.folded \
                  core/vauchi-core/artifacts/flame/*.folded \
                  relay/artifacts/flame/*.folded \
                  ohttp-relay/artifacts/flame/*.folded 2>/dev/null | head -1)
    if [[ -z "${LATEST:-}" ]]; then
        echo "Error: no .folded trace found in any artifacts/flame/ dir"
        echo "  Generate: just flame-e2e <test> | just flame-relay | just flame-ohttp-relay"
        exit 1
    fi
    OUT="${LATEST%.folded}.svg"
    inferno-flamegraph < "$LATEST" > "$OUT"
    echo "Rendered: $OUT"
    echo "Open with: xdg-open \"$OUT\""

# Run an E2E test and immediately render the resulting flamegraph
[group('perf')]
flame-e2e-svg test='five_user_exchange': (flame-e2e test) flame-render

# List captured flame traces across all sources (folded + rendered SVGs)
[group('perf')]
[script]
flame-list:
    set -euo pipefail
    found=0
    for dir in e2e/artifacts/flame core/vauchi-core/artifacts/flame relay/artifacts/flame ohttp-relay/artifacts/flame; do
        if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            echo "── $dir ──"
            ls -lht "$dir" 2>/dev/null | tail -n +2 | head -10
            echo ""
            found=1
        fi
    done
    if [[ $found -eq 0 ]]; then
        echo "(no traces captured yet)"
    fi

# Remove all captured flame traces (e2e + core + relay + ohttp-relay)
[group('perf')]
[script]
flame-clean:
    set -euo pipefail
    cleared=0
    for dir in e2e/artifacts/flame core/vauchi-core/artifacts/flame relay/artifacts/flame ohttp-relay/artifacts/flame; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            echo "Cleared $dir/"
            cleared=$((cleared + 1))
        fi
    done
    if [[ $cleared -eq 0 ]]; then
        echo "(nothing to clean)"
    fi

# ── Flame profiling for vauchi-core tests ──────────────────────

# Run vauchi-core tests with tracing-flame; output: core/vauchi-core/artifacts/flame/
# `testing` feature is required to compile the `it` integration test binary,
# which is where most callers of instrumented core APIs live.
[group('perf')]
[script]
flame-core test_filter='':
    set -euo pipefail
    echo "── tracing-flame: vauchi-core (filter='{{test_filter}}') ──"
    mkdir -p core/vauchi-core/artifacts/flame
    OUT="$PWD/core/vauchi-core/artifacts/flame/core-$(date +%s).folded"
    cd core && \
        VAUCHI_FLAME_OUT="$OUT" \
        cargo test --release -p vauchi-core --features flame,testing --test it -- --test-threads=1 "{{test_filter}}"
    echo ""
    echo "Wrote: $OUT"
    echo "Render: just flame-render"

# Profile vauchi-core tests under samply (CPU sampling)
[group('perf')]
[script]
samply-core test_filter='':
    set -euo pipefail
    if ! command -v samply &>/dev/null; then
        echo "Error: samply not installed."
        echo "  Install: cargo install samply"
        exit 1
    fi
    echo "── samply: vauchi-core (filter='{{test_filter}}') ──"
    mkdir -p core/vauchi-core/artifacts/samply
    OUT="$PWD/core/vauchi-core/artifacts/samply/core-$(date +%s).profile.json"
    # Override workspace `[profile.release].strip = true` so samples resolve to symbols.
    CARGO_PROFILE_RELEASE_STRIP=false CARGO_PROFILE_RELEASE_DEBUG=line-tables-only \
        RUSTFLAGS="-C force-frame-pointers=yes" \
        cargo test --manifest-path core/Cargo.toml -p vauchi-core --release --features testing --test it --no-run
    BIN=$(ls -t core/target/release/deps/it-* 2>/dev/null | grep -v '\.d$' | head -1)
    if [[ -z "${BIN:-}" ]]; then
        echo "Error: could not locate release test binary (core/target/release/deps/it-*)"
        exit 1
    fi
    samply record --save-only --unstable-presymbolicate -o "$OUT" -- \
        "$BIN" --test-threads=1 "{{test_filter}}"
    echo "Wrote: $OUT"
    echo "Open: samply load \"$OUT\""

# ── Flame profiling for relay services ─────────────────────────

# Run vauchi-relay under tracing-flame for `duration_secs`, then SIGTERM (default 30s)
[group('perf')]
[script]
flame-relay duration_secs='30':
    set -euo pipefail
    echo "── tracing-flame: relay (duration={{duration_secs}}s) ──"
    mkdir -p relay/artifacts/flame
    OUT="relay/artifacts/flame/relay-$(date +%s).folded"
    cargo build --manifest-path relay/Cargo.toml --release --features flame
    VAUCHI_FLAME_OUT="$PWD/$OUT" \
        relay/target/release/vauchi-relay &
    PID=$!
    trap 'kill -TERM "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true' EXIT
    sleep "{{duration_secs}}"
    kill -TERM "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    trap - EXIT
    echo "Wrote: $OUT"
    echo "Render: just flame-render"

# Run vauchi-ohttp-relay under tracing-flame for `duration_secs`, then SIGTERM (default 30s)
[group('perf')]
[script]
flame-ohttp-relay duration_secs='30':
    set -euo pipefail
    echo "── tracing-flame: ohttp-relay (duration={{duration_secs}}s) ──"
    mkdir -p ohttp-relay/artifacts/flame
    OUT="ohttp-relay/artifacts/flame/ohttp-relay-$(date +%s).folded"
    cargo build --manifest-path ohttp-relay/Cargo.toml --release --features flame
    VAUCHI_FLAME_OUT="$PWD/$OUT" \
        ohttp-relay/target/release/vauchi-ohttp-relay &
    PID=$!
    trap 'kill -TERM "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true' EXIT
    sleep "{{duration_secs}}"
    kill -TERM "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    trap - EXIT
    echo "Wrote: $OUT"
    echo "Render: just flame-render"

# Update flame-render to find the most recent trace across all three sources.
# (Original recipe only looked at e2e/artifacts/flame.)

# ═══════════════════════════════════════════════════════════════
# RUNTIME PROFILING — samply (CPU sampling, no instrumentation)
# ═══════════════════════════════════════════════════════════════
#
# samply works without any tracing instrumentation — it samples the
# kernel-reported call stack at fixed intervals. Output opens in the
# Firefox Profiler.
#
# Linux: requires `perf_event_paranoid <= 1` (some recent kernels reject 2).
# Set with: sudo sysctl kernel.perf_event_paranoid=1
# Profiles are emitted with a `.syms.json` sidecar (`--unstable-presymbolicate`)
# so symbols resolve even if the binary is later rebuilt or moved.
#
# Output: <repo>/artifacts/samply/<name>-<ts>.profile.json
# (gitignored alongside flame/)

# Profile an E2E test under samply (CPU sampling)
[group('perf')]
[script]
samply-e2e test='five_user_exchange':
    set -euo pipefail
    if ! command -v samply &>/dev/null; then
        echo "Error: samply not installed."
        echo "  Install: cargo install samply"
        exit 1
    fi
    echo "── samply: e2e test '{{test}}' ──"
    mkdir -p e2e/artifacts/samply
    OUT="e2e/artifacts/samply/e2e-{{test}}-$(date +%s).profile.json"
    # Override workspace `[profile.release].strip = true` so samples resolve to symbols.
    CARGO_PROFILE_RELEASE_STRIP=false CARGO_PROFILE_RELEASE_DEBUG=line-tables-only \
        RUSTFLAGS="-C force-frame-pointers=yes" \
        cargo test --manifest-path e2e/Cargo.toml --release --test it --no-run
    BIN=$(ls -t e2e/target/release/deps/it-* 2>/dev/null | grep -v '\.d$' | head -1)
    if [[ -z "${BIN:-}" ]]; then
        echo "Error: could not locate release test binary"
        exit 1
    fi
    samply record --save-only --unstable-presymbolicate -o "$OUT" -- \
        "$BIN" --test-threads=1 --include-ignored "{{test}}"
    echo "Wrote: $OUT"
    echo "Open: samply load \"$OUT\""

# Profile vauchi-relay under samply for duration_secs
[group('perf')]
[script]
samply-relay duration_secs='30':
    set -euo pipefail
    if ! command -v samply &>/dev/null; then
        echo "Error: samply not installed."
        echo "  Install: cargo install samply"
        exit 1
    fi
    echo "── samply: relay (duration={{duration_secs}}s) ──"
    mkdir -p relay/artifacts/samply
    OUT="relay/artifacts/samply/relay-$(date +%s).profile.json"
    # Override `[profile.release].strip = true` so samples resolve to symbols.
    CARGO_PROFILE_RELEASE_STRIP=false CARGO_PROFILE_RELEASE_DEBUG=line-tables-only \
        RUSTFLAGS="-C force-frame-pointers=yes" \
        cargo build --manifest-path relay/Cargo.toml --release
    samply record --save-only --unstable-presymbolicate -o "$OUT" --duration "{{duration_secs}}" -- \
        relay/target/release/vauchi-relay &
    PID=$!
    wait "$PID" 2>/dev/null || true
    echo "Wrote: $OUT"
    echo "Open: samply load \"$OUT\""

# Profile vauchi-ohttp-relay under samply for duration_secs
[group('perf')]
[script]
samply-ohttp-relay duration_secs='30':
    set -euo pipefail
    if ! command -v samply &>/dev/null; then
        echo "Error: samply not installed."
        echo "  Install: cargo install samply"
        exit 1
    fi
    echo "── samply: ohttp-relay (duration={{duration_secs}}s) ──"
    mkdir -p ohttp-relay/artifacts/samply
    OUT="ohttp-relay/artifacts/samply/ohttp-relay-$(date +%s).profile.json"
    # Override `[profile.release].strip = true` so samples resolve to symbols.
    CARGO_PROFILE_RELEASE_STRIP=false CARGO_PROFILE_RELEASE_DEBUG=line-tables-only \
        RUSTFLAGS="-C force-frame-pointers=yes" \
        cargo build --manifest-path ohttp-relay/Cargo.toml --release
    samply record --save-only --unstable-presymbolicate -o "$OUT" --duration "{{duration_secs}}" -- \
        ohttp-relay/target/release/vauchi-ohttp-relay &
    PID=$!
    wait "$PID" 2>/dev/null || true
    echo "Wrote: $OUT"
    echo "Open: samply load \"$OUT\""

# Measure carbon emissions of `cargo test -p vauchi-core` using CodeCarbon.
# Requires: python3 + codecarbon.
# Quick setup:
#   python3 -m venv .venv/carbon
#   source .venv/carbon/bin/activate
#   python3 -m pip install -r scripts/requirements-carbon.txt
[group('perf')]
[script]
perf-carbon-test:
    set -euo pipefail
    if ! command -v python3 &>/dev/null; then
        echo "Error: python3 not found." >&2
        exit 1
    fi
    # Prefer a local venv if it exists.
    PYTHON=python3
    VENV="{{ justfile_directory() }}/.venv/carbon/bin/python3"
    if [[ -x "$VENV" ]]; then
        PYTHON="$VENV"
    fi
    "$PYTHON" - <<'PY'
    import importlib.util, sys
    if importlib.util.find_spec("codecarbon") is None:
        print("Error: codecarbon is not installed.", file=sys.stderr)
        print("Install with:", file=sys.stderr)
        print("  python3 -m venv .venv/carbon", file=sys.stderr)
        print("  source .venv/carbon/bin/activate", file=sys.stderr)
        print("  python3 -m pip install -r scripts/requirements-carbon.txt", file=sys.stderr)
        sys.exit(1)
    PY
    echo "── CodeCarbon: cargo test -p vauchi-core ──"
    (cd "{{ justfile_directory() }}/core" && "$PYTHON" "{{ justfile_directory() }}/scripts/measure-carbon.py" \
        --project-name vauchi-core \
        --experiment-id "vauchi-core-test-$(date +%s)" \
        --output-dir .cache/carbon \
        --format text \
        -- cargo test -p vauchi-core)

# Remove all samply profiles
[group('perf')]
[script]
samply-clean:
    set -euo pipefail
    cleared=0
    for dir in e2e/artifacts/samply core/vauchi-core/artifacts/samply relay/artifacts/samply ohttp-relay/artifacts/samply; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            echo "Cleared $dir/"
            cleared=$((cleared + 1))
        fi
    done
    if [[ $cleared -eq 0 ]]; then
        echo "(nothing to clean)"
    fi
