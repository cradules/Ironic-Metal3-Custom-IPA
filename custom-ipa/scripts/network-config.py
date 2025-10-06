#!/usr/bin/env python3
"""
Custom IPA Network Configuration Script
Reads network_data.json from config drive and applies network configuration
"""

import json
import subprocess
import sys
import os
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/ipa-network-config.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class NetworkConfigurator:
    def __init__(self, config_drive_path="/mnt/config"):
        self.config_drive_path = config_drive_path
        self.network_data_path = os.path.join(config_drive_path, "openstack/latest/network_data.json")
        self.network_data = None
        
    def mount_config_drive(self):
        """Mount the config drive"""
        try:
            # Create mount point
            os.makedirs(self.config_drive_path, exist_ok=True)
            
            # Try to mount config drive
            result = subprocess.run([
                'mount', '/dev/sr0', self.config_drive_path
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Successfully mounted config drive to {self.config_drive_path}")
                return True
            else:
                logger.error(f"Failed to mount config drive: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Exception mounting config drive: {e}")
            return False
    
    def load_network_data(self):
        """Load network_data.json from config drive"""
        try:
            if not os.path.exists(self.network_data_path):
                logger.error(f"network_data.json not found at {self.network_data_path}")
                return False
                
            with open(self.network_data_path, 'r') as f:
                self.network_data = json.load(f)
                
            logger.info("Successfully loaded network_data.json")
            logger.debug(f"Network data: {json.dumps(self.network_data, indent=2)}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load network_data.json: {e}")
            return False
    
    def get_interface_by_mac(self, mac_address):
        """Find interface name by MAC address"""
        try:
            result = subprocess.run([
                'ip', 'link', 'show'
            ], capture_output=True, text=True)
            
            lines = result.stdout.split('\n')
            current_interface = None
            
            for line in lines:
                if ': ' in line and 'link/' not in line:
                    # Interface line
                    current_interface = line.split(':')[1].strip().split('@')[0]
                elif 'link/ether' in line and mac_address.lower() in line.lower():
                    logger.info(f"Found interface {current_interface} for MAC {mac_address}")
                    return current_interface
                    
            logger.warning(f"Interface not found for MAC {mac_address}")
            return None
            
        except Exception as e:
            logger.error(f"Error finding interface for MAC {mac_address}: {e}")
            return None
    
    def run_command(self, cmd):
        """Run a shell command and log the result"""
        try:
            logger.info(f"Running command: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Command succeeded: {result.stdout.strip()}")
                return True
            else:
                logger.error(f"Command failed: {result.stderr.strip()}")
                return False
                
        except Exception as e:
            logger.error(f"Exception running command {cmd}: {e}")
            return False
    
    def configure_bond(self, bond_config):
        """Configure bond interface"""
        bond_name = bond_config['id']
        bond_mode = bond_config.get('bond_mode', '802.3ad')
        bond_links = bond_config.get('bond_links', [])
        mtu = bond_config.get('mtu', 1500)

        logger.info(f"Configuring bond {bond_name} with mode {bond_mode}, MTU {mtu}")

        # Load bonding module if not loaded
        self.run_command(['modprobe', 'bonding'])

        # Create bond interface
        if not self.run_command(['ip', 'link', 'add', bond_name, 'type', 'bond', 'mode', bond_mode]):
            return False

        # Set MTU
        if not self.run_command(['ip', 'link', 'set', bond_name, 'mtu', str(mtu)]):
            return False
        
        # Add slave interfaces to bond
        for link_id in bond_links:
            # Find the physical interface for this link
            for link in self.network_data.get('links', []):
                if link['id'] == link_id and link['type'] == 'phy':
                    mac_address = link.get('ethernet_mac_address')
                    if mac_address:
                        interface = self.get_interface_by_mac(mac_address)
                        if interface:
                            # Bring interface down first
                            self.run_command(['ip', 'link', 'set', interface, 'down'])
                            # Set MTU on slave interface
                            self.run_command(['ip', 'link', 'set', interface, 'mtu', str(mtu)])
                            # Add to bond
                            self.run_command(['ip', 'link', 'set', interface, 'master', bond_name])
                            # Bring slave interface up
                            self.run_command(['ip', 'link', 'set', interface, 'up'])
                            logger.info(f"Added {interface} to bond {bond_name}")
                        else:
                            logger.error(f"Could not find interface for MAC {mac_address}")
                    else:
                        logger.error(f"No MAC address found for link {link_id}")
        
        # Wait for bond to be ready
        time.sleep(2)

        # Bring bond interface up
        if not self.run_command(['ip', 'link', 'set', bond_name, 'up']):
            return False

        # Wait for bond to fully initialize
        time.sleep(3)

        logger.info(f"Bond {bond_name} configured successfully")
        return True
    
    def configure_network(self, network_config):
        """Configure IP address and routes for a network"""
        link_id = network_config.get('link')
        ip_address = network_config.get('ip_address')
        netmask = network_config.get('netmask')
        routes = network_config.get('routes', [])
        
        if not ip_address or not netmask:
            logger.warning(f"Missing IP or netmask for network {network_config.get('id')}")
            return False
        
        # Find the interface for this link
        interface = None
        for link in self.network_data.get('links', []):
            if link['id'] == link_id:
                if link['type'] == 'bond':
                    interface = link['id']  # Bond name
                elif link['type'] == 'phy':
                    mac_address = link.get('ethernet_mac_address')
                    if mac_address:
                        interface = self.get_interface_by_mac(mac_address)
                break
        
        if not interface:
            logger.error(f"Could not find interface for link {link_id}")
            return False
        
        # Convert netmask to CIDR
        cidr = self.netmask_to_cidr(netmask)
        ip_with_cidr = f"{ip_address}/{cidr}"
        
        logger.info(f"Configuring {interface} with IP {ip_with_cidr}")
        
        # Configure IP address
        if not self.run_command(['ip', 'addr', 'add', ip_with_cidr, 'dev', interface]):
            return False
        
        # Bring interface up
        if not self.run_command(['ip', 'link', 'set', interface, 'up']):
            return False
        
        # Configure routes
        for route in routes:
            network = route.get('network')
            route_netmask = route.get('netmask')
            gateway = route.get('gateway')

            if network and route_netmask and gateway:
                route_cidr = self.netmask_to_cidr(route_netmask)
                route_dest = f"{network}/{route_cidr}"

                logger.info(f"Adding route {route_dest} via {gateway}")
                self.run_command(['ip', 'route', 'add', route_dest, 'via', gateway, 'dev', interface])

        # Check if this network should be the default route (gateway for 0.0.0.0/0)
        for route in routes:
            network = route.get('network')
            route_netmask = route.get('netmask')
            gateway = route.get('gateway')

            if network == "0.0.0.0" and route_netmask == "0.0.0.0" and gateway:
                logger.info(f"Adding default route via {gateway}")
                self.run_command(['ip', 'route', 'add', 'default', 'via', gateway, 'dev', interface])
        
        return True
    
    def netmask_to_cidr(self, netmask):
        """Convert netmask to CIDR notation"""
        try:
            return sum(bin(int(x)).count('1') for x in netmask.split('.'))
        except:
            logger.error(f"Invalid netmask: {netmask}")
            return 24  # Default fallback
    
    def apply_network_configuration(self):
        """Apply the complete network configuration"""
        if not self.network_data:
            logger.error("No network data loaded")
            return False
        
        logger.info("Starting network configuration")
        
        # First, configure bonds
        for link in self.network_data.get('links', []):
            if link.get('type') == 'bond':
                if not self.configure_bond(link):
                    logger.error(f"Failed to configure bond {link['id']}")
                    return False
        
        # Wait a bit for bonds to come up
        time.sleep(2)
        
        # Then configure networks (IP addresses and routes)
        for network in self.network_data.get('networks', []):
            if not self.configure_network(network):
                logger.error(f"Failed to configure network {network.get('id')}")
                return False
        
        logger.info("Network configuration completed successfully")
        return True

def main():
    """Main function"""
    logger.info("Starting IPA custom network configuration")
    
    configurator = NetworkConfigurator()
    
    # Mount config drive
    if not configurator.mount_config_drive():
        logger.error("Failed to mount config drive")
        sys.exit(1)
    
    # Load network data
    if not configurator.load_network_data():
        logger.error("Failed to load network data")
        sys.exit(1)
    
    # Apply network configuration
    if not configurator.apply_network_configuration():
        logger.error("Failed to apply network configuration")
        sys.exit(1)
    
    logger.info("IPA network configuration completed successfully")

if __name__ == "__main__":
    main()
