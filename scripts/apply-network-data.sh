#!/bin/bash
# Custom IPA Network Configuration Script
# This script is called early in the IPA boot process to configure networking

set -euo pipefail

# Logging setup
LOG_FILE="/var/log/ipa-network-config.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting IPA network configuration"

# Wait for devices to be ready
echo "$(date): Waiting for network devices to be ready..."
sleep 5

# Check if config drive exists
if [ ! -b "/dev/sr0" ]; then
    echo "$(date): ERROR: Config drive /dev/sr0 not found"
    exit 1
fi

echo "$(date): Config drive found at /dev/sr0"

# Run the Python network configuration script
echo "$(date): Running network configuration script"
if python3 /usr/local/bin/network-config.py; then
    echo "$(date): Network configuration completed successfully"
    
    # Test network connectivity
    echo "$(date): Testing network connectivity..."
    
    # Get the configured IP addresses
    echo "$(date): Configured IP addresses:"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    
    # Show routing table
    echo "$(date): Routing table:"
    ip route show
    
    # Try to ping gateway (if we can determine it)
    GATEWAY=$(ip route show default | awk '/default/ {print $3}' | head -1)
    if [ -n "$GATEWAY" ]; then
        echo "$(date): Testing connectivity to gateway $GATEWAY"
        if ping -c 3 -W 5 "$GATEWAY"; then
            echo "$(date): Gateway connectivity test successful"
        else
            echo "$(date): WARNING: Gateway connectivity test failed"
        fi
    fi
    
    echo "$(date): Network configuration script completed"
else
    echo "$(date): ERROR: Network configuration script failed"
    exit 1
fi
