# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Deployment recipes
# Config: _private/infra/config/deploy.combined.yml

# ═══════════════════════════════════════════════════════════════════
# VALIDATION
# ═══════════════════════════════════════════════════════════════════

# Run pre-flight validation checks
[group('deploy')]
validate *FLAGS:
    ./_private/infra/scripts/validate.sh {{FLAGS}}

# ═══════════════════════════════════════════════════════════════════
# KAMAL DEPLOYMENT (relay + landing)
# ═══════════════════════════════════════════════════════════════════

# Deploy relay + landing using pre-built CI images (auto-resolves version from relay origin/main)
[group('deploy')]
deploy: validate
    ./_private/infra/scripts/deploy-all.sh --skip-validation

# Deploy relay + landing with local build + push (escape hatch for manual builds)
[group('deploy')]
deploy-with-build: validate
    ./_private/infra/scripts/deploy-all.sh --skip-validation --with-build

# Deploy a specific image version
[group('deploy')]
deploy-version VERSION:
    ./_private/infra/scripts/deploy-all.sh --version={{VERSION}}

# Verify website image contains only expected files (no workspace leaks)
[group('deploy')]
test-website-image:
    ./_private/infra/scripts/test-website-image.sh

# Show relay logs
[group('deploy')]
relay-logs:
    kamal app logs -f -c _private/infra/config/deploy.combined.yml

# ═══════════════════════════════════════════════════════════════════
# MAIL DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════

# Sync mail config + restart changed services
[group('deploy')]
deploy-mail:
    ./_private/infra/scripts/deploy-mail.sh

# Preview mail config changes (dry run)
[group('deploy')]
deploy-mail-dry:
    ./_private/infra/scripts/deploy-mail.sh --dry-run

# Prepare mail server for first-time setup
[group('deploy')]
mail-prepare:
    ./_private/infra/mail/prepare-mail.sh

# ═══════════════════════════════════════════════════════════════════
# BACKUP & RESTORE
# ═══════════════════════════════════════════════════════════════════

# Run backup on the VPS
[group('deploy')]
backup:
    ssh vauchi@bold-hopper-vps "/opt/vauchi-infra/scripts/backup.sh"

# Verify latest backup is restorable (runs on VPS)
[group('deploy')]
verify-backup:
    ssh vauchi@bold-hopper-vps "/opt/vauchi-infra/scripts/verify-backup.sh"

# ═══════════════════════════════════════════════════════════════════
# MONITORING (Prometheus + Grafana)
# ═══════════════════════════════════════════════════════════════════

# Deploy / update monitoring stack (Prometheus + Grafana + node_exporter)
[group('deploy')]
deploy-monitoring:
    ./_private/infra/scripts/deploy-monitoring.sh

# Show monitoring stack status
[group('deploy')]
monitoring-status:
    ./_private/infra/scripts/deploy-monitoring.sh --status

# Follow Grafana logs
[group('deploy')]
monitoring-logs:
    ./_private/infra/scripts/deploy-monitoring.sh --logs

# Re-create relay alias on monitoring network (run after each relay deploy)
[group('deploy')]
monitoring-relay-alias:
    #!/usr/bin/env bash
    set -euo pipefail
    SSH_TARGET="vauchi@bold-hopper-vps"
    RELAY=$(ssh "$SSH_TARGET" "docker ps --filter 'name=vauchi-relay-web-' --format '{{{{.Names}}' | head -1")
    if [ -z "$RELAY" ]; then
        echo "ERROR: No running relay container found"
        exit 1
    fi
    ssh "$SSH_TARGET" "docker network disconnect monitoring_monitoring $RELAY 2>/dev/null || true"
    ssh "$SSH_TARGET" "docker network connect --alias vauchi-relay-web monitoring_monitoring $RELAY"
    echo "Connected $RELAY to monitoring network as 'vauchi-relay-web'"

# ═══════════════════════════════════════════════════════════════════
# DEPLOY EVERYTHING
# ═══════════════════════════════════════════════════════════════════

# Deploy Kamal services + sync mail config + monitoring
[group('deploy')]
deploy-all: deploy deploy-mail deploy-monitoring

# ═══════════════════════════════════════════════════════════════════
# MAIL MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

# Show mail server logs
[group('deploy')]
mail-logs:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && docker compose logs -f mailserver"

# Mail server status
[group('deploy')]
mail-status:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && docker compose ps && echo '' && ./setup.sh email list"

# Webmail logs
[group('deploy')]
mail-webmail-logs:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && docker compose logs -f roundcube webmail-nginx"

# Add mail user
[group('deploy')]
mail-add-user email:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && ./setup.sh email add {{email}}"

# Update mail user password
[group('deploy')]
mail-update-password email:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && ./setup.sh email update {{email}}"

# List mail users
[group('deploy')]
mail-list-users:
    ssh vauchi@bold-hopper-vps "cd /opt/mail && ./setup.sh email list"
