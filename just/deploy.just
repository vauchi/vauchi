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

# Deploy relay + landing (full build + push + deploy)
[group('deploy')]
deploy: validate
    ./_private/infra/scripts/deploy-all.sh --skip-validation

# Deploy existing images only (skip build + push)
[group('deploy')]
deploy-skip-push:
    ./_private/infra/scripts/deploy-all.sh --skip-push

# Deploy a specific image version
[group('deploy')]
deploy-version VERSION:
    ./_private/infra/scripts/deploy-all.sh --version={{VERSION}}

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
# DEPLOY EVERYTHING
# ═══════════════════════════════════════════════════════════════════

# Deploy Kamal services + sync mail config
[group('deploy')]
deploy-all: deploy deploy-mail

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
