#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Deep running-state check for `just deploy-check --running`.
#
# deploy-check answers "is a newer build available than what's deployed?" from
# served build-info + the registry — it never asks the host what it is ACTUALLY
# running. This does. Two classes of service:
#
#   App services (docs/cdn/landing/relay/ohttp) — vauchi-built, versioned by
#   commit SHA. Resolve the kamal-proxy-ACTIVE target container (the one
#   receiving traffic, per Codex — not an arbitrary one) and reconcile what it
#   is RUNNING against what the host SERVES (build-info.json) and the newest
#   successful build. A mutable :latest deploy is reported UNKNOWN, never
#   guessed.
#
#   Infra services (vaultwarden/infisical/prometheus/grafana) — upstream
#   third-party images, versioned by tag, not a build SHA. Resolve the
#   container by name (Prometheus has no public route, so kamal-proxy can't
#   find it) and compare the RUNNING image tag against the PINNED tag in the
#   repo's docker-compose, so you can see what is actually live vs the config.
#
# Per-service data gathering runs in parallel to keep the wall-clock down.
#
# Usage: deploy-running.sh <ssh-user@host>

set -uo pipefail
SSH_TARGET="${1:?usage: deploy-running.sh <user@host>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # workspace root (contains _private/)

if [ -t 1 ]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; DIM=$'\e[2m'; NC=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""; DIM=""; NC=""
fi

is_hex() { printf '%s' "${1:-}" | grep -qE '^[0-9a-f]{7,40}$'; }
pref()   { case "$2" in "$1"*) return 0 ;; esac; case "$1" in "$2"*) return 0 ;; esac; return 1; }
disp()   { if is_hex "$1"; then printf '%.12s' "$1"; else printf '%s' "$1"; fi; }
latest_built() {
  glab api "projects/vauchi%2F${1}/pipelines?ref=main&status=success&per_page=1" 2>/dev/null \
    | jq -r '.[0].sha // empty' 2>/dev/null
}

# App services:   svc | host | build-info-path (- if none) | repo | proxy-service
APP_MANIFEST='docs|docs.vauchi.app|/build-info.json|docs|vauchi-docs-web-production
cdn|cdn.vauchi.app|/build-info.json|website|vauchi-cdn-web-production
landing|vauchi.app|/build-info.json|website|vauchi-landing-web-production
relay|relay.vauchi.app|-|relay|vauchi-relay-web-production
ohttp|ohttp.vauchi.app|-|ohttp-relay|vauchi-ohttp-relay-web-production'

# Infra services: svc | container | compose-relpath (under _private/) | image-repo
INFRA_MANIFEST='vaultwarden|vauchi-vaultwarden|infra/vaultwarden/docker-compose.yml|vaultwarden/server
infisical|vauchi-infisical|infra/infisical/docker-compose.yml|infisical/infisical
prometheus|vauchi-prometheus|infra/monitoring/docker-compose.yml|prom/prometheus
grafana|vauchi-grafana|infra/monitoring/docker-compose.yml|grafana/grafana'

# ── One SSH round-trip for everything ───────────────────────────────
# APP lines:   APP|<proxy-service>|<name>|<image>|<revision-label>
# INFRA lines: INFRA|<container>|<image>|<state>
REMOTE=$(cat <<'REMOTE'
PROXY=$(docker exec kamal-proxy kamal-proxy list 2>/dev/null || true)
for psvc in vauchi-docs-web-production vauchi-cdn-web-production vauchi-landing-web-production vauchi-relay-web-production vauchi-ohttp-relay-web-production; do
  target=$(printf '%s\n' "$PROXY" | grep -E "^${psvc}[[:space:]]" | head -1 | tr -s ' ' | cut -d' ' -f4)
  cid=${target%%:*}
  if [ -z "$cid" ]; then printf 'APP|%s|-|-|-\n' "$psvc"; continue; fi
  info=$(docker inspect --format '{{.Name}}|{{.Config.Image}}|{{index .Config.Labels "org.opencontainers.image.revision"}}' "$cid" 2>/dev/null || printf -- '-|?|?')
  printf 'APP|%s|%s\n' "$psvc" "$info"
done
for c in vauchi-vaultwarden vauchi-infisical vauchi-prometheus vauchi-grafana; do
  info=$(docker inspect --format '{{.Config.Image}}|{{.State.Status}}' "$c" 2>/dev/null || printf -- '-|absent')
  printf 'INFRA|%s|%s\n' "$c" "$info"
done
REMOTE
)

echo ""
printf '  %sRunning state on the VPS (--running):%s\n' "$DIM" "$NC"
RAW=$(ssh -o StrictHostKeyChecking=accept-new "$SSH_TARGET" "$REMOTE" 2>/dev/null) || {
  printf '  %sCould not SSH %s — skipping running check.%s\n' "$YELLOW" "$SSH_TARGET" "$NC"
  exit 0
}

running_sha() {  # name image label -> full sha or UNKNOWN(reason)
  local name="$1" image="$2" label="$3"
  local ver="${name##*-production-}" tag="${image##*:}"
  if is_hex "$ver"   && [ "${#ver}"  = 40 ]; then printf '%s' "$ver";   return; fi
  if is_hex "$tag"   && [ "${#tag}"  = 40 ]; then printf '%s' "$tag";   return; fi
  if is_hex "$label";                        then printf '%s' "$label"; return; fi
  [ "$name" = "-" ] && { printf 'UNKNOWN(no-container)'; return; }
  printf 'UNKNOWN(%s)' "${tag:-untagged}"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── App reconciliation (parallel per service) ───────────────────────
i=0
while IFS='|' read -r svc host bipath repo psvc; do
  [ -n "$svc" ] || continue
  n=$i; i=$((i+1))
  (
    rline=$(printf '%s\n' "$RAW" | awk -F'|' -v s="$psvc" '$1=="APP" && $2==s {print; exit}')
    name=$(printf '%s' "$rline" | cut -d'|' -f3); name="${name#/}"
    image=$(printf '%s' "$rline" | cut -d'|' -f4)
    label=$(printf '%s' "$rline" | cut -d'|' -f5)
    run=$(running_sha "$name" "$image" "$label")
    served="n/a"
    if [ "$bipath" != "-" ]; then
      served=$(curl -sf --max-time 8 "https://${host}${bipath}" 2>/dev/null | jq -r '.sha // "none"' 2>/dev/null || echo "none")
    fi
    built=$(latest_built "$repo"); built="${built:-?}"
    color="$GREEN"; note="up-to-date"
    if [[ "$run" == UNKNOWN* ]]; then
      color="$YELLOW"; note="running unpinned/unknown — SHA-pin the deploy"
    elif is_hex "$served" && ! pref "$served" "$run"; then
      color="$RED"; note="SERVED != RUNNING (stale cache / misroute?)"
    elif is_hex "$built" && ! pref "$built" "$run"; then
      color="$RED"; note="behind newest build"
    fi
    printf '  %-11s %-14s %-14s %-14s %s%s%s\n' \
      "$svc" "$(disp "$run")" "$(disp "$served")" "$(disp "$built")" "$color" "$note" "$NC" > "$TMP/app.$n"
  ) &
done <<< "$APP_MANIFEST"
wait

printf '  %sapp services (commit SHA):%s\n' "$DIM" "$NC"
printf '  %-11s %-14s %-14s %-14s %s\n' "SERVICE" "RUNNING" "SERVED" "BUILT" "NOTE"
printf '  %s\n' "$(printf '%*s' 74 '' | tr ' ' '-')"
f=0
while [ "$f" -lt "$i" ]; do cat "$TMP/app.$f" 2>/dev/null; f=$((f+1)); done

# ── Infra reconciliation (running image tag vs config pin) ──────────
echo ""
printf '  %sinfra services (image tag vs config pin):%s\n' "$DIM" "$NC"
printf '  %-11s %-22s %-16s %s\n' "SERVICE" "RUNNING TAG" "PINNED" "NOTE"
printf '  %s\n' "$(printf '%*s' 74 '' | tr ' ' '-')"
while IFS='|' read -r svc container compose repo; do
  [ -n "$svc" ] || continue
  iline=$(printf '%s\n' "$RAW" | awk -F'|' -v c="$container" '$1=="INFRA" && $2==c {print; exit}')
  image=$(printf '%s' "$iline" | cut -d'|' -f3)
  state=$(printf '%s' "$iline" | cut -d'|' -f4)
  run_tag="${image##*:}"; [ "$image" = "-" ] && run_tag="absent"
  pinned=$(grep -oE "${repo}:[^[:space:]\"']+" "$ROOT/_private/$compose" 2>/dev/null | head -1)
  pin_tag="${pinned##*:}"; pin_tag="${pin_tag:-?}"
  color="$GREEN"; note="matches pin"
  if [ "$image" = "-" ] || [ "$state" != "running" ]; then
    color="$RED"; note="container ${state:-missing}"
  elif [ "$run_tag" = "latest" ]; then
    color="$YELLOW"; note="running mutable :latest (pin is $pin_tag) — redeploy to pin"
  elif [ "$run_tag" != "$pin_tag" ]; then
    color="$YELLOW"; note="running $run_tag != pin $pin_tag — redeploy to apply pin"
  fi
  printf '  %-11s %-22.22s %-16s %s%s%s\n' "$svc" "$run_tag" "$pin_tag" "$color" "$note" "$NC"
done <<< "$INFRA_MANIFEST"
