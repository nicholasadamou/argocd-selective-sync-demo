#!/bin/bash

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/nexus-common.sh"

complete_onboarding() {
    log "Completing Nexus onboarding..."

    if check_eula_status "admin" "$ADMIN_PASSWORD"; then
        success "EULA already accepted. Onboarding is already complete"
        return 0
    fi

    warn "EULA acceptance required through web interface"
    log ""
    log "Please complete the following steps:"
    log "1. Open your web browser and go to: $NEXUS_URL"
    log "2. Sign in with username: admin, password: $ADMIN_PASSWORD"
    log "3. Accept the End User License Agreement (EULA) in the onboarding wizard"
    log "4. Press ENTER when you have completed the EULA acceptance"
    log ""

    read -p "Press ENTER after accepting the EULA through the web interface..."

    local max_attempts=30
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        log "Attempt $attempt/$max_attempts - Checking if EULA was accepted..."
        if check_eula_status "admin" "$ADMIN_PASSWORD"; then
            success "EULA accepted and onboarding completed"
            return 0
        fi
        log "Still waiting for EULA acceptance... (waiting 5 seconds)"
        sleep 5
    done

    error "EULA was not accepted within the expected time. Please try again."
    return 1
}

# Initialize common functions and check prerequisites
nexus_common_init

# Check if Nexus container is running
if ! check_nexus_container; then
    exit 1
fi

complete_onboarding
