# Custom IPA Deployment Guide

This guide will teach you how to build, deploy, and test the custom IPA image for DHCP-less environments.

## Prerequisites

Before starting, ensure you have:

- ✅ Docker installed and running
- ✅ Access to your Ironic server (SSH or local access)
- ✅ Sudo privileges on the Ironic server
- ✅ Your existing Metal3/Ironic setup working with DHCP

## Quick Deployment (Automated)

### Option 1: Integrated with Ironic Deployment (Recommended)

If you're using the integrated approach, the custom IPA is automatically built and deployed when your Ironic server is created via Terraform user data. No manual steps needed!

### Option 2: Manual Deployment

If you need to deploy manually or update an existing Ironic server:

```bash
# Download and deploy custom IPA
cd /tmp
curl -L https://github.com/cradules/Ironic-Metal3-Custom-IPA/archive/main.tar.gz | tar -xz
cd Ironic-Metal3-Custom-IPA-main
chmod +x deploy.sh
./deploy.sh
```

This script will:
1. Build the custom IPA image
2. Extract kernel and ramdisk
3. Backup existing IPA images
4. Deploy new images to Ironic
5. Restart Ironic
6. Verify deployment

## Manual Deployment (Step by Step)

If you prefer to understand each step or need to troubleshoot:

### Step 1: Build the Custom IPA Image

```bash
cd 2-cluster-api/ironic/custom-ipa

# Make scripts executable
chmod +x build.sh extract-images.sh
chmod +x scripts/apply-network-data.sh scripts/network-config.py

# Build the image
./build.sh
```

**Expected output:**
```
Building custom IPA image with network configuration support...
Image: custom-ipa-network:latest
Build context: /path/to/custom-ipa
...
Build completed successfully!
```

### Step 2: Extract Kernel and Ramdisk

```bash
./extract-images.sh
```

**Expected output:**
```
Extracting kernel and ramdisk from custom IPA image...
Creating temporary container...
Extracting kernel...
Extracting ramdisk...
Files created:
-rw-r--r-- 1 user user  8234567 Jan 01 12:00 ironic-python-agent.kernel
-rw-r--r-- 1 user user 45678901 Jan 01 12:00 ironic-python-agent.initramfs
```

### Step 3: Backup Existing Images

```bash
# Create backup directory
sudo mkdir -p /opt/ironic/data/html/images/backup-$(date +%Y%m%d-%H%M%S)

# Backup existing images (if they exist)
sudo cp /opt/ironic/data/html/images/ironic-python-agent.* \
    /opt/ironic/data/html/images/backup-$(date +%Y%m%d-%H%M%S)/ 2>/dev/null || true
```

### Step 4: Deploy New Images

```bash
# Copy new images to Ironic
sudo cp output/ironic-python-agent.kernel /opt/ironic/data/html/images/
sudo cp output/ironic-python-agent.initramfs /opt/ironic/data/html/images/

# Set proper permissions
sudo chown root:root /opt/ironic/data/html/images/ironic-python-agent.*
sudo chmod 644 /opt/ironic/data/html/images/ironic-python-agent.*
```

### Step 5: Restart Ironic

```bash
cd ../  # Go back to ironic directory
sudo docker compose restart ironic
```

**Wait for Ironic to fully restart** (usually 30-60 seconds).

### Step 6: Verify Deployment

```bash
# Check if images are in place
ls -la /opt/ironic/data/html/images/ironic-python-agent.*

# Check Ironic logs
sudo docker logs ironic | tail -20

# Verify Ironic is serving the new images
curl -I http://localhost:8080/images/ironic-python-agent.kernel
curl -I http://localhost:8080/images/ironic-python-agent.initramfs
```

## Testing the Custom IPA

### Test 1: Deploy a BareMetalHost

Use your existing Terraform configuration to deploy a BareMetalHost:

```bash
cd 3-worker-clusters-bootstrap
terraform apply -target=module.worker_cluster.module.metal3[0].kubernetes_manifest.bare_metal_host
```

### Test 2: Monitor IPA Boot Process

1. **Access BMC Console**: Connect to your server's BMC console
2. **Watch Boot Messages**: Look for these key messages during IPA boot:

```
[  OK  ] Started IPA Custom Network Configuration
[  OK  ] Reached target Multi-User System
```

3. **Check Network Service**: Once IPA is running, check the service:

```bash
# Via BMC console
systemctl status ipa-network-init.service
```

**Expected output:**
```
● ipa-network-init.service - IPA Custom Network Configuration
   Loaded: loaded (/etc/systemd/system/ipa-network-init.service; enabled)
   Active: active (exited) since Mon 2024-01-01 12:00:00 UTC; 2min ago
  Process: 1234 ExecStart=/usr/local/bin/apply-network-data.sh (code=exited, status=0/SUCCESS)
```

### Test 3: Verify Network Configuration

```bash
# Via BMC console - Check IP addresses
ip addr show

# Expected: You should see your bond interface with configured IP
# bond0: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9000
#     inet 203.0.113.10/24 brd 203.0.113.255 scope global bond0

# Check routes
ip route show

# Expected: You should see your configured routes
# default via 203.0.113.1 dev bond0
# 10.0.0.0/8 via 10.158.175.248 dev bond0
```

### Test 4: Verify IPA-Ironic Communication

```bash
# Via BMC console - Test connectivity to Ironic
ping -c 3 <your-ironic-ip>

# Check if IPA can reach Ironic API
curl -s http://<your-ironic-ip>:6385/v1/ | head -5
```

**Expected**: You should see JSON response from Ironic API.

## Troubleshooting

### Issue 1: Custom Service Not Running

**Symptoms**: `systemctl status ipa-network-init.service` shows failed

**Debug steps**:
```bash
# Check service logs
journalctl -u ipa-network-init.service -f

# Check script logs
cat /var/log/ipa-network-config.log

# Run script manually
/usr/local/bin/apply-network-data.sh
```

### Issue 2: Network Configuration Failed

**Symptoms**: No IP address on bond interface

**Debug steps**:
```bash
# Check if config drive is mounted
mount | grep sr0

# Check if network_data.json exists
ls -la /mnt/config/openstack/latest/network_data.json

# Check network_data.json content
cat /mnt/config/openstack/latest/network_data.json | jq .

# Run Python script manually
python3 /usr/local/bin/network-config.py
```

### Issue 3: Bond Interface Not Created

**Symptoms**: `ip addr show` doesn't show bond interface

**Debug steps**:
```bash
# Check if bonding module is loaded
lsmod | grep bonding

# Load bonding module manually
modprobe bonding

# Check if physical interfaces exist
ip link show | grep -E "(eno1|eno2)"

# Check MAC addresses match
ip link show | grep -A1 -B1 "7c:c2:55:6e:90:44"
```

### Issue 4: IPA Can't Reach Ironic

**Symptoms**: IPA starts but can't communicate with Ironic

**Debug steps**:
```bash
# Check default route
ip route show default

# Test gateway connectivity
ping -c 3 $(ip route show default | awk '{print $3}')

# Test Ironic connectivity
telnet <ironic-ip> 6385

# Check DNS resolution (if using hostnames)
nslookup <ironic-hostname>
```

## Rollback Procedure

If you need to rollback to the original IPA images:

```bash
# Find your backup
ls -la /opt/ironic/data/html/images/backup-*/

# Restore original images
sudo cp /opt/ironic/data/html/images/backup-YYYYMMDD-HHMMSS/* \
    /opt/ironic/data/html/images/

# Restart Ironic
cd 2-cluster-api/ironic
sudo docker compose restart ironic
```

## Success Indicators

You know the deployment is successful when:

1. ✅ **Custom service runs**: `systemctl status ipa-network-init.service` shows active
2. ✅ **Network configured**: Bond interface has correct IP address
3. ✅ **Routes configured**: Default route and custom routes are present
4. ✅ **Connectivity works**: Can ping gateway and reach Ironic API
5. ✅ **IPA communicates**: IPA successfully registers with Ironic
6. ✅ **Deployment proceeds**: Metal3 deployment continues normally

## Next Steps

Once the custom IPA is working:

1. **Test with multiple nodes**: Deploy additional BareMetalHosts
2. **Monitor performance**: Check if network setup adds significant boot time
3. **Update documentation**: Document any environment-specific configurations
4. **Automate deployment**: Integrate into your CI/CD pipeline

## Support

If you encounter issues not covered in this guide:

1. Check the logs in `/var/log/ipa-network-config.log`
2. Review the systemd journal: `journalctl -u ipa-network-init.service`
3. Verify your network_data.json format matches the expected OpenStack format
4. Test the Python script manually to isolate issues

The custom IPA approach provides a robust solution for DHCP-less environments while maintaining full compatibility with your existing Metal3 infrastructure.
