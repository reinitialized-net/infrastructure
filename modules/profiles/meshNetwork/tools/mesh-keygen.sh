#!/usr/bin/env bash
# Generate Wireguard key pair for mesh networking
set -euo pipefail

echo "=== Wireguard Mesh Key Generator ==="
echo

PRIVATE_KEY=$(@wireguard-tools@/bin/wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | @wireguard-tools@/bin/wg pubkey)

echo "Private Key: $PRIVATE_KEY"
echo "Public Key:  $PUBLIC_KEY"
echo
echo "⚠️  IMPORTANT: Store the private key securely!"
echo "   Add the private key to: modules/secrets/mesh.nix"
echo "   Share the public key with other mesh nodes"
echo