# Custom IPA Image with Network Configuration Support
# Based on the official Metal3 IPA image
FROM quay.io/metal3-io/ironic-python-agent:latest

# Install additional packages for network configuration
USER root

# Install network configuration tools and bonding support
RUN dnf update -y && \
    dnf install -y \
        python3-pip \
        python3-yaml \
        python3-requests \
        iproute \
        bridge-utils \
        net-tools \
        iputils \
        bind-utils \
        jq \
        ethtool \
        ifenslave && \
    dnf clean all

# Install Python packages for network configuration
RUN pip3 install --no-cache-dir \
    pyyaml \
    requests \
    netifaces

# Load bonding kernel module
RUN echo "bonding" >> /etc/modules-load.d/bonding.conf

# Copy custom network configuration scripts
COPY scripts/network-config.py /usr/local/bin/network-config.py
COPY scripts/apply-network-data.sh /usr/local/bin/apply-network-data.sh
COPY scripts/ipa-network-init.service /etc/systemd/system/ipa-network-init.service

# Make scripts executable
RUN chmod +x /usr/local/bin/network-config.py && \
    chmod +x /usr/local/bin/apply-network-data.sh && \
    chmod 644 /etc/systemd/system/ipa-network-init.service

# Enable the network initialization service
RUN systemctl enable ipa-network-init.service

# Switch back to IPA user
USER ironic

# Set environment variables for custom network configuration
ENV IPA_ENABLE_CUSTOM_NETWORK=true
ENV IPA_CONFIG_DRIVE_MOUNT=/mnt/config
ENV IPA_NETWORK_DATA_PATH=/mnt/config/openstack/latest/network_data.json

# Keep the original IPA entrypoint
ENTRYPOINT ["/usr/local/bin/ironic-python-agent"]
