#!/usr/bin/env bash
# Rebuild a remote NixOS host using nixos-rebuild over SSH
set -euo pipefail

VALID_HOSTS="@validHosts@"
FLAKE_PATH="/home/develop/projects/reinitialized.net/infrastructure"
SSH_USER="rnetadmin"

usage() {
  echo "Usage: rebuildHost TARGET [--boot]"
  echo ""
  echo "Rebuild a NixOS host using nixos-rebuild over SSH."
  echo ""
  echo "Arguments:"
  echo "  TARGET     The hostname to rebuild (must exist in hosts/)"
  echo "  --boot     Use 'boot' instead of 'switch' (activates on next reboot)"
  echo ""
  echo "Valid targets: $VALID_HOSTS"
  exit 1
}

get_host_ip() {
  local host="$1"
  case "$host" in
@hostIpCases@
    *) echo "ERROR: Unknown host '$host'" >&2; return 1 ;;
  esac
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
fi

TARGET="$1"
ACTION="switch"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --boot)
      ACTION="boot"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown option '$1'" >&2
      usage
      ;;
  esac
done

# Validate target exists
if ! echo "$VALID_HOSTS" | grep -qw "$TARGET"; then
  echo "ERROR: Invalid target '$TARGET'"
  echo "Valid targets: $VALID_HOSTS"
  exit 1
fi

# Check that host config file exists
if [[ ! -f "$FLAKE_PATH/hosts/$TARGET.nix" ]] && [[ ! -d "$FLAKE_PATH/hosts/$TARGET" ]]; then
  echo "ERROR: Host configuration not found: $FLAKE_PATH/hosts/$TARGET.nix"
  exit 1
fi

# Guard: don't run as root/sudo for remote targets (SSH keys won't work)
if [[ "$TARGET" != "devenv" && $(id -u) -eq 0 ]]; then
  echo "ERROR: Do not use sudo for remote targets."
  echo "  rebuildHost uses SSH as '$SSH_USER' and --sudo on the remote side."
  echo "  Running as root breaks SSH key authentication."
  echo ""
  echo "Usage: rebuildHost $TARGET $([[ \"$ACTION\" == \"boot\" ]] && echo '--boot' || true)"
  exit 1
fi

# Check if target is local (devenv) or remote
if [[ "$TARGET" == "devenv" ]]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  NixOS Local Rebuild                                         ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "  Target:  $TARGET (local)"
  echo "  Action:  nixos-rebuild $ACTION"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Execute local nixos-rebuild
  echo "→ Rebuilding local system..."
  sudo nixos-rebuild $ACTION --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$TARGET"
else
  # Get target IP for remote host
  TARGET_IP=$(get_host_ip "$TARGET")
  
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  NixOS Remote Rebuild                                        ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "  Target:  $TARGET ($TARGET_IP)"
  echo "  Action:  nixos-rebuild $ACTION"
  echo "  User:    $SSH_USER"
  echo "  Mode:    Build on devenv, deploy to target"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Execute nixos-rebuild from devenv with --target-host
  echo "→ Building and deploying to $TARGET_IP as $SSH_USER..."
  if nixos-rebuild $ACTION --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$TARGET" \
    --target-host "$SSH_USER@$TARGET_IP" \
    --sudo; then
    :
  elif [[ "$ACTION" == "switch" ]]; then
    echo ""
    echo "⚠ Switch failed — attempting DBus recovery on $TARGET..."
    echo "  (This can happen when daemon-reexec disconnects PID 1 from the system bus)"
    echo ""

    # Recover dbus + logind on the remote host
    if ssh "$SSH_USER@$TARGET_IP" 'sudo systemctl restart dbus.service && sleep 2 && sudo systemctl restart systemd-logind.service' 2>/dev/null; then
      echo "→ DBus recovered, retrying switch..."
      nixos-rebuild $ACTION --cores 6 --max-jobs 12 --flake "path:$FLAKE_PATH#$TARGET" \
        --target-host "$SSH_USER@$TARGET_IP" \
        --sudo
    else
      echo "✗ DBus recovery failed on $TARGET"
      exit 1
    fi
  else
    exit 1
  fi
fi

echo ""
echo "✓ Rebuild completed successfully for $TARGET"
