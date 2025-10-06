#!/bin/bash
# Build script for custom IPA image with network configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="custom-ipa-network"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building custom IPA image with network configuration support..."
echo "Image: $FULL_IMAGE_NAME"
echo "Build context: $SCRIPT_DIR"

# Build the Docker image
docker build -t "$FULL_IMAGE_NAME" "$SCRIPT_DIR"

echo "Build completed successfully!"
echo "Image: $FULL_IMAGE_NAME"

# Show image info
echo ""
echo "Image information:"
docker images | grep "$IMAGE_NAME" | head -1

echo ""
echo "To use this image, update your Ironic configuration to use:"
echo "  Deploy kernel: Extract from $FULL_IMAGE_NAME"
echo "  Deploy ramdisk: Extract from $FULL_IMAGE_NAME"

echo ""
echo "Next steps:"
echo "1. Extract kernel and ramdisk from the image"
echo "2. Copy them to your Ironic HTTP server"
echo "3. Update Ironic configuration to use the new images"
echo "4. Test deployment with a bare metal node"
