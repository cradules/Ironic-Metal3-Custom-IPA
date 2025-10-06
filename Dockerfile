# Custom IPA Image with Network Configuration Support
# Downloads the same IPA images that ironic-ipa-downloader uses and modifies them
FROM quay.io/centos/centos:stream9

# Install required packages for building
RUN dnf update -y && \
    dnf install -y --allowerasing \
        curl \
        tar \
        gzip \
        cpio \
        file \
        findutils && \
    dnf clean all

# Create directories for IPA files
RUN mkdir -p /usr/share/ironic-python-agent

# Download the exact same IPA images that ironic-ipa-downloader uses
# This matches: https://tarballs.opendev.org/openstack/ironic-python-agent/dib/ipa-centos9-master.tar.gz
RUN curl -L -o /tmp/ipa.tar.gz "https://tarballs.opendev.org/openstack/ironic-python-agent/dib/ipa-centos9-master.tar.gz" && \
    cd /tmp && \
    tar -xzf ipa.tar.gz && \
    cp ipa-centos9-master.kernel /usr/share/ironic-python-agent/kernel && \
    cp ipa-centos9-master.initramfs /tmp/ipa-original.initramfs

# Extract the original initramfs to modify it
RUN mkdir -p /tmp/ipa-extract && \
    cd /tmp/ipa-extract && \
    zcat /tmp/ipa-original.initramfs | cpio -idmv

# Copy custom network configuration scripts into the extracted initramfs
COPY scripts/network-config.py /tmp/ipa-extract/usr/local/bin/network-config.py
COPY scripts/apply-network-data.sh /tmp/ipa-extract/usr/local/bin/apply-network-data.sh
COPY scripts/ipa-network-init.service /tmp/ipa-extract/etc/systemd/system/ipa-network-init.service

# Make scripts executable and set proper permissions
RUN chmod +x /tmp/ipa-extract/usr/local/bin/network-config.py && \
    chmod +x /tmp/ipa-extract/usr/local/bin/apply-network-data.sh && \
    chmod 644 /tmp/ipa-extract/etc/systemd/system/ipa-network-init.service

# Add bonding module configuration
RUN mkdir -p /tmp/ipa-extract/etc/modules-load.d && \
    echo "bonding" >> /tmp/ipa-extract/etc/modules-load.d/bonding.conf

# Enable the network initialization service
RUN ln -sf /etc/systemd/system/ipa-network-init.service \
    /tmp/ipa-extract/etc/systemd/system/multi-user.target.wants/ipa-network-init.service

# Repack the modified initramfs
RUN cd /tmp/ipa-extract && \
    find . | cpio -o -H newc | gzip > /usr/share/ironic-python-agent/ramdisk

# Clean up temporary files
RUN rm -rf /tmp/ipa.tar.gz /tmp/ipa-extract /tmp/ipa-original.initramfs /tmp/ipa-centos9-master.kernel /tmp/ipa-centos9-master.initramfs

# Set working directory
WORKDIR /

# This container is used to extract the modified IPA kernel and ramdisk
CMD ["echo", "Custom IPA images ready for extraction"]
