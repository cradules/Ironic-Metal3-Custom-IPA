#!/bin/bash
# Extract kernel and ramdisk from custom IPA image

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="custom-ipa-network:latest"
OUTPUT_DIR="$SCRIPT_DIR/output"

echo "Extracting kernel and ramdisk from custom IPA image..."
echo "Image: $IMAGE_NAME"
echo "Output directory: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temporary container to extract files
echo "Creating temporary container..."
CONTAINER_ID=$(docker create "$IMAGE_NAME")

echo "Extracting kernel..."
docker cp "$CONTAINER_ID:/usr/share/ironic-python-agent/kernel" "$OUTPUT_DIR/ironic-python-agent.kernel"

echo "Extracting ramdisk..."
docker cp "$CONTAINER_ID:/usr/share/ironic-python-agent/ramdisk" "$OUTPUT_DIR/ironic-python-agent.initramfs"

echo "Cleaning up temporary container..."
docker rm "$CONTAINER_ID"

echo "Extraction completed!"
echo "Files created:"
ls -la "$OUTPUT_DIR/"

echo ""
echo "Copy these files to your Ironic HTTP server:"
echo "  cp $OUTPUT_DIR/ironic-python-agent.kernel /opt/ironic/data/html/images/"
echo "  cp $OUTPUT_DIR/ironic-python-agent.initramfs /opt/ironic/data/html/images/"

echo ""
echo "Then restart your Ironic container to use the new images."
