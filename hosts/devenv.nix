{
  self,
  pkgs,
  lib,
  ...
}: let
  # Import mesh topology for host IP resolution
  meshTopology = import "${self}/modules/profiles/meshNetwork/meshTopology.nix" { inherit lib; };
  
  # Get list of valid hostnames from mesh topology
  validHosts = builtins.attrNames meshTopology.nodes;
  validHostsStr = lib.concatStringsSep " " validHosts;
  
  # Create a lookup table of hostname -> IP address (extracted from endpoint)
  # The endpoint format is "IP:PORT", we extract just the IP
  hostIpMap = lib.mapAttrs (name: node: 
    if node ? endpoint 
    then lib.head (lib.splitString ":" node.endpoint)
    else null
  ) meshTopology.nodes;
  
  # Generate case statements for host IP lookup
  hostIpCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: ip: 
      if ip != null 
      then "      ${name}) echo \"${ip}\" ;;"
      else "      ${name}) echo \"ERROR: Host '${name}' has no endpoint configured\" >&2; return 1 ;;"
    ) hostIpMap
  );

  # rebuildHost script
  rebuildHostScript = pkgs.writeScriptBin "rebuildHost" ''
    #!${pkgs.bash}/bin/bash
    # Rebuild a remote NixOS host using nixos-rebuild over SSH
    set -euo pipefail

    VALID_HOSTS="${validHostsStr}"
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
    ${hostIpCases}
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
    if [[ ! -f "$FLAKE_PATH/hosts/$TARGET.nix" ]]; then
      echo "ERROR: Host configuration file not found: $FLAKE_PATH/hosts/$TARGET.nix"
      exit 1
    fi

    # Get target IP
    TARGET_IP=$(get_host_ip "$TARGET")
    
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  NixOS Remote Rebuild                                        ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "  Target:  $TARGET ($TARGET_IP)"
    echo "  Action:  nixos-rebuild $ACTION"
    echo "  User:    $SSH_USER"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Execute nixos-rebuild
    echo "→ Connecting to $TARGET_IP as $SSH_USER..."
    ${pkgs.openssh}/bin/ssh -t "$SSH_USER@$TARGET_IP" \
      "sudo nixos-rebuild $ACTION --flake 'path:$FLAKE_PATH#$TARGET'"
    
    echo ""
    echo "✓ Rebuild completed successfully for $TARGET"
  '';

  # updateAll script
  updateAllScript = pkgs.writeScriptBin "updateAll" ''
    #!${pkgs.bash}/bin/bash
    # Update all NixOS hosts defined in hosts/ directory
    set -euo pipefail

    VALID_HOSTS="${validHostsStr}"
    FLAKE_PATH="/home/develop/projects/reinitialized.net/infrastructure"
    SSH_USER="rnetadmin"
    CURRENT_HOST=$(hostname)

    get_host_ip() {
      local host="$1"
      case "$host" in
    ${hostIpCases}
        *) echo "ERROR: Unknown host '$host'" >&2; return 1 ;;
      esac
    }

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
      
      if [[ "$host" == "$CURRENT_HOST" ]]; then
        echo "  (local host - running directly)"
        if sudo nixos-rebuild switch --flake "path:$FLAKE_PATH#$host"; then
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
        
        echo "  (remote: $TARGET_IP)"
        if ${pkgs.openssh}/bin/ssh -t "$SSH_USER@$TARGET_IP" \
            "sudo nixos-rebuild switch --flake 'path:$FLAKE_PATH#$host'"; then
          SUCCESS_HOSTS+=("$host")
          echo "✓ $host updated successfully"
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
    
    if [[ ''${#SUCCESS_HOSTS[@]} -gt 0 ]]; then
      echo "✓ Successful: ''${SUCCESS_HOSTS[*]}"
    fi
    
    if [[ ''${#FAILED_HOSTS[@]} -gt 0 ]]; then
      echo "✗ Failed:     ''${FAILED_HOSTS[*]}"
      exit 1
    fi
    
    echo ""
    echo "All hosts updated successfully!"
  '';

in {
  imports = [
    ((import "${self}/library/makeUser.nix" {}) {
      username = "develop";
      group = "develop";
      homePermissions = "0700";
      extraUserAttrs = {
        extraGroups = [ "docker" "wheel" ];
        shell = pkgs.bashInteractive;
        isNormalUser = true;

        initialPassword = "!";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEgNNIkOFenuf9S6sy5heFeysErwMgfGD//r4jWgbg/E develop"
        ];
      };
    })
  ];
  # Networking Configuration
  networking = {
    hostName = "devenv";
    useDHCP = false;
  };
  systemd.network.networks = {
    "eth0" = {
      address = [
        "10.1.200.2/24"
      ];
      dns = [
        "10.1.11.2"
        "10.1.11.3"
      ];
      ntp = [
        "10.1.200.1"
      ];
      gateway = [
        "10.1.200.1"
      ];
      matchConfig.Path = "pci-0000:06:12.0";
    };
  };
  # Configure Services
  services = {
    vscode-server.enable = true;
    meshNetwork = {
      enable = true;
      nodeId = 1;
    };
  };
  # Install development tools
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    btop
    fastfetch

    nmap
    dig
    coreutils
    pciutils
    usbutils

    nixd
    nixfmt-rfc-style

    # DevEnv-exclusive fleet management tools
    rebuildHostScript
    updateAllScript
  ];
}