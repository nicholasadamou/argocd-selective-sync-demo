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

# Check and handle Vagrant lock status
check_vagrant_lock() {
    log "Checking Vagrant lock status..."
    
    # Determine Vagrant directory - look for common locations
    local vagrant_dirs=(
        "$HOME/code/gitlab/beast/operational/repo/vagrant"
    )
    
    local vagrant_dir=""
    for dir in "${vagrant_dirs[@]}"; do
        if [ -f "$dir/Vagrantfile" ]; then
            vagrant_dir="$dir"
            log "Found Vagrant directory: $vagrant_dir"
            break
        fi
    done
    
    if [ -z "$vagrant_dir" ]; then
        warn "Could not find Vagrant directory with Vagrantfile"
        warn "Please ensure Vagrant is set up or run from the correct directory"
        return 1
    fi
    
    # Change to Vagrant directory and check status
    local current_dir="$(pwd)"
    cd "$vagrant_dir" || {
        error "Failed to change to Vagrant directory: $vagrant_dir"
        return 1
    }
    
    # Try to run a simple vagrant command to check for locks
    local vagrant_output
    vagrant_output=$(vagrant status 2>&1 || true)
    local vagrant_exit_code=$?
    
    # Return to original directory
    cd "$current_dir"
    
    if echo "$vagrant_output" | grep -q "locked"; then
        warn "Vagrant machine is locked by another process"
        warn "Vagrant directory: $vagrant_dir"
        warn "This usually means another Vagrant operation is running"
        warn "Please wait for the other process to complete, or if stuck:"
        warn "  1. Check for running Vagrant processes: ps aux | grep vagrant"
        warn "  2. Kill stuck processes if necessary"
        warn "  3. Use the helper script: ./scripts/fix-vagrant-lock.sh"
        warn "  4. Or manually: cd $vagrant_dir && vagrant reload"
        return 1
    fi
    
    if [ $vagrant_exit_code -ne 0 ]; then
        warn "Vagrant command failed (exit code: $vagrant_exit_code)"
        warn "Output: $vagrant_output"
        return 1
    fi
    
    log "Vagrant status check completed from: $vagrant_dir"
    return 0
}

# Helper function to run vagrant ssh commands with retry and lock handling
vagrant_ssh() {
    local command="$1"
    local max_retries=3
    local retry_delay=5
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        local output
        output=$(vagrant-ssh "$command" 2>&1)
        local exit_code=$?
        
        # Check if output contains lock message
        if echo "$output" | grep -q "locked"; then
            warn "Vagrant is locked (attempt $((retry + 1))/$max_retries)"
            if [ $retry -lt $((max_retries - 1)) ]; then
                warn "Waiting $retry_delay seconds before retrying..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff
            fi
            retry=$((retry + 1))
        else
            # Command succeeded or failed for reasons other than locking
            echo "$output"
            return $exit_code
        fi
    done
    
    error "Vagrant remains locked after $max_retries attempts"
    error "Please resolve the Vagrant lock issue manually"
    return 1
}

# Helper function to upload files to vagrant
vagrant_upload() {
    local local_path="$1"
    local remote_path="$2"
    vagrant-scp --to "$local_path" "$remote_path"
}

# Check if required commands are available
check_prerequisites() {
    local missing_deps=()
    local required_commands=("${@:-vagrant vagrant-ssh vagrant-scp}")

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
                vagrant)
                    error "  - vagrant: Please install Vagrant"
                    ;;
                vagrant-ssh|vagrant-scp)
                    error "  - $dep: Install from vagrant-scripts repository"
                    error "    You can install it from: https://gitlab.us.lmco.com/nicholasadamou/vagrant-scripts"
                    ;;
                helm)
                    error "  - helm: Please install Helm (https://helm.sh/docs/intro/install/)"
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
    if ! vagrant_ssh "docker ps | grep -q $CONTAINER_NAME"; then
        error "Nexus container ($CONTAINER_NAME) is not running!"
        error "Please start the Nexus container first by running:"
        error "  ./scripts/helm/setup-nexus.sh"
        error "Or manually start it with:"
        error "  vagrant-ssh 'docker start $CONTAINER_NAME'"
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
        if ! vagrant_ssh "docker ps | grep -q $CONTAINER_NAME"; then
            error "Nexus container is not running!"
            return 1
        fi
        
        # Check if Nexus web interface is responding
        local http_code
        http_code=$(vagrant_ssh "curl -s -o /dev/null -w '%{http_code}' $NEXUS_URL" 2>/dev/null || echo "000")
        
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
    if vagrant_ssh "curl -s -f -u $username:$password '$NEXUS_URL/service/rest/v1/status' >/dev/null 2>&1"; then
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
    response=$(vagrant_ssh "curl -s -u $username:$password \"$NEXUS_URL/service/rest/v1/system/eula\" 2>&1")
    local exit_code=$?
    
    log "Debug: curl exit code: $exit_code"
    log "Debug: EULA response: '$response'"
    
    if echo "$response" | grep -q '"accepted"[[:space:]]*:[[:space:]]*true'; then
        return 0
    else
        return 1
    fi
}

# Helper function to create JSON files directly on remote system
create_remote_json() {
    local json_content="$1"
    local remote_filename="$2"
    
    # Use cat with heredoc to create file remotely
    if vagrant_ssh "cat > /tmp/$remote_filename << 'EOF'
$json_content
EOF" >/dev/null 2>&1; then
        return 0
    else
        error "Failed to create JSON file on remote system: $remote_filename"
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
export -f vagrant_ssh vagrant_upload check_vagrant_lock
export -f check_prerequisites check_nexus_container wait_for_nexus
export -f test_nexus_auth check_eula_status create_remote_json
export -f validate_project_directory nexus_common_init
