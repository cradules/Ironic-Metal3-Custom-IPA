# Custom IPA Image for DHCP-less Environments

This directory contains the configuration and scripts to build a custom Ironic Python Agent (IPA) image that can configure network settings from config drive without requiring DHCP.

## Problem Statement

In environments without DHCP servers, the standard IPA cannot obtain network configuration automatically during the deployment phase. This prevents IPA from communicating with the Ironic API server, causing deployment failures.

## Solution Overview: Single Image, Multiple Nodes

The custom IPA image we create is **generic and reusable**. Each node gets its specific network configuration via the **config drive** that your Terraform already creates.

### Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Custom IPA    │    │   Config Drive   │    │  Final Result   │
│     Image       │    │  (per-node)      │    │   (per-node)    │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ • Base IPA      │    │ • network_data   │    │ • Node with     │
│ • Network       │ +  │   - server001:   │ =  │   server001 IP  │
│   config script │    │     203.0.113.10 │    │   and bonds     │
│ • Bond support  │    │   - server002:   │    │                 │
│ • Generic logic │    │     203.0.113.11 │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### How Single Image Works for Multiple Nodes

**1. Single Custom IPA Image Contains:**
```bash
# Generic network configuration script
/usr/local/bin/apply-network-data.sh
# Reads from: /dev/sr0 (config drive)
# Applies: whatever network_data.json specifies
```

**2. Server001 Gets Config Drive With:**
```json
{
  "networks": [
    {
      "id": "public",
      "type": "ipv4",
      "ip_address": "203.0.113.10",
      "netmask": "255.255.255.0",
      "gateway": "203.0.113.1"
    }
  ],
  "links": [
    {
      "id": "bond0",
      "type": "bond",
      "ethernet_mac_address": "7c:c2:55:6e:90:44",
      "bond_links": ["eno1", "eno2"],
      "bond_mode": "802.3ad"
    }
  ]
}
```

**3. Server002 Gets Different Config Drive:**
```json
{
  "networks": [
    {
      "id": "public",
      "type": "ipv4",
      "ip_address": "203.0.113.11",
      "netmask": "255.255.255.0",
      "gateway": "203.0.113.1"
    }
  ],
  "links": [
    {
      "id": "bond0",
      "type": "bond",
      "ethernet_mac_address": "a0:36:9f:2e:3c:c0",
      "bond_links": ["eno1", "eno2"],
      "bond_mode": "802.3ad"
    }
  ]
}
```

### Step-by-Step Process

1. **Single Custom IPA Image**: Built once, used for all nodes
2. **Per-Node Configuration**: Each node gets its specific network config via **config drive**
3. **Dynamic Application**: IPA reads the config drive and applies node-specific settings

### Your Current Terraform Integration

Your existing Terraform code **already creates per-node config drives** with different:
- IP addresses (`each.value.network_config.public_network.ip_address`)
- MAC addresses (`each.value.network_config.private_bond.interface1_mac`)
- Network settings per host

The custom IPA image will read these existing configurations and apply them automatically.

## Key Benefits

✅ **Single Image**: Build once, use everywhere
✅ **Per-Node Config**: Each node gets its specific network settings
✅ **No Rebuilds**: Add new nodes without touching the image
✅ **Terraform Integration**: Works with your existing per-host configurations
✅ **Scalable**: Works for 3 nodes or 300 nodes

## Files

- `Dockerfile`: Custom IPA image definition
- `build.sh`: Script to build the custom IPA image
- `extract-images.sh`: Script to extract kernel and ramdisk for Ironic
- `scripts/`: Network configuration scripts
  - `apply-network-data.sh`: Main network configuration script
  - `network-config.py`: Python helper for parsing network_data.json
  - `ipa-network-init.service`: Systemd service for early network setup

## Usage

### 1. Build the Custom Image

```bash
cd 2-cluster-api/ironic/custom-ipa
chmod +x build.sh extract-images.sh
./build.sh
```

### 2. Extract Kernel and Ramdisk

```bash
./extract-images.sh
```

### 3. Deploy to Ironic

```bash
# Copy images to Ironic HTTP server
sudo cp output/ironic-python-agent.kernel /opt/ironic/data/html/images/
sudo cp output/ironic-python-agent.initramfs /opt/ironic/data/html/images/

# Restart Ironic to use new images
cd ../
sudo docker compose restart ironic
```

## How It Works

### The Custom IPA Script Logic

```bash
#!/bin/bash
# This runs on EVERY node, but reads different config per node

# Mount config drive (same for all nodes)
mount /dev/sr0 /mnt/config

# Read THIS node's specific network config
NETWORK_CONFIG=$(cat /mnt/config/openstack/latest/network_data.json)

# Apply THIS node's specific settings
configure_bonds_from_json "$NETWORK_CONFIG"
configure_ips_from_json "$NETWORK_CONFIG"
configure_routes_from_json "$NETWORK_CONFIG"

# Now IPA can communicate with Ironic using THIS node's network
```

### Deployment Flow

1. **Server boots custom IPA image** (same image for all nodes)
2. **`ipa-network-init.service` runs early** in boot process
3. **Script mounts config drive** and reads THIS node's network_data.json
4. **Network configuration is applied** (bonds, IPs, routes) specific to THIS node
5. **IPA starts with working network** connectivity using THIS node's settings
6. **IPA communicates with Ironic API** to complete deployment

### What Makes This Work

- **Generic Image**: Contains logic to handle any network configuration
- **Per-Node Data**: Config drive provides node-specific network settings
- **Dynamic Configuration**: Script reads and applies whatever is in the config drive
- **Terraform Integration**: Uses existing per-host network configurations

### Configuration Details

The custom IPA image automatically:

- Mounts config drive from `/dev/sr0`
- Reads `/mnt/config/openstack/latest/network_data.json`
- Configures network interfaces based on MAC addresses
- Sets up bond interfaces with LACP mode
- Applies IP addresses and routes
- Tests connectivity

## Network Data Format

The image expects standard OpenStack `network_data.json` format:

```json
{
  "links": [
    {
      "id": "private-int1",
      "type": "phy",
      "ethernet_mac_address": "7c:c2:55:6e:90:44",
      "mtu": 9000
    },
    {
      "id": "aggi",
      "type": "bond",
      "bond_links": ["private-int1", "private-int2"],
      "bond_mode": "802.3ad",
      "mtu": 9000
    }
  ],
  "networks": [
    {
      "id": "private_network",
      "link": "aggi",
      "type": "ipv4",
      "ip_address": "10.158.175.249",
      "netmask": "255.255.255.254",
      "routes": [
        {
          "network": "10.0.0.0",
          "netmask": "255.0.0.0",
          "gateway": "10.158.175.248"
        }
      ]
    }
  ]
}
```

## Logging

Network configuration logs are written to:
- `/var/log/ipa-network-config.log`
- Console output (visible via BMC console)

## Troubleshooting

### 1. Check if Custom Image is Being Used

```bash
# Via console during IPA boot, check for custom service
systemctl status ipa-network-init.service
```

### 2. Check Network Configuration Logs

```bash
# Via console
cat /var/log/ipa-network-config.log
journalctl -u ipa-network-init.service
```

### 3. Verify Network Configuration

```bash
# Via console
ip addr show
ip route show
```

### 4. Test Connectivity

```bash
# Via console
ping <ironic-api-ip>
curl http://<ironic-api-ip>:6385/v1/
```

## Integration with Existing Setup

This custom IPA image works with your existing:
- Metal3 BareMetalHost configurations
- `network_interface: noop` setting
- Config drive generation from Terraform
- Bond interface configurations

No changes needed to your Terraform configurations - just replace the IPA images and the network configuration will work automatically.

## Summary

This approach eliminates the DHCP dependency while maintaining full compatibility with existing Metal3 configurations and allowing unlimited scalability without image rebuilds. The key insight is that **one generic image can handle infinite node configurations** by reading the per-node config drive data that Terraform already generates.

### What This Solves

- ✅ **No DHCP Required**: IPA reads network config from config drive instead
- ✅ **Works with `noop`**: No changes needed to your Ironic network interface setting
- ✅ **Bond Support**: Handles your complex LACP bond configurations
- ✅ **Automatic**: Runs before IPA starts, so network is ready when IPA needs it
- ✅ **Compatible**: Works with your existing Terraform Metal3 configurations
- ✅ **Scalable**: Single image works for any number of nodes with different configurations

### Files Reference

- `Dockerfile`: Custom IPA image definition
- `scripts/network-config.py`: Python script for network configuration
- `scripts/apply-network-data.sh`: Shell wrapper script
- `scripts/ipa-network-init.service`: Systemd service definition
- `build.sh`: Build script for the custom image
- `extract-images.sh`: Extract kernel/ramdisk from built image
