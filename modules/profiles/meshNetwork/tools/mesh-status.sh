#!/usr/bin/env bash
# Show mesh network status
set -euo pipefail

if [ -f /etc/meshNetwork/status.sh ]; then
    /etc/meshNetwork/status.sh
else
    echo "Mesh network is not enabled or not properly configured."
    exit 1
fi