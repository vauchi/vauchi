# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab runner recipes

# ═══════════════════════════════════════════════════════════════════
# GITLAB RUNNERS (docker-local via systemd)
# ═══════════════════════════════════════════════════════════════════

# Start docker-local runner service
[group('runners')]
runners-start:
    @echo "Starting docker-local runner..."
    systemctl --user start gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"
    @echo "Done. Run 'just runners-status' to verify."

# Stop docker-local runner service
[group('runners')]
runners-stop:
    @echo "Stopping docker-local runner..."
    systemctl --user stop gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"

# Restart docker-local runner service
[group('runners')]
runners-restart:
    @echo "Restarting docker-local runner..."
    systemctl --user restart gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"

# Show status of all runners
[group('runners')]
runners-status:
    @echo "── Runner Status ──"
    @echo ""
    @echo "Docker-local (systemd):"
    @systemctl --user status gitlab-runner --no-pager 2>&1 | head -5 || echo "  Not configured"
    @echo ""
    @echo "── GitLab Runner Config ──"
    @gitlab-runner list 2>&1 | head -20 || echo "  gitlab-runner not installed"

# View docker-local runner logs (follow mode)
[group('runners')]
runners-logs:
    journalctl --user -u gitlab-runner -f
