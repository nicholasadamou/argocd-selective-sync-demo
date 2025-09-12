#!/bin/bash

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/nexus-common.sh"

# Script-specific configuration
NEW_ADMIN_PASSWORD="admin123"
HELM_REPO_NAME="helm-hosted"
FRESH_INSTALL=false



determine_admin_password() {
    log "Determining admin password..." >&2
    local password
    local max_attempts=30
    local attempt=1
    
    # First, check if admin.password file exists (fresh installation)
    while [ $attempt -le $max_attempts ]; do
        log "Attempt $attempt/$max_attempts - Checking for admin password file..." >&2
        password=$(docker exec "$CONTAINER_NAME" cat /nexus-data/admin.password 2>/dev/null || echo 'NOT_FOUND')
        
        if [ "$password" != "NOT_FOUND" ] && [ -n "$password" ]; then
            success "Found initial admin password from file!" >&2
            echo "$password"
            return 0
        fi
        
        # If no password file, check if this is a reused volume with our expected password
        if curl -s -f -u "admin:$NEW_ADMIN_PASSWORD" "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
            success "Admin password is already set to: $NEW_ADMIN_PASSWORD" >&2
            echo "$NEW_ADMIN_PASSWORD"
            return 0
        fi
        
        # Check if default admin password works
        if curl -s -f -u "admin:admin" "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
            success "Using default admin password" >&2
            echo "admin"
            return 0
        fi
        
        log "Password not ready yet, waiting 10 seconds..." >&2
        sleep 10
        ((attempt++))
    done
    
    error "Could not determine admin password after $max_attempts attempts" >&2
    error "Try cleaning up with: docker stop nexus && docker rm nexus && docker volume rm nexus-data" >&2
    return 1
}

change_admin_password() {
    local current_password="$1"
    
    # Check if password is already what we want
    if [ "$current_password" = "$NEW_ADMIN_PASSWORD" ]; then
        success "Admin password is already set to desired value"
        return 0
    fi
    
    log "Changing admin password from current to: $NEW_ADMIN_PASSWORD"
    
    local response
    
    # Use the correct change-password endpoint with string body
    log "Attempting to change password using v1 change-password endpoint..." >&2
    response=$(curl -s -u "admin:$current_password" -X PUT "$NEXUS_URL/service/rest/v1/security/users/admin/change-password" -H 'Content-Type: text/plain' -d "$NEW_ADMIN_PASSWORD")
    
    # Test the new password
    log "Testing new password..." >&2
    if curl -s -u "admin:$NEW_ADMIN_PASSWORD" -f "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
        success "Admin password changed successfully"
        return 0
    else
        # If the standard endpoint failed, try the fallback method
        log "First method failed, trying alternative user update approach..." >&2
        local user_json='{"userId": "admin", "firstName": "Admin", "lastName": "User", "email": "admin@example.com", "password": "'$NEW_ADMIN_PASSWORD'", "status": "active", "roles": ["nx-admin"]}'
        
        local temp_file
        temp_file=$(create_temp_json "$user_json" "user.json")
        if [ -n "$temp_file" ]; then
            response=$(curl -s -u "admin:$current_password" -X PUT "$NEXUS_URL/service/rest/v1/security/users/admin" -H 'Content-Type: application/json' -d @"$temp_file")
            log "User update API response: $response" >&2
            
            # Test the new password again
            if curl -s -u "admin:$NEW_ADMIN_PASSWORD" -f "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
                success "Admin password changed successfully via user update"
                return 0
            fi
        fi
        
        error "Failed to change admin password - new password doesn't work"
        return 1
    fi
}

enable_anonymous_access() {
    log "Enabling anonymous access..."
    
    local response
    local anonymous_json='{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}'
    
    local temp_file
    temp_file=$(create_temp_json "$anonymous_json" "anonymous.json")
    if [ -n "$temp_file" ]; then
        response=$(curl -s -u "admin:$NEW_ADMIN_PASSWORD" -X PUT "$NEXUS_URL/service/rest/v1/security/anonymous" -H 'Content-Type: application/json' -d @"$temp_file")
        log "Anonymous access API response: $response"
        
        if [ $? -eq 0 ]; then
            success "Anonymous access enabled"
        else
            warn "Failed to enable anonymous access (this might be okay)"
        fi
    else
        warn "Failed to create anonymous access configuration file"
    fi
}

create_helm_repository() {
    log "Creating Helm hosted repository: $HELM_REPO_NAME"
    
    local response
    local repo_json='{"name": "'$HELM_REPO_NAME'", "online": true, "storage": {"blobStoreName": "default", "strictContentTypeValidation": true, "writePolicy": "ALLOW_ONCE"}}'
    
    local temp_file
    temp_file=$(create_temp_json "$repo_json" "repository.json")
    if [ -n "$temp_file" ]; then
        response=$(curl -s -u "admin:$NEW_ADMIN_PASSWORD" -X POST "$NEXUS_URL/service/rest/v1/repositories/helm/hosted" -H 'Content-Type: application/json' -d @"$temp_file")
    fi
    
    if [ $? -eq 0 ]; then
        success "Helm repository '$HELM_REPO_NAME' created successfully"
    else
        error "Failed to create Helm repository"
        return 1
    fi
}

# Upload Helm packages using dedicated script
upload_helm_packages() {
    log "Uploading Helm packages using upload script..."
    if "$SCRIPT_DIR/upload-helm-packages.sh"; then
        success "Helm packages uploaded successfully"
        return 0
    else
        error "Failed to upload Helm packages"
        return 1
    fi
}

verify_setup() {
    log "Verifying Nexus setup..."
    
    # Check if repository exists
    if curl -s -u "admin:$NEW_ADMIN_PASSWORD" "$NEXUS_URL/service/rest/v1/repositories" | grep -q "$HELM_REPO_NAME"; then
        success "Helm repository verified"
    else
        error "Helm repository verification failed"
        return 1
    fi
    
    # Try to access repository index
    if curl -s -u "admin:$NEW_ADMIN_PASSWORD" "$NEXUS_URL/repository/$HELM_REPO_NAME/index.yaml" >/dev/null 2>&1; then
        success "Repository index accessible"
    else
        warn "Repository index may not be immediately available (this is normal)"
    fi
    
    success "Nexus setup verification complete"
}

cleanup_existing_container() {
    log "Checking for existing Nexus container..."
    
    if [ "$FRESH_INSTALL" = true ]; then
        # Force remove any existing container with the same name
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            warn "Fresh install requested - removing existing Nexus container..."
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
            success "Existing container removed"
        fi
        
        warn "Fresh install requested - removing nexus-data volume..."
        docker volume rm nexus-data >/dev/null 2>&1 || true
        success "nexus-data volume removed (if existed)"
    else
        # Check if container exists and is running
        if docker ps | grep -q "$CONTAINER_NAME"; then
            success "Nexus container is already running"
            return 0
        elif docker ps -a | grep -q "$CONTAINER_NAME"; then
            log "Nexus container exists but is not running, starting it..."
            if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
                success "Existing Nexus container started"
                return 0
            else
                warn "Failed to start existing container, will create a new one"
                docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
            fi
        else
            log "No existing Nexus container found, will create a new one"
        fi
    fi
}

start_nexus_container() {
    # Check if container is already running (from cleanup_existing_container)
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log "Nexus container is already running, skipping container creation"
        return 0
    fi
    
    log "Starting Nexus container..."
    
    local container_id
    local docker_output
    
    # Try to start the container with detailed error output
    docker_output=$(docker run -d --name "$CONTAINER_NAME" -p 8081:8081 -v nexus-data:/nexus-data sonatype/nexus3 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        container_id="$docker_output"
        success "Nexus container started with ID: $container_id"
        return 0
    else
        error "Failed to start Nexus container"
        error "Docker output: $docker_output"
        
        # Try alternative approaches for common issues
        if echo "$docker_output" | grep -q "name.*already in use"; then
            warn "Container name conflict, trying to remove and retry..."
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
            
            # Retry container creation
            docker_output=$(docker run -d --name "$CONTAINER_NAME" -p 8081:8081 -v nexus-data:/nexus-data sonatype/nexus3 2>&1)
            if [ $? -eq 0 ]; then
                container_id="$docker_output"
                success "Nexus container started with ID: $container_id"
                return 0
            fi
        fi
        
        if echo "$docker_output" | grep -q "disk quota exceeded"; then
            error "Disk quota exceeded. Please free up disk space."
            error "You can try: docker system prune -f"
        fi
        
        return 1
    fi
}

main() {
    log "Starting Nexus setup process..."
    
    # Step 1: Clean up and start container
    cleanup_existing_container
    start_nexus_container
    
    # Step 2: Wait for Nexus to be ready
    wait_for_nexus
    
    # Step 3: Determine admin password
    local current_password
    current_password=$(determine_admin_password)
    if [ $? -ne 0 ]; then
        error "Failed to determine admin password"
        exit 1
    fi
    log "Current admin password determined"
    
    # Step 4: Change admin password
    change_admin_password "$current_password"

    # Step 5: Enable anonymous access
    enable_anonymous_access

    # Step 6: Complete onboarding
    "$SCRIPT_DIR/complete_onboarding.sh"
    
    # Step 7: Create Helm repository
    create_helm_repository
    
    # Step 8: Upload Helm packages (optional)
    if upload_helm_packages; then
        log "Helm packages uploaded successfully"
    else
        warn "Helm package upload failed, but continuing..."
    fi
    
    # Step 9: Verify setup
    if verify_setup; then
        success "Nexus setup verification complete!"
    else
        error "Setup verification failed"
        exit 1
    fi
    
    success "Nexus setup complete!"
    log ""
    log "Nexus is available at: $NEXUS_URL"
    log "Admin credentials: admin / $NEW_ADMIN_PASSWORD"
    log "Helm repository: $NEXUS_URL/repository/$HELM_REPO_NAME"
    log ""
    log "Next steps:"
    log "1. Access Nexus at $NEXUS_URL (admin/$NEW_ADMIN_PASSWORD)"
    log "2. The Helm repository is ready for ArgoCD integration"
    log "3. Use this repository URL in your ArgoCD applications: $NEXUS_URL/repository/$HELM_REPO_NAME"
}

# Initialize common functions and check prerequisites
nexus_common_init


# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh)
            FRESH_INSTALL=true
            log "Fresh install mode enabled - will clean existing data"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --fresh    Force a clean installation by removing existing container and data"
            echo "  -h, --help Show this help message"
            echo ""
            echo "This script sets up Nexus Repository Manager with Helm repository and uploads packages."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main
