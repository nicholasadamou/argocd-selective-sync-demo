#!/bin/bash

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/nexus-common.sh"

# Environment directories to package
ENVIRONMENTS=(
    "environments/dev-api-app"
    "environments/dev-demo-app" 
    "environments/production-api-app"
    "environments/production-demo-app"
    "app-of-apps/applications/dev"
    "app-of-apps/applications/production"
)

create_helm_packages_dir() {
    log "Creating helm-packages directory..."
    mkdir -p helm-packages
    success "Directory created: helm-packages/"
}

verify_helm_chart() {
    local chart_dir="$1"
    local chart_name=$(basename "$chart_dir")
    
    log "Verifying Helm chart: $chart_name"
    
    # Check if Chart.yaml exists
    if [ ! -f "$chart_dir/Chart.yaml" ]; then
        error "Chart.yaml not found in $chart_dir"
        return 1
    fi
    
    # Check if templates directory exists
    if [ ! -d "$chart_dir/templates" ]; then
        error "templates/ directory not found in $chart_dir"
        return 1
    fi
    
    # Check if templates directory has any files
    if [ -z "$(ls -A "$chart_dir/templates" 2>/dev/null)" ]; then
        warn "templates/ directory is empty in $chart_dir"
    fi
    
    success "Chart $chart_name is valid"
    return 0
}

package_helm_chart() {
    local chart_dir="$1"
    local chart_name=$(basename "$chart_dir")
    
    log "Packaging Helm chart: $chart_name"
    
    # Verify chart first
    if ! verify_helm_chart "$chart_dir"; then
        error "Chart verification failed for $chart_name"
        return 1
    fi
    
    # Package the chart
    if helm package "$chart_dir" -d helm-packages/; then
        success "Packaged $chart_name"
        return 0
    else
        error "Failed to package $chart_name"
        return 1
    fi
}

list_packages() {
    log "Helm packages created:"
    ls -la helm-packages/*.tgz 2>/dev/null || {
        warn "No .tgz files found in helm-packages/"
        return 1
    }
}

main() {
    log "Building all Helm packages..."
    
    # Create output directory
    create_helm_packages_dir
    
    # Package each environment
    local failed_packages=0
    for env_dir in "${ENVIRONMENTS[@]}"; do
        if [ -d "$env_dir" ]; then
            if ! package_helm_chart "$env_dir"; then
                ((failed_packages++))
            fi
        else
            warn "Directory not found: $env_dir"
            ((failed_packages++))
        fi
    done
    
    # Report results
    if [ $failed_packages -eq 0 ]; then
        success "All Helm packages built successfully!"
        list_packages
        log ""
        log "You can now run: ./scripts/helm/setup-nexus.sh"
    else
        error "$failed_packages package(s) failed to build"
        exit 1
    fi
}

# Initialize common functions and check prerequisites (only helm needed for this script)
nexus_common_init helm

# Run main function
main "$@"
