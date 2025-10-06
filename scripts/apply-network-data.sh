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

# Find config drive - try multiple possible locations
CONFIG_DRIVE=""
for device in /dev/sr0 /dev/sr1 /dev/cdrom /dev/dvd; do
    if [ -b "$device" ]; then
        echo "$(date): Found potential config drive at $device"
        CONFIG_DRIVE="$device"
        break
    fi
done

if [ -z "$CONFIG_DRIVE" ]; then
    echo "$(date): ERROR: No config drive found. Available block devices:"
    ls -la /dev/sr* /dev/cd* /dev/dvd* 2>/dev/null || echo "No optical devices found"
    echo "$(date): All block devices:"
    lsblk
    exit 1
fi

echo "$(date): Using config drive at $CONFIG_DRIVE"

# Mount the config drive (if not already mounted)
MOUNT_POINT="/mnt/config"
mkdir -p "$MOUNT_POINT"

if mount | grep -q "$MOUNT_POINT"; then
    echo "$(date): Config drive already mounted at $MOUNT_POINT"
elif mount "$CONFIG_DRIVE" "$MOUNT_POINT"; then
    echo "$(date): Config drive mounted at $MOUNT_POINT"
else
    echo "$(date): ERROR: Failed to mount config drive $CONFIG_DRIVE"
    exit 1
fi

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
