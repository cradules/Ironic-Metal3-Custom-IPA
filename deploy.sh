#!/bin/bash
# Complete deployment script for custom IPA image
# This script builds, extracts, and deploys the custom IPA image to Ironic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IRONIC_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="custom-ipa-network:latest"
OUTPUT_DIR="$SCRIPT_DIR/output"
IRONIC_IMAGES_DIR="/var/lib/docker/volumes/scripts_ironic-data/_data/html/images"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if we can access Ironic directory
    if [ ! -d "$IRONIC_IMAGES_DIR" ]; then
        log_warning "Ironic images directory $IRONIC_IMAGES_DIR does not exist"
        log_info "Will create it during deployment"
    fi
    
    # Check if we're in the right directory
    if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
        log_error "Dockerfile not found. Are you in the custom-ipa directory?"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

build_image() {
    log_info "Building custom IPA image..."
    
    cd "$SCRIPT_DIR"
    
    # Make scripts executable
    chmod +x build.sh extract-images.sh
    chmod +x scripts/apply-network-data.sh
    chmod +x scripts/network-config.py
    
    # Build the image
    if ./build.sh; then
        log_success "Custom IPA image built successfully"
    else
        log_error "Failed to build custom IPA image"
        exit 1
    fi
}

extract_images() {
    log_info "Extracting kernel and ramdisk from custom IPA image..."
    
    if ./extract-images.sh; then
        log_success "Kernel and ramdisk extracted successfully"
        
        # Show extracted files
        log_info "Extracted files:"
        ls -la "$OUTPUT_DIR/"
    else
        log_error "Failed to extract kernel and ramdisk"
        exit 1
    fi
}

backup_existing_images() {
    log_info "Backing up existing IPA images..."
    
    if [ -d "$IRONIC_IMAGES_DIR" ]; then
        BACKUP_DIR="$IRONIC_IMAGES_DIR/backup-$(date +%Y%m%d-%H%M%S)"
        sudo mkdir -p "$BACKUP_DIR"
        
        if [ -f "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel" ]; then
            sudo cp "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel" "$BACKUP_DIR/"
            log_info "Backed up existing kernel to $BACKUP_DIR/"
        fi
        
        if [ -f "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs" ]; then
            sudo cp "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs" "$BACKUP_DIR/"
            log_info "Backed up existing ramdisk to $BACKUP_DIR/"
        fi
        
        log_success "Backup completed: $BACKUP_DIR"
    else
        log_warning "Ironic images directory does not exist, creating it"
        sudo mkdir -p "$IRONIC_IMAGES_DIR"
    fi
}

deploy_images() {
    log_info "Deploying custom IPA images to Ironic..."
    
    # Copy new images
    if sudo cp "$OUTPUT_DIR/ironic-python-agent.kernel" "$IRONIC_IMAGES_DIR/"; then
        log_success "Deployed custom kernel"
    else
        log_error "Failed to deploy custom kernel"
        exit 1
    fi
    
    if sudo cp "$OUTPUT_DIR/ironic-python-agent.initramfs" "$IRONIC_IMAGES_DIR/"; then
        log_success "Deployed custom ramdisk"
    else
        log_error "Failed to deploy custom ramdisk"
        exit 1
    fi
    
    # Set proper permissions
    sudo chown root:root "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel"
    sudo chown root:root "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs"
    sudo chmod 644 "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel"
    sudo chmod 644 "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs"
    
    log_success "Custom IPA images deployed successfully"
}

restart_ironic() {
    log_info "Restarting Ironic to use new images..."
    
    cd "$IRONIC_DIR"
    
    if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        if sudo docker compose restart ironic; then
            log_success "Ironic restarted successfully"
        else
            log_error "Failed to restart Ironic"
            exit 1
        fi
    else
        log_warning "Docker compose file not found in $IRONIC_DIR"
        log_info "Please restart Ironic manually"
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check if images exist and have reasonable sizes
    if [ -f "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel" ]; then
        KERNEL_SIZE=$(stat -c%s "$IRONIC_IMAGES_DIR/ironic-python-agent.kernel")
        if [ "$KERNEL_SIZE" -gt 1000000 ]; then  # > 1MB
            log_success "Custom kernel deployed (${KERNEL_SIZE} bytes)"
        else
            log_error "Custom kernel seems too small (${KERNEL_SIZE} bytes)"
        fi
    else
        log_error "Custom kernel not found after deployment"
    fi
    
    if [ -f "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs" ]; then
        RAMDISK_SIZE=$(stat -c%s "$IRONIC_IMAGES_DIR/ironic-python-agent.initramfs")
        if [ "$RAMDISK_SIZE" -gt 10000000 ]; then  # > 10MB
            log_success "Custom ramdisk deployed (${RAMDISK_SIZE} bytes)"
        else
            log_error "Custom ramdisk seems too small (${RAMDISK_SIZE} bytes)"
        fi
    else
        log_error "Custom ramdisk not found after deployment"
    fi
}

show_next_steps() {
    log_info "Deployment completed! Next steps:"
    echo ""
    echo "1. Test the deployment:"
    echo "   - Deploy a BareMetalHost through your Terraform configuration"
    echo "   - Monitor the console during IPA boot"
    echo "   - Look for 'IPA Custom Network Configuration' messages"
    echo ""
    echo "2. Check logs if there are issues:"
    echo "   - Via BMC console: systemctl status ipa-network-init.service"
    echo "   - Via BMC console: cat /var/log/ipa-network-config.log"
    echo ""
    echo "3. Verify network configuration:"
    echo "   - Via BMC console: ip addr show"
    echo "   - Via BMC console: ip route show"
    echo "   - Via BMC console: ping <ironic-api-ip>"
    echo ""
    echo "4. If you need to rollback:"
    echo "   - Restore from backup in $IRONIC_IMAGES_DIR/backup-*"
    echo "   - Restart Ironic"
    echo ""
    log_success "Custom IPA deployment is ready for testing!"
}

main() {
    echo "=========================================="
    echo "Custom IPA Image Deployment Script"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    build_image
    extract_images
    backup_existing_images
    deploy_images
    restart_ironic
    verify_deployment
    show_next_steps
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
