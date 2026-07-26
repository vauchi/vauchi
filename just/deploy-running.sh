#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Deep running-state check for `just deploy-check --running`.
#
# deploy-check answers "is a newer build available than what's deployed?" from
# served build-info + the registry — it never asks the host what it is ACTUALLY
# running. This does: it SSHes the VPS, resolves each kamal-proxy-ACTIVE target
# container (the one receiving traffic, per Codex — not an arbitrary one), and
# reconciles what that container is RUNNING against what the public host SERVES
# and the newest successful build. A mutable :latest deploy is reported UNKNOWN,
# never guessed. Informational: it prints a section but does not change the
# deploy-check exit code.
#
# Usage: deploy-running.sh <ssh-user@host>

set -uo pipefail
SSH_TARGET="${1:?usage: deploy-running.sh <user@host>}"

if [ -t 1 ]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; DIM=$'\e[2m'; NC=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""; DIM=""; NC=""
fi

is_hex() { printf '%s' "${1:-}" | grep -qE '^[0-9a-f]{7,40}$'; }
# prefix-tolerant SHA equality (a short sha vs its full form still matches)
pref()   { case "$2" in "$1"*) return 0 ;; esac; case "$1" in "$2"*) return 0 ;; esac; return 1; }
disp()   { if is_hex "$1"; then printf '%.12s' "$1"; else printf '%s' "$1"; fi; }
latest_built() {
  glab api "projects/vauchi%2F${1}/pipelines?ref=main&status=success&per_page=1" 2>/dev/null \
    | jq -r '.[0].sha // empty' 2>/dev/null
}

# svc | host | build-info-path (- if none) | repo | proxy-service
MANIFEST='docs|docs.vauchi.app|/build-info.json|docs|vauchi-docs-web-production
cdn|cdn.vauchi.app|/build-info.json|website|vauchi-cdn-web-production
landing|vauchi.app|/build-info.json|website|vauchi-landing-web-production
relay|relay.vauchi.app|-|relay|vauchi-relay-web-production
ohttp|ohttp.vauchi.app|-|ohttp-relay|vauchi-ohttp-relay-web-production'

# One SSH round-trip. Resolve each proxy-active target container and read its
# identity. `kamal-proxy list` columns: Service Host Path Target State TLS, so
# Target (=<container-id>:<port>) is the 4th field (confirmed on the host).
REMOTE=$(cat <<'REMOTE'
PROXY=$(docker exec kamal-proxy kamal-proxy list 2>/dev/null || true)
for psvc in vauchi-docs-web-production vauchi-cdn-web-production vauchi-landing-web-production vauchi-relay-web-production vauchi-ohttp-relay-web-production; do
  target=$(printf '%s\n' "$PROXY" | grep -E "^${psvc}[[:space:]]" | head -1 | tr -s ' ' | cut -d' ' -f4)
  cid=${target%%:*}
  if [ -z "$cid" ]; then printf '%s|-|-|-\n' "$psvc"; continue; fi
  info=$(docker inspect --format '{{.Name}}|{{.Config.Image}}|{{index .Config.Labels "org.opencontainers.image.revision"}}' "$cid" 2>/dev/null || printf -- '-|?|?')
  printf '%s|%s\n' "$psvc" "$info"
done
REMOTE
)

echo ""
printf '  %sProxy-active containers on the VPS (--running):%s\n' "$DIM" "$NC"
RAW=$(ssh -o StrictHostKeyChecking=accept-new "$SSH_TARGET" "$REMOTE" 2>/dev/null) || {
  printf '  %sCould not SSH %s — skipping running check.%s\n' "$YELLOW" "$SSH_TARGET" "$NC"
  exit 0
}

printf '  %-11s %-14s %-14s %-14s %s\n' "SERVICE" "RUNNING" "SERVED" "BUILT" "NOTE"
printf '  %s\n' "$(printf '%*s' 74 '' | tr ' ' '-')"

running_sha() {  # name image label -> full sha or UNKNOWN(reason)
  local name="$1" image="$2" label="$3"
  local ver="${name##*-production-}" tag="${image##*:}"
  if is_hex "$ver"   && [ "${#ver}"  = 40 ]; then printf '%s' "$ver";   return; fi
  if is_hex "$tag"   && [ "${#tag}"  = 40 ]; then printf '%s' "$tag";   return; fi
  if is_hex "$label";                        then printf '%s' "$label"; return; fi
  [ "$name" = "-" ] && { printf 'UNKNOWN(no-container)'; return; }
  printf 'UNKNOWN(%s)' "${tag:-untagged}"
}

while IFS='|' read -r svc host bipath repo psvc; do
  [ -n "$svc" ] || continue
  rline=$(printf '%s\n' "$RAW" | awk -F'|' -v s="$psvc" '$1==s {print; exit}')
  name=$(printf '%s' "$rline" | cut -d'|' -f2); name="${name#/}"
  image=$(printf '%s' "$rline" | cut -d'|' -f3)
  label=$(printf '%s' "$rline" | cut -d'|' -f4)

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
    "$svc" "$(disp "$run")" "$(disp "$served")" "$(disp "$built")" "$color" "$note" "$NC"
done <<< "$MANIFEST"
