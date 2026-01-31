# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Deployment recipes

# ═══════════════════════════════════════════════════════════════════
# DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════

# Deploy relay using Kamal
deploy-relay:
    kamal deploy -c _private/infra/config/deploy.yml

# Show relay logs
relay-logs:
    kamal app logs -f -c _private/infra/config/deploy.yml

# Prepare mail server (run before port 25 is open)
mail-prepare:
    ./_private/infra/mail/prepare-mail.sh

# Deploy mail server (run after port 25 is open)
mail-deploy:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && ./deploy-mail.sh"

# Show mail server logs
mail-logs:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && docker compose logs -f mailserver"

# Mail server status
mail-status:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && docker compose ps && echo '' && ./setup.sh email list"

# Webmail logs
mail-webmail-logs:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && docker compose logs -f roundcube webmail-nginx"

# Add mail user
mail-add-user email:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && ./setup.sh email add {{email}}"

# Update mail user password
mail-update-password email:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && ./setup.sh email update {{email}}"

# List mail users
mail-list-users:
    ssh fufadmin@bold-hopper-vps "cd /opt/mail && ./setup.sh email list"
