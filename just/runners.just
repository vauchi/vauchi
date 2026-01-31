# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab runners & VM recipes

# ═══════════════════════════════════════════════════════════════════
# GITLAB RUNNERS & VMS
# ═══════════════════════════════════════════════════════════════════

# Start all runners (VMs + docker-local service)
[group('runners')]
[script('bash')]
runners-start:
    set -euo pipefail
    echo "Starting all runners..."

    # Start VMs in parallel
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh start-nowait &
    pid_linux=$!
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh start-nowait &
    pid_macos=$!

    # Start docker-local service
    systemctl --user start gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"

    # Wait for VM start commands
    wait $pid_linux $pid_macos 2>/dev/null || true

    echo ""
    echo "Waiting for VMs to become ready..."

    # Wait for SSH on VMs
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh wait &
    pid_wait_linux=$!
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh wait &
    pid_wait_macos=$!

    wait $pid_wait_linux && echo "[OK] Linux VM ready" || echo "[SKIP] Linux VM not available"
    wait $pid_wait_macos && echo "[OK] macOS VM ready" || echo "[SKIP] macOS VM not available"

    # Check docker-local
    systemctl --user is-active gitlab-runner &>/dev/null && echo "[OK] Docker-local runner active" || echo "[SKIP] Docker-local not running"

    echo ""
    echo "Done. Run 'just runners-status' to verify."

# Stop all runners (VMs + docker-local service)
[group('runners')]
runners-stop:
    @echo "Stopping all runners..."
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh stop || true
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh stop || true
    systemctl --user stop gitlab-runner 2>/dev/null || true

# Show status of all runners
[group('runners')]
runners-status:
    @echo "=== Runner Status ==="
    @echo ""
    @echo "Linux VM:"
    @./_private/infra/runners/linux-vm/vm-lifecycle.sh status || echo "  Not configured"
    @echo ""
    @echo "macOS VM:"
    @./_private/infra/runners/macos-vm/vm-lifecycle.sh status || echo "  Not configured"
    @echo ""
    @echo "Docker-local (systemd):"
    @systemctl --user status gitlab-runner --no-pager 2>&1 | head -5 || echo "  Not configured"
    @echo ""
    @echo "=== GitLab Runner Config ==="
    @gitlab-runner list 2>&1 | head -20 || echo "  gitlab-runner not installed"

# ─── Linux VM ──────────────────────────────────────────────────────

# Start Linux VM
[group('runners')]
vm-linux-start:
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh start

# Stop Linux VM
[group('runners')]
vm-linux-stop:
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh stop

# SSH into Linux VM
[group('runners')]
vm-linux-ssh *args:
    ./_private/infra/runners/linux-vm/vm-lifecycle.sh ssh {{args}}

# ─── macOS VM ──────────────────────────────────────────────────────

# Start macOS VM
[group('runners')]
vm-macos-start:
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh start

# Stop macOS VM
[group('runners')]
vm-macos-stop:
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh stop

# SSH into macOS VM
[group('runners')]
vm-macos-ssh *args:
    ./_private/infra/runners/macos-vm/vm-lifecycle.sh ssh {{args}}

# ─── Docker-local Runner (systemd) ─────────────────────────────────

# Start docker-local runner service
[group('runners')]
docker-runner-start:
    systemctl --user start gitlab-runner

# Stop docker-local runner service
[group('runners')]
docker-runner-stop:
    systemctl --user stop gitlab-runner

# Show docker-local runner status
[group('runners')]
docker-runner-status:
    systemctl --user status gitlab-runner --no-pager

# View docker-local runner logs
[group('runners')]
docker-runner-logs:
    journalctl --user -u gitlab-runner -f

# Restart docker-local runner
[group('runners')]
docker-runner-restart:
    systemctl --user restart gitlab-runner
