#!/bin/bash

# demo-cleanup.sh
# Functions for cleaning up demo changes including Git revert and Helm artifacts

# Source common demo functions
source "$(dirname "${BASH_SOURCE[0]}")/demo-common.sh"

# --- Small focused helpers ---

find_demo_commit() {
    git log --oneline -1 --grep="Demo: Scale dev-api-app" --format="%h" 2>/dev/null || echo ""
}

capture_api_chart_version() {
    # Capture version BEFORE revert so we can remove the correct artifacts later
    local chart="environments/dev-api-app/Chart.yaml"
    if [ ! -f "$chart" ]; then
        log "Chart.yaml not found, cannot capture version for cleanup"
        return 1
    fi
    local ver
    ver=$(grep "^version:" "$chart" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "")
    if [ -z "$ver" ] || [ "$ver" = "0.1.0" ]; then
        log "Chart version is original (0.1.0) or not found, no artifacts to clean up"
        return 1
    fi
    echo "$ver"  # Only output the version, no duplicate logging
}

revert_last_commit() {
    log_step "Reverting the scaling change..."
    if git revert --no-edit HEAD; then
        success "Successfully reverted scaling commit"
        log "Revert commit created:"; git log --oneline -1
        return 0
    else
        warn "Failed to revert commit automatically. Manual cleanup may be needed."
        return 1
    fi
}

push_revert_and_wait_detection() {
    log_step "Pushing revert commit to remote repository..."
    if git push; then
        success "Revert pushed successfully to remote repository"
        log "ArgoCD should now detect the revert and sync back to original state"
        log "Allowing 3 seconds for ArgoCD to detect the revert..."; sleep 3
        return 0
    else
        warn "Failed to push revert commit. Manual push may be needed."
        log "You can manually push with: git push"
        return 1
    fi
}

wait_for_argocd_revert_sync() {
    log_step "Waiting for ArgoCD to sync the revert..."; echo
    local start_time=$(date +%s)
    local max_wait=60
    local revert_detected=false

    while [ $(($(date +%s) - start_time)) -lt $max_wait ]; do
        local elapsed=$(($(date +%s) - start_time))
        local api_replicas api_status api_health
        api_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
        api_status=$(kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        api_health=$(kubectl get application dev-api-app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

        printf "\r${CYAN}[%02ds]${NC} Replicas: %s, Status: %s, Health: %s" $elapsed "$api_replicas" "$api_status" "$api_health"

        if [ "$api_replicas" -eq 1 ]; then
            if ! $revert_detected; then
                echo; success "🔄 Deployment scaled back to 1 replica at ${elapsed}s"; revert_detected=true
                if [[ "$api_status" == "Synced" ]] && [[ "$api_health" == "Healthy" ]]; then
                    success "✅ Revert fully completed (Synced + Healthy + Scaled)"; break
                fi
            fi
            if $revert_detected && [[ "$api_status" == "Synced" ]]; then
                echo; success "✅ Revert sync completed at ${elapsed}s"; break
            fi
        fi
        sleep 1
    done
    echo; echo
}

cleanup_api_artifacts() {
    local version="$1"
    log_step "Cleaning up Helm artifacts..."
    if [ -z "$version" ]; then
        log "No API app chart version to clean up (version is original 0.1.0 or not captured)"
        return 0
    fi

    log "Cleaning up API app chart version: $version"
    local package_file="helm-packages/dev-api-app-${version}.tgz"
    if [ -f "$package_file" ]; then
        log "Removing local package file: $package_file"; rm -f "$package_file"; success "Local package file removed"
    else
        log "Local package file not found: $package_file"
    fi

    log "Checking Nexus repository connection..."
    local nexus_health
    nexus_health=$(curl -s -w '%{http_code}' -o /dev/null -u "admin:admin123" "$NEXUS_URL/service/rest/v1/repositories" 2>/dev/null || echo "000")
    if [ "$nexus_health" != "200" ]; then
        warn "Cannot connect to Nexus repository (HTTP: $nexus_health). Skipping Nexus cleanup."
        log "This may be normal if Nexus is not running or not accessible"
        return 0
    fi
    log "Nexus connection verified (HTTP: $nexus_health)"

    log "Searching for package in Nexus repository..."
    local component_search component_id
    component_search=$(curl -s -u "admin:admin123" "$NEXUS_URL/service/rest/v1/search?repository=helm-hosted&name=dev-api-app&version=${version}" 2>/dev/null || echo "")
    if [ -z "$component_search" ]; then
        warn "Failed to search Nexus repository"; return 0
    fi
    
    component_id=$(echo "$component_search" | jq -r '.items[0].id' 2>/dev/null || echo "")
    if [ -z "$component_id" ]; then
        log "Package not found in Nexus repository (may have been previously cleaned or never uploaded)"
        return 0
    fi
    
    log "Found component ID: $component_id"
    log "Removing package from Nexus repository..."
    local delete_response
    delete_response=$(curl -s -w '%{http_code}' -o /dev/null -u "admin:admin123" -X DELETE "$NEXUS_URL/service/rest/v1/components/${component_id}" 2>/dev/null || echo "000")
    if [ "$delete_response" = "204" ] || [ "$delete_response" = "200" ]; then
        success "Package removed from Nexus repository (HTTP: $delete_response)"
    else
        warn "Failed to remove package from Nexus (HTTP: $delete_response)"
    fi
}

verify_cleanup_summary() {
    log_step "Final state after cleanup:"
    local final_replicas remaining_packages
    final_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
    echo "Dev API App replicas: $final_replicas"
    remaining_packages=$(find helm-packages/ -name "dev-api-app-*.tgz" 2>/dev/null | wc -l || echo "0")
    echo "Remaining dev-api-app packages: $remaining_packages"
    if [ "$final_replicas" -eq 1 ]; then
        success "🎉 Cleanup completed successfully - environment and artifacts restored to original state"
    else
        warn "⚠️  Environment may not be fully restored (replicas: $final_replicas)"
    fi
}

# Orchestrator with reduced nesting
cleanup_demo() {
    echo; log_header "🧹 Cleaning Up Demo Changes"; echo

    local demo_commit
    demo_commit=$(find_demo_commit)
    if [ -z "$demo_commit" ]; then
        log "No demo commit found to revert"; echo; return 0
    fi
    log "Found demo commit: $demo_commit"

    local api_chart_version
    api_chart_version=$(capture_api_chart_version)
    local capture_status=$?
    if [ $capture_status -eq 0 ] && [ -n "$api_chart_version" ]; then
        log "Will clean up artifacts for version: $api_chart_version"
    else
        log "No custom chart version to clean up (using original version or capture failed)"
        api_chart_version=""  # Ensure empty for cleanup function
    fi

    revert_last_commit || return 1
    push_revert_and_wait_detection || true
    wait_for_argocd_revert_sync
    cleanup_api_artifacts "$api_chart_version"
    echo
    verify_cleanup_summary
    echo
}

# Export cleanup functions
export -f cleanup_demo find_demo_commit capture_api_chart_version revert_last_commit push_revert_and_wait_detection wait_for_argocd_revert_sync cleanup_api_artifacts verify_cleanup_summary
