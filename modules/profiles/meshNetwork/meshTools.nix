{
  lib,
  pkgs,
  config,
  ...
}: let
  meshEnabled = config.services.meshNetwork.enable or false;
in {
  environment.systemPackages = lib.mkIf meshEnabled (
    with pkgs; [
      (writeScriptBin "mesh-keygen" ''
        #!/usr/bin/env bash
        # Generate Wireguard key pair for mesh networking
        set -euo pipefail

        echo "=== Wireguard Mesh Key Generator ==="
        echo

        PRIVATE_KEY=$(${wireguard-tools}/bin/wg genkey)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | ${wireguard-tools}/bin/wg pubkey)

        echo "Private Key: $PRIVATE_KEY"
        echo "Public Key:  $PUBLIC_KEY"
        echo
        echo "⚠️  IMPORTANT: Store the private key securely!"
        echo "   Add the private key to: modules/secrets/mesh.nix"
        echo "   Share the public key with other mesh nodes"
        echo
      '')

      (writeScriptBin "mesh-status" ''
        #!/usr/bin/env bash
        # Show mesh network status
        set -euo pipefail

        if [ -f /etc/meshNetwork/status.sh ]; then
          /etc/meshNetwork/status.sh
        else
          echo "Mesh network is not enabled or not properly configured."
          exit 1
        fi
      '')

      (writeScriptBin "mesh-test" ''
        #!/usr/bin/env bash
        # Test mesh connectivity to all peers
        set -euo pipefail

        echo "=== Mesh Network Connectivity Test ==="
        echo

        if [ ! -d /sys/class/net/wg-mesh ]; then
          echo "Error: wg-mesh interface not found"
          exit 1
        fi

        # Get all mesh IPs from Wireguard config
        sudo ${wireguard-tools}/bin/wg show wg-mesh | grep 'allowed ips' | awk '{print $3}' | cut -d'/' -f1 | while read ip; do
          echo -n "Testing $ip ... "
          if ${iputils}/bin/ping -c 3 -W 2 "$ip" > /dev/null 2>&1; then
            echo "✓ OK ($(${iputils}/bin/ping -c 1 -W 1 "$ip" | grep 'time=' | sed 's/.*time=\([^ ]*\).*/\1/'))"
          else
            echo "✗ FAILED"
          fi
        done

        echo
        echo "=== Bandwidth Test (iperf3) ==="
        echo "To test bandwidth between nodes:"
        echo "  On receiver: iperf3 -s"
        echo "  On sender:   iperf3 -c <mesh-ip>"
      '')
    ]
  );
}
