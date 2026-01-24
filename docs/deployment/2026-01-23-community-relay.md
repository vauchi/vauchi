# Running a Community Relay

A simple guide for running your own Vauchi relay server for yourself, your family, or your community.

## Why Run Your Own Relay?

**Data Sovereignty**: Your contact card updates stay on infrastructure you control. The official relay works great, but you may prefer:

- **Privacy**: Only you and your contacts use your relay
- **Control**: Your data, your rules
- **Community**: Serve your local community, organization, or friend group
- **Reliability**: Not dependent on a single central service

**Important**: Running a relay does NOT mean you can see others' data. All Vauchi messages are end-to-end encrypted. The relay only stores encrypted blobs it cannot read.

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 512MB | 1GB |
| Storage | 5GB | 10GB |
| CPU | 1 core | 2 cores |
| Bandwidth | 10 Mbps | 100 Mbps |
| OS | Linux (any) | Ubuntu 22.04 |

A $5/month VPS from DigitalOcean, Linode, Hetzner, or Vultr works well.

## Quick Start (5 minutes)

### 1. Get a Server

Sign up with any VPS provider and create a server with Ubuntu 22.04.

### 2. Point Your Domain

Add a DNS A record pointing to your server's IP:
```
relay.yourdomain.com -> 123.45.67.89
```

### 3. One-Command Setup

SSH into your server and run:

```bash
curl -fsSL https://get.vauchi.app/relay | sudo bash -s -- relay.yourdomain.com
```

This script:
- Installs Docker and Caddy
- Deploys the relay container
- Configures TLS automatically (via Let's Encrypt)
- Sets up systemd for auto-restart

### 4. Verify

Check your relay is running:
```bash
curl https://relay.yourdomain.com/health
```

Should return: `{"status":"ok"}`

## Manual Setup

If you prefer manual installation:

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# Create data directory
sudo mkdir -p /var/lib/vauchi-relay
sudo chown $USER:$USER /var/lib/vauchi-relay

# Run the relay
docker run -d \
  --name vauchi-relay \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v /var/lib/vauchi-relay:/data \
  ghcr.io/vauchi/relay:latest

# Install Caddy for TLS
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy

# Configure Caddy
echo "relay.yourdomain.com {
    reverse_proxy localhost:8080
}" | sudo tee /etc/caddy/Caddyfile

# Restart Caddy (auto-obtains TLS cert)
sudo systemctl restart caddy
```

## Using Your Relay

In the Vauchi app:

1. Go to **Settings** > **Network**
2. Tap **Custom Relay**
3. Enter `wss://relay.yourdomain.com`
4. Tap **Save**

Share the relay URL with anyone who should use it. They'll enter the same URL in their settings.

## Monitoring

### Check Status

```bash
# Is the relay running?
docker ps | grep vauchi-relay

# View recent logs
docker logs --tail 100 vauchi-relay

# Check connections
curl -s https://relay.yourdomain.com/metrics | grep connections_active
```

### Simple Uptime Monitoring

Use a free service like [UptimeRobot](https://uptimerobot.com) or [Healthchecks.io](https://healthchecks.io):

1. Create a monitor for `https://relay.yourdomain.com/health`
2. Set check interval to 5 minutes
3. Configure email/SMS alerts

### Storage Usage

```bash
# Check disk usage
du -sh /var/lib/vauchi-relay

# Data is auto-cleaned after 90 days by default
```

## Updating

```bash
# Pull latest image
docker pull ghcr.io/vauchi/relay:latest

# Restart container
docker stop vauchi-relay
docker rm vauchi-relay
docker run -d \
  --name vauchi-relay \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v /var/lib/vauchi-relay:/data \
  ghcr.io/vauchi/relay:latest
```

## FAQ

### Can I see my users' messages?

No. All data is end-to-end encrypted before it reaches the relay. You only see encrypted blobs.

### How many users can one relay handle?

With default settings: ~1000 concurrent connections. A $5 VPS handles a small community easily.

### What if my relay goes down?

Users can switch to another relay (including the official one) at any time. Their contacts sync once they reconnect.

### Is the relay required to send messages?

Yes, but only for delivery. If the relay is down, messages queue locally and sync when it's back.

### Can I run multiple relays?

Yes! Configure redundant relays in the app for failover. Messages sync across all configured relays.

## Troubleshooting

### "Connection refused" in app

1. Check relay is running: `docker ps`
2. Check firewall: `sudo ufw status` (allow 80, 443)
3. Check DNS: `dig relay.yourdomain.com`
4. Check TLS: `curl -v https://relay.yourdomain.com/health`

### High memory usage

Increase cleanup frequency or reduce retention:

```bash
docker stop vauchi-relay
docker rm vauchi-relay
docker run -d \
  --name vauchi-relay \
  --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v /var/lib/vauchi-relay:/data \
  -e RELAY_BLOB_TTL_SECS=2592000 \  # 30 days instead of 90
  ghcr.io/vauchi/relay:latest
```

### TLS certificate not renewing

Caddy renews automatically. If issues occur:

```bash
sudo systemctl status caddy
sudo journalctl -u caddy --since "1 hour ago"
sudo systemctl restart caddy
```

## Getting Help

- **Documentation**: [vauchi.app/docs](https://vauchi.app/docs)
- **Community**: [Discord](https://discord.gg/vauchi) or [Matrix](https://matrix.to/#/#vauchi:matrix.org)
- **Issues**: [GitHub Issues](https://github.com/vauchi/vauchi/issues)

---

*Running a community relay helps decentralize the network and gives you full control over your data sovereignty. Thank you for contributing to the Vauchi ecosystem!*
