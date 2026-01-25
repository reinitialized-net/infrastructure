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
sudo @wireguard-tools@/bin/wg show wg-mesh | grep 'allowed ips' | awk '{print $3}' | cut -d'/' -f1 | while read ip; do
    echo -n "Testing $ip ... "
    if @iputils@/bin/ping -c 3 -W 2 "$ip" > /dev/null 2>&1; then
    echo "✓ OK ($(@iputils@/bin/ping -c 1 -W 1 "$ip" | grep 'time=' | sed 's/.*time=\([^ ]*\).*/\1/'))"
    else
    echo "✗ FAILED"
    fi
done

echo
echo "=== Bandwidth Test (iperf3) ==="
echo "To test bandwidth between nodes:"
echo "  On receiver: iperf3 -s"
echo "  On sender:   iperf3 -c <mesh-ip>"