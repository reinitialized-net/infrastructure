#!/usr/bin/env bash
# Update all deployable NixOS hosts
set -euo pipefail

VALID_HOSTS="@validHosts@"
FLAKE_PATH="${FLAKE_PATH:-/home/develop/projects/reinitialized.net/infrastructure}"
SSH_USER="rnetadmin"
NIXOS_REBUILD_FLAGS=()

if [[ -n "${INFRA_SECRETS_DIR:-}" ]]; then
  NIXOS_REBUILD_FLAGS+=(--impure)
fi

get_host_ip() {
  local host="$1"
  case "$host" in
@hostIpCases@
    *) echo "ERROR: Unknown host '$host'" >&2; return 1 ;;
  esac
}

# Guard: fleet update includes remote hosts, don't run as root/sudo
if [[ $(id -u) -eq 0 ]]; then
  echo "ERROR: Do not use sudo for updateInfra."
  echo "  Remote hosts are deployed via SSH as '$SSH_USER' with --sudo."
  echo "  Running as root breaks SSH key authentication."
  echo "  The local devenv rebuild will use sudo internally."
  echo ""
  echo "Usage: updateInfra"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  NixOS Fleet Update                                          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "  Hosts:   $VALID_HOSTS"
echo "  Action:  nixos-rebuild switch"
echo "  User:    $SSH_USER"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

FAILED_HOSTS=()
SUCCESS_HOSTS=()

for host in $VALID_HOSTS; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "→ Updating: $host"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [[ "$host" == "devenv" ]]; then
    echo "  (local host - building and activating directly)"
    if sudo INFRA_SECRETS_DIR="${INFRA_SECRETS_DIR:-}" nixos-rebuild switch "${NIXOS_REBUILD_FLAGS[@]}" --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$host"; then
      SUCCESS_HOSTS+=("$host")
      echo "✓ $host updated successfully"
    else
      FAILED_HOSTS+=("$host")
      echo "✗ $host update failed"
    fi
  else
    TARGET_IP=$(get_host_ip "$host") || {
      echo "✗ Skipping $host - no IP address configured"
      FAILED_HOSTS+=("$host")
      continue
    }
    
    echo "  (remote: $TARGET_IP - building on devenv, deploying to target)"
    if nixos-rebuild switch "${NIXOS_REBUILD_FLAGS[@]}" --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$host" \
        --target-host "$SSH_USER@$TARGET_IP" \
        --sudo; then
      SUCCESS_HOSTS+=("$host")
      echo "✓ $host updated successfully"
    elif ssh "$SSH_USER@$TARGET_IP" 'sudo systemctl restart dbus.service && sleep 2 && sudo systemctl restart systemd-logind.service' 2>/dev/null && \
         nixos-rebuild switch "${NIXOS_REBUILD_FLAGS[@]}" --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$host" \
           --target-host "$SSH_USER@$TARGET_IP" \
           --sudo; then
      SUCCESS_HOSTS+=("$host")
      echo "✓ $host updated successfully (after DBus recovery)"
    else
      FAILED_HOSTS+=("$host")
      echo "✗ $host update failed"
    fi
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  UPDATE SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ${#SUCCESS_HOSTS[@]} -gt 0 ]]; then
  echo "✓ Successful: ${SUCCESS_HOSTS[*]}"
fi

if [[ ${#FAILED_HOSTS[@]} -gt 0 ]]; then
  echo "✗ Failed:     ${FAILED_HOSTS[*]}"
  exit 1
fi

echo ""
echo "All hosts updated successfully!"
