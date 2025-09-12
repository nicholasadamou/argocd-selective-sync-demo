#!/bin/bash

# nexus-common.sh - Common functions and variables for Nexus setup scripts
# This library provides shared functionality to avoid code duplication

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NEXUS_URL="${NEXUS_URL:-http://localhost:8081}"
CONTAINER_NAME="${CONTAINER_NAME:-nexus}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Execute shell commands locally or remotely
exec_cmd() {
    local command="$1"
    local max_retries=3
    local retry_delay=5
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        local output
        output=$(bash -c "$command" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "$output"
            return $exit_code
        else
            warn "Command failed (attempt $((retry + 1))/$max_retries): $command"
            if [ $retry -lt $((max_retries - 1)) ]; then
                warn "Waiting $retry_delay seconds before retrying..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff
            fi
            retry=$((retry + 1))
        fi
    done
    
    error "Command failed after $max_retries attempts: $command"
    return 1
}

# Check if required commands are available
check_prerequisites() {
    local missing_deps=()
    local required_commands=("${@:-curl helm docker}")

    for cmd in $required_commands; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please ensure the following commands are installed and in your PATH:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                curl)
                    error "  - curl: Please install curl (https://curl.se/)"
                    ;;
                helm)
                    error "  - helm: Please install Helm (https://helm.sh/docs/intro/install/)"
                    ;;
                docker)
                    error "  - docker: Please install Docker (https://docs.docker.com/get-docker/)"
                    ;;
                kubectl)
                    error "  - kubectl: Please install kubectl (https://kubernetes.io/docs/tasks/tools/)"
                    ;;
                *)
                    error "  - $dep: Please install this command"
                    ;;
            esac
        done
        return 1
    fi
    
    success "All prerequisites are available"
    return 0
}

# Check if Nexus container is running
check_nexus_container() {
    log "Checking if Nexus container is running..."
    if ! exec_cmd "docker ps | grep -q $CONTAINER_NAME"; then
        error "Nexus container ($CONTAINER_NAME) is not running!"
        error "Please start the Nexus container first by running:"
        error "  ./scripts/helm/setup-nexus.sh"
        error "Or manually start it with:"
        error "  docker start $CONTAINER_NAME"
        return 1
    fi
    success "Nexus container is running"
    return 0
}

# Wait for Nexus to be ready
wait_for_nexus() {
    log "Waiting for Nexus to be ready..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if container is running
        if ! exec_cmd "docker ps | grep -q $CONTAINER_NAME"; then
            error "Nexus container is not running!"
            return 1
        fi
        
        # Check if Nexus web interface is responding
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' "$NEXUS_URL" 2>/dev/null || echo "000")
        
        if echo "$http_code" | grep -q "200\|403\|401"; then
            success "Nexus is ready! (HTTP $http_code)"
            # Give it a few more seconds to be fully initialized
            sleep 5
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts - Nexus not ready yet (HTTP $http_code), waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    error "Nexus failed to start within expected time"
    return 1
}

# Test Nexus authentication
test_nexus_auth() {
    local username="${1:-admin}"
    local password="${2:-$ADMIN_PASSWORD}"
    
    log "Testing Nexus authentication for user: $username"
    if curl -s -f -u "$username:$password" "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
        success "Authentication successful for user: $username"
        return 0
    else
        error "Authentication failed for user: $username"
        return 1
    fi
}

# Check EULA status
check_eula_status() {
    local username="${1:-admin}"
    local password="${2:-$ADMIN_PASSWORD}"
    
    log "Checking EULA status..."
    local response
    response=$(curl -s -u "$username:$password" "$NEXUS_URL/service/rest/v1/system/eula" 2>&1)
    local exit_code=$?
    
    log "Debug: curl exit code: $exit_code"
    log "Debug: EULA response: '$response'"
    
    if echo "$response" | grep -q '"accepted"[[:space:]]*:[[:space:]]*true'; then
        return 0
    else
        return 1
    fi
}

# Helper function to create JSON files locally
create_temp_json() {
    local json_content="$1"
    local local_filename="$2"
    
    # Create local temporary file
    local temp_file="/tmp/$local_filename"
    if echo "$json_content" > "$temp_file"; then
        echo "$temp_file"
        return 0
    else
        error "Failed to create JSON file: $temp_file"
        return 1
    fi
}

# Validate project directory
validate_project_directory() {
    if [ ! -f "README.md" ] || [ ! -d "environments" ]; then
        error "Please run this script from the project root directory"
        return 1
    fi
    return 0
}

# Common initialization function that scripts can call
nexus_common_init() {
    # Validate we're in the right directory
    if ! validate_project_directory; then
        exit 1
    fi
    
    # Check prerequisites (use arguments if provided, otherwise defaults)
    if ! check_prerequisites "$@"; then
        exit 1
    fi
}

# Export functions to make them available to sourcing scripts
export -f log warn error success
export -f exec_cmd
export -f check_prerequisites check_nexus_container wait_for_nexus
export -f test_nexus_auth check_eula_status create_temp_json
export -f validate_project_directory nexus_common_init
