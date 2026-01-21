{
  lib,
  pkgs,
  config,
  ...
}: let
  meshEnabled = config.services.mesh-network.enable or false;
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

        if [ -f /etc/mesh-network/status.sh ]; then
          /etc/mesh-network/status.sh
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
        ${wireguard-tools}/bin/wg show wg-mesh | grep 'allowed ips' | awk '{print $3}' | cut -d'/' -f1 | while read ip; do
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

      (writeScriptBin "mesh-docker-example" ''
        #!/usr/bin/env bash
        # Generate example docker-compose.yml for mesh networking
        set -euo pipefail

        cat <<'EOF'
# Example docker-compose.yml using mesh network

services:
  web:
    image: nginx:alpine
    networks:
      - mesh
    environment:
      - MESH_NODE_IP=10.100.0.X  # Replace X with node ID
    # The container can now access other nodes via their mesh IPs:
    # - Node 1: 10.100.0.1
    # - Node 2: 10.100.0.2
    # etc.

  app:
    image: your-app:latest
    networks:
      - mesh
    environment:
      # Connect to services on other mesh nodes
      - DATABASE_HOST=10.100.0.1  # Example: DB on node 1
      - CACHE_HOST=10.100.0.2     # Example: Redis on node 2

networks:
  mesh:
    name: mesh-net
    external: true  # Use the mesh-net created by NixOS

# To use mesh network environment variables:
# Source them in your compose file:
#   env_file: /etc/mesh-network/docker-compose.env
EOF

        echo
        echo "💡 TIP: You can source mesh configuration with:"
        echo "   env_file: /etc/mesh-network/docker-compose.env"
      '')
    ]
  );
}
