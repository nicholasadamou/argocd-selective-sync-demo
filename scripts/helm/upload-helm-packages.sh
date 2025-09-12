#!/bin/bash

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/nexus-common.sh"

# Script-specific configuration
NEW_ADMIN_PASSWORD="admin123"
HELM_REPO_NAME="helm-hosted"

upload_helm_packages() {
    log "Uploading Helm packages to repository..."
    
    local helm_packages_dir="./helm-packages"
    
    if [ ! -d "$helm_packages_dir" ]; then
        warn "Helm packages directory not found: $helm_packages_dir"
        warn "Skipping Helm package upload. You can run this again after creating packages."
        return 0
    fi
    
    # Copy packages to Vagrant
    log "Copying Helm packages to Vagrant environment..."
    for package in "$helm_packages_dir"/*.tgz; do
        if [ -f "$package" ]; then
            local package_name=$(basename "$package")
            local absolute_package_path=$(realpath "$package")
            log "Copying $package_name..."
            
            # Use base64 encoding to transfer the file through vagrant ssh
            # This avoids path issues with vagrant upload on Windows
            if base64 "$absolute_package_path" | vagrant_ssh "base64 -d > /tmp/$package_name"; then
                log "Successfully copied $package_name using base64 transfer"
            else
                error "Failed to copy $package_name"
                return 1
            fi
        fi
    done
    
    # Upload packages
    for package in "$helm_packages_dir"/*.tgz; do
        if [ -f "$package" ]; then
            local package_name=$(basename "$package")
            log "Uploading $package_name to Nexus..."
            
            local upload_response
            upload_response=$(vagrant_ssh "curl -s -u admin:$NEW_ADMIN_PASSWORD -X POST '$NEXUS_URL/service/rest/v1/components?repository=$HELM_REPO_NAME' -F 'helm.asset=@/tmp/$package_name'")
            
            if [ $? -eq 0 ]; then
                success "Uploaded $package_name"
            else
                error "Failed to upload $package_name"
                return 1
            fi
        fi
    done
}

main() {
    log "Starting Helm package upload process..."
    
    # Initialize common functions and check prerequisites
    nexus_common_init
    
    # Check if Nexus container is running
    if ! check_nexus_container; then
        exit 1
    fi
    
    # Upload packages
    if upload_helm_packages; then
        success "Helm package upload completed successfully!"
    else
        error "Helm package upload failed"
        exit 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Upload Helm packages from ./helm-packages/ to Nexus repository"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo
    echo "Prerequisites:"
    echo "  • Nexus Repository Manager running and accessible"
    echo "  • Helm packages built (run build-helm-packages.sh first)"
    echo "  • vagrant-ssh and vagrant-scp commands available"
    echo
    echo "Examples:"
    echo "  $0            # Upload all packages in ./helm-packages/"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main
