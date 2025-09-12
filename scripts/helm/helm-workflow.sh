#!/bin/bash

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/nexus-common.sh"

# Script-specific configuration
NEW_ADMIN_PASSWORD="admin123"
HELM_REPO_NAME="helm-hosted"

# Bump semantic version
bump_version() {
    local version="$1"
    local bump_type="${2:-patch}"  # patch, minor, major
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch|*)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Update chart version in Chart.yaml
update_chart_version() {
    local chart_dir="$1"
    local new_version="$2"
    
    if [ ! -f "$chart_dir/Chart.yaml" ]; then
        error "Chart.yaml not found in $chart_dir"
        return 1
    fi
    
    # Update version in Chart.yaml
    sed -i.bak "s/^version: .*/version: $new_version/" "$chart_dir/Chart.yaml"
    rm -f "$chart_dir/Chart.yaml.bak"
    
    success "Updated $chart_dir/Chart.yaml to version $new_version"
}

# Update ArgoCD application targetRevision
update_argocd_target_revision() {
    local app_name="$1"
    local new_version="$2"
    
    # Find the ArgoCD application file
    local app_file
    if [[ "$app_name" == *"dev"* ]]; then
        app_file="app-of-apps/applications/dev/templates/$app_name.yaml"
    elif [[ "$app_name" == *"production"* ]]; then
        app_file="app-of-apps/applications/production/templates/$app_name.yaml"
    else
        error "Cannot determine environment for app: $app_name"
        return 1
    fi
    
    if [ ! -f "$app_file" ]; then
        error "ArgoCD application file not found: $app_file"
        return 1
    fi
    
    # Update targetRevision
    sed -i.bak "s/targetRevision: .*/targetRevision: $new_version/" "$app_file"
    rm -f "$app_file.bak"
    
    success "Updated $app_file targetRevision to $new_version"
}

# Complete Helm workflow for a specific app
helm_workflow_for_app() {
    local app_name="$1"
    local bump_type="${2:-patch}"
    
    log "Starting Helm workflow for $app_name..."
    
    local chart_dir="environments/$app_name"
    
    if [ ! -d "$chart_dir" ]; then
        error "Chart directory not found: $chart_dir"
        return 1
    fi
    
    # Get current version
    local current_version
    current_version=$(grep "^version:" "$chart_dir/Chart.yaml" | awk '{print $2}' | tr -d '"' || echo "0.1.0")
    
    # Bump version
    local new_version
    new_version=$(bump_version "$current_version" "$bump_type")
    
    log "Bumping $app_name version: $current_version → $new_version"
    
    # Update Chart.yaml
    update_chart_version "$chart_dir" "$new_version"
    
    # Update ArgoCD application
    update_argocd_target_revision "$app_name" "$new_version"
    
    log "Version updates completed for $app_name"
}

# Publish Helm packages workflow (all packages)
publish_helm_packages() {
    log "Publishing Helm packages workflow..."
    
    # Build packages
    log "Building Helm packages..."
    if ! "$SCRIPT_DIR/build-helm-packages.sh"; then
        error "Failed to build Helm packages"
        return 1
    fi
    
    # Upload packages
    log "Uploading Helm packages to Nexus..."
    if ! "$SCRIPT_DIR/upload-helm-packages.sh"; then
        error "Failed to upload Helm packages"
        return 1
    fi
    
    success "Helm packages published successfully"
}

# Publish single app Helm package
publish_single_app_package() {
    local app_name="$1"
    
    log "Publishing single Helm package for $app_name..."
    
    # Build only the specific app package
    log "Building Helm package for $app_name..."
    
    # Create helm-packages directory if it doesn't exist
    mkdir -p helm-packages
    
    # Package the specific chart
    local chart_dir="environments/$app_name"
    if [ ! -d "$chart_dir" ]; then
        error "Chart directory not found: $chart_dir"
        return 1
    fi
    
    # Verify and package the chart
    if ! helm lint "$chart_dir"; then
        error "Helm chart validation failed for $app_name"
        return 1
    fi
    
    if ! helm package "$chart_dir" --destination helm-packages/; then
        error "Failed to package $app_name"
        return 1
    fi
    
    success "Packaged $app_name"
    
    # Upload only the specific package
    log "Uploading $app_name package to Nexus..."
    
    # Get the version to find the exact package file
    local version
    version=$(grep "^version:" "$chart_dir/Chart.yaml" | awk '{print $2}' | tr -d '"' || echo "0.1.0")
    local package_file="helm-packages/$app_name-$version.tgz"
    
    if [ ! -f "$package_file" ]; then
        error "Package file not found: $package_file"
        return 1
    fi
    
    # Use upload script but only for this specific file
    # We'll need to call the upload function directly with the specific file
    log "Uploading $package_file to Nexus..."
    
    # Upload to Nexus directly
    local package_name=$(basename "$package_file")
    local absolute_package_path=$(realpath "$package_file")
    log "Uploading $package_name directly to Nexus..."
    
    # Upload to Nexus
    if ! curl -u "admin:admin123" --upload-file "$absolute_package_path" "$NEXUS_URL/repository/helm-hosted/"; then
        error "Failed to upload $package_file to Nexus"
        return 1
    fi
    
    success "Uploaded $app_name package successfully"
}

# Scale replicas in deployment template
scale_app_replicas() {
    local app_name="$1"
    local new_replicas="$2"
    
    local deployment_file="environments/$app_name/templates/deployment.yaml"
    
    if [ ! -f "$deployment_file" ]; then
        error "Deployment file not found: $deployment_file"
        return 1
    fi
    
    # Get current replicas
    local current_replicas
    current_replicas=$(grep -m1 -E '^[[:space:]]*replicas:' "$deployment_file" 2>/dev/null | awk '{print $2}' | tr -cd '0-9')
    if [[ -z "$current_replicas" ]]; then
        current_replicas=1
    fi
    
    # Update replicas
    sed -i.bak -E "s/(^[[:space:]]*replicas:[[:space:]]*)[0-9]+/\\1$new_replicas/" "$deployment_file"
    rm -f "$deployment_file.bak"
    
    log "Scaled $app_name replicas: $current_replicas → $new_replicas"
    # Return old value silently for potential rollback (don't echo to stdout)
    return 0
}

# Show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Complete Helm workflow management for ArgoCD applications"
    echo
    echo "Commands:"
    echo "  scale-and-publish <app_name> <replicas>  # Scale app and publish ONLY that app"
    echo "  bump-version <app_name> [patch|minor|major]  # Bump chart version only"
    echo "  publish-packages                         # Build and upload ALL packages"
    echo "  publish-app <app_name>                   # Build and upload single app package"
    echo "  scale-only <app_name> <replicas>        # Scale replicas without version bump"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 scale-and-publish dev-api-app 2      # Scale to 2 replicas and publish only that app"
    echo "  $0 bump-version dev-api-app minor       # Bump minor version"
    echo "  $0 publish-packages                     # Rebuild and upload all packages"
    echo "  $0 publish-app dev-api-app               # Rebuild and upload only dev-api-app"
    echo "  $0 scale-only dev-api-app 3             # Just scale replicas, no version bump"
    echo
    echo "Prerequisites:"
    echo "  • Nexus Repository Manager running"
    echo "  • Docker available for Nexus container"
    echo "  • Helm CLI installed"
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        scale-and-publish)
            if [ $# -lt 2 ]; then
                error "scale-and-publish requires app_name and replicas"
                show_usage
                exit 1
            fi
            
            local app_name="$1"
            local replicas="$2"
            local bump_type="${3:-patch}"
            
            log "Starting scale-and-publish workflow for $app_name..."
            
            # Initialize prerequisites
            nexus_common_init
            
            # Check Nexus is running
            if ! check_nexus_container; then
                exit 1
            fi
            
            # Get current replicas before scaling
            local deployment_file="environments/$app_name/templates/deployment.yaml"
            local old_replicas
            old_replicas=$(grep -m1 -E '^[[:space:]]*replicas:' "$deployment_file" 2>/dev/null | awk '{print $2}' | tr -cd '0-9')
            if [[ -z "$old_replicas" ]]; then
                old_replicas=1
            fi
            
            # Scale replicas
            scale_app_replicas "$app_name" "$replicas"
            
            # Bump version and update ArgoCD
            helm_workflow_for_app "$app_name" "$bump_type"
            
            # Publish only the specific app package
            publish_single_app_package "$app_name"
            
            success "Scale-and-publish workflow completed for $app_name"
            log "Changes made:"
            log "  • Replicas: $old_replicas → $replicas"
            log "  • Chart version bumped ($bump_type)"
            log "  • Packages rebuilt and uploaded to Nexus"
            log "  • ArgoCD targetRevision updated"
            ;;
            
        bump-version)
            if [ $# -lt 1 ]; then
                error "bump-version requires app_name"
                show_usage
                exit 1
            fi
            
            local app_name="$1"
            local bump_type="${2:-patch}"
            
            helm_workflow_for_app "$app_name" "$bump_type"
            ;;
            
        publish-packages)
            nexus_common_init
            if ! check_nexus_container; then
                exit 1
            fi
            publish_helm_packages
            ;;
            
        publish-app)
            if [ $# -lt 1 ]; then
                error "publish-app requires app_name"
                show_usage
                exit 1
            fi
            
            local app_name="$1"
            
            nexus_common_init
            if ! check_nexus_container; then
                exit 1
            fi
            publish_single_app_package "$app_name"
            ;;
            
        scale-only)
            if [ $# -lt 2 ]; then
                error "scale-only requires app_name and replicas"
                show_usage
                exit 1
            fi
            
            local app_name="$1"
            local replicas="$2"
            
            scale_app_replicas "$app_name" "$replicas"
            ;;
            
        -h|--help)
            show_usage
            exit 0
            ;;
            
        *)
            error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
