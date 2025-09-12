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
    
    # Upload packages directly to Nexus
    log "Uploading Helm packages directly to Nexus..."
    for package in "$helm_packages_dir"/*.tgz; do
        if [ -f "$package" ]; then
            local package_name=$(basename "$package")
            local absolute_package_path=$(realpath "$package")
            log "Uploading $package_name to Nexus..."
            
            # Upload directly to Nexus using curl
            if curl -u "admin:$NEW_ADMIN_PASSWORD" --upload-file "$absolute_package_path" "$NEXUS_URL/repository/$HELM_REPO_NAME/"; then
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
    echo "  • curl command available for uploading"
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
