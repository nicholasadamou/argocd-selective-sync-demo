#!/bin/bash

# demo-state.sh
# Functions for managing and monitoring demo state

# Source common demo functions
source "$(dirname "${BASH_SOURCE[0]}")/demo-common.sh"

# Show current state before demo
show_initial_state() {
    log_header "📊 Initial State Before Selective Sync Test"
    echo
    
    log_step "Current Applications:"
    vagrant-ssh "kubectl get applications -n argocd | grep -E '(dev-api-app|dev-demo-app|NAME)'" || echo "No matching applications found"
    echo
    
    log_step "Current Pod Count in Each Namespace:"
    echo "Dev API App namespace:"
    vagrant-ssh "kubectl get pods -n dev-api-app --no-headers 2>/dev/null | grep -v 'Completed' | wc -l" || echo "0"
    echo "Dev Demo App namespace:"
    vagrant-ssh "kubectl get pods -n dev-demo-app --no-headers 2>/dev/null | grep -v 'Completed' | wc -l" || echo "0"
    echo
    
    log_step "Current Replica Counts:"
    echo "Dev API App:"
    vagrant-ssh "kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "N/A"
    echo
    echo "Dev Demo App:"
    vagrant-ssh "kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "N/A"
    echo
    
    echo
    log_step "Current Git Revision:"
    local current_rev
    current_rev=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8" || echo "Unknown")
    echo "ArgoCD Sync Revision: $current_rev"
    echo "Git HEAD: $(git rev-parse --short HEAD)"
    echo
}

# Monitor selective sync behavior
monitor_selective_sync() {
    log_header "👀 Monitoring Selective Sync Behavior"
    echo
    
    local start_time=$(date +%s)
    local api_app_synced=false
    local api_deployment_scaled=false
    local current_git_rev=$(git rev-parse --short HEAD)
    local target_replicas=$(( $(grep -m1 -E '^[[:space:]]*replicas:' environments/dev-api-app/templates/deployment.yaml 2>/dev/null | awk '{print $2}' | tr -cd '0-9') ))
    
    # Get initial state for comparison
    local initial_api_status initial_api_rev initial_api_replicas
    initial_api_status=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null" || echo "Unknown")
    initial_api_rev=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8" || echo "Unknown")
    initial_api_replicas=$(vagrant-ssh "kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "0")
    
    log "Watching for ArgoCD to detect and sync changes..."
    log "Target: $target_replicas replicas, git revision: $current_git_rev"
    echo
    
    # Phase 1: Wait for ArgoCD to detect the change (OutOfSync)
    log_step "Phase 1: Waiting for ArgoCD to detect git changes..."
    local detection_start=$start_time
    while [ $(($(date +%s) - start_time)) -lt 30 ]; do  # 30s max for detection
        local elapsed=$(($(date +%s) - start_time))
        local api_status api_rev
        
        api_status=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null" || echo "Unknown")
        api_rev=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8" || echo "Unknown")
        
        printf "\r${CYAN}[%02ds]${NC} Status: %s, Revision: %s" $elapsed "$api_status" "$api_rev"
        
        # Check if ArgoCD detected the change
        if [[ "$api_status" == "OutOfSync" ]] || [[ "$api_rev" == "$current_git_rev" ]]; then
            echo
            success "✅ ArgoCD detected changes at ${elapsed}s (Status: $api_status)"
            break
        fi
        
        sleep 1  # More frequent checks during detection phase
    done
    echo
    
    # Phase 2: Wait for sync to complete
    log_step "Phase 2: Waiting for sync to complete..."
    local sync_start=$(date +%s)
    while true; do
        local total_elapsed=$(($(date +%s) - start_time))
        local sync_elapsed=$(($(date +%s) - sync_start))
        
        # Get current state
        local api_status api_rev api_replicas api_health
        api_status=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null" || echo "Unknown")
        api_rev=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8" || echo "Unknown")
        api_replicas=$(vagrant-ssh "kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "0")
        api_health=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null" || echo "Unknown")
        
        printf "\r${CYAN}[%02ds]${NC} Sync: %s, Health: %s, Replicas: %s/%s" \
               $total_elapsed "$api_status" "$api_health" "$api_replicas" "$target_replicas"
        
        # Check deployment scaling completion
        if [[ "$api_replicas" == "$target_replicas" ]] && ! $api_deployment_scaled; then
            api_deployment_scaled=true
            echo
            success "🔄 Deployment scaled to $api_replicas replicas at ${total_elapsed}s"
        fi
        
        # Check if sync fully completed
        if [[ "$api_status" == "Synced" ]] && [[ "$api_health" == "Healthy" ]] && \
           [[ "$api_replicas" == "$target_replicas" ]] && [[ "$api_rev" == "$current_git_rev" ]]; then
            echo
            success "✅ Complete sync achieved at ${total_elapsed}s (Synced + Healthy + Scaled)"
            api_app_synced=true
            break
        fi
        
        # Early exit if we achieve the main goal even if not fully healthy yet
        if [[ "$api_status" == "Synced" ]] && [[ "$api_replicas" == "$target_replicas" ]] && $api_deployment_scaled; then
            if [ $sync_elapsed -gt 15 ]; then  # Give it at least 15s for health to stabilize
                echo
                success "✅ Sync completed at ${total_elapsed}s (may still be reaching healthy state)"
                api_app_synced=true
                break
            fi
        fi
        
        sleep 2
    done
    
    echo
    
    # Summary of monitoring results
    if $api_app_synced; then
        success "🎯 Monitoring completed - sync detected and confirmed"
    else
        warn "⏰ Monitoring loop exited unexpectedly"
        log "Current state: Status=$api_status, Health=$api_health, Replicas=$api_replicas"
    fi
    
    echo
}

# Show results after sync
show_results() {
    log_header "📋 Selective Sync Results"
    echo
    
    # Application sync status
    log_step "Final Application Sync Status:"
    vagrant-ssh "kubectl get applications -n argocd | grep -E '(dev-api-app|dev-demo-app|NAME)'" || echo "No applications found"
    echo
    
    # Pod counts
    log_step "Pod Counts After Change:"
    local api_pods demo_pods
    api_pods=$(vagrant-ssh "kubectl get pods -n dev-api-app --no-headers 2>/dev/null | grep -v 'Completed' | wc -l" || echo "0")
    demo_pods=$(vagrant-ssh "kubectl get pods -n dev-demo-app --no-headers 2>/dev/null | grep -v 'Completed' | wc -l" || echo "0")
    
    echo "Dev API App pods: $api_pods"
    echo "Dev Demo App pods: $demo_pods"
    echo
    
    # Replica counts
    log_step "Deployment Replica Counts:"
    local api_replicas demo_replicas
    api_replicas=$(vagrant-ssh "kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "N/A")
    demo_replicas=$(vagrant-ssh "kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "N/A")
    
    echo "Dev API App replicas: $api_replicas"
    echo "Dev Demo App replicas: $demo_replicas"
    echo
    
    # Check workflow activity
    log_step "Workflow Activity (last 5 minutes):"
    local workflows
    workflows=$(vagrant-ssh "kubectl get workflows --all-namespaces --no-headers 2>/dev/null | grep -E '(dev-api-validation|dev-demo-validation)' | wc -l" || echo "0")
    
    echo "Recent validation workflows: $workflows"
    
    if [ "$workflows" -gt 0 ]; then
        log_step "Workflow Details:"
        vagrant-ssh "kubectl get workflows --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,STATUS:.status.phase,AGE:.metadata.creationTimestamp --no-headers 2>/dev/null | grep -E '(dev-api-validation|dev-demo-validation)' | head -3" || echo "  No workflow details available"
    fi
    echo
    
    # Recent events for both applications
    log_step "Recent ArgoCD Events (last 5 minutes):"
    echo
    echo "📱 dev-api-app events:"
    vagrant-ssh "kubectl get events -n argocd --field-selector involvedObject.name=dev-api-app --sort-by='.lastTimestamp' 2>/dev/null | tail -3" || echo "  No recent events"
    echo
    echo "📱 dev-demo-app events:"
    vagrant-ssh "kubectl get events -n argocd --field-selector involvedObject.name=dev-demo-app --sort-by='.lastTimestamp' 2>/dev/null | tail -3" || echo "  No recent events"
    echo
}

# Analyze results for selective sync effectiveness
analyze_results() {
    log_header "🔍 Selective Sync Analysis"
    echo
    
    # Check if selective sync worked
    local api_replicas demo_replicas
    api_replicas=$(vagrant-ssh "kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "0")
    demo_replicas=$(vagrant-ssh "kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null" || echo "0")
    
    # Get chart versions for Helm-based applications
    local api_chart_version demo_chart_version
    api_chart_version=$(vagrant-ssh "kubectl get application dev-api-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null" || echo "Unknown")
    demo_chart_version=$(vagrant-ssh "kubectl get application dev-demo-app -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null" || echo "Unknown")
    
    # Get expected chart version from local Chart.yaml
    local expected_api_version
    expected_api_version=$(grep "^version:" "environments/dev-api-app/Chart.yaml" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "Unknown")
    
    echo "Expected Behavior Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check if dev-api-app scaled
    if [ "$api_replicas" -gt 1 ]; then
        success "✅ dev-api-app scaled to $api_replicas replicas (EXPECTED)"
    else
        warn "⚠️  dev-api-app still has $api_replicas replica (unexpected)"
    fi
    
    # Check if dev-demo-app remained unchanged
    if [ "$demo_replicas" -eq 1 ]; then
        success "✅ dev-demo-app remained at $demo_replicas replica (EXPECTED - selective sync worked)"
    else
        warn "⚠️  dev-demo-app changed to $demo_replicas replicas (unexpected)"
    fi
    
    # Check Helm chart versions (not Git revisions for Helm-based apps)
    echo
    echo "Helm Chart Version Analysis:"
    if [[ "$api_chart_version" == "$expected_api_version" ]]; then
        success "✅ dev-api-app synced to expected chart version $api_chart_version"
    else
        warn "⚠️  dev-api-app at chart version $api_chart_version, expected $expected_api_version"
    fi
    
    # For Helm apps, we don't expect the demo app to change versions
    log "ℹ️  dev-demo-app at chart version $demo_chart_version (should remain unchanged)"
    log "   Helm-based apps use chart versions, not Git commit hashes for sync tracking"
    
    echo
    echo "Selective Sync Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$api_replicas" -gt 1 ] && [ "$demo_replicas" -eq 1 ]; then
        success "🎉 SELECTIVE SYNC WORKING PERFECTLY!"
        echo "   • Only dev-api-app was affected by the change"
        echo "   • dev-demo-app remained stable and unchanged"
        echo "   • Each application syncs independently based on its path"
    else
        warn "⚠️  Selective sync may not be working as expected"
        echo "   • Check ArgoCD application configurations"
        echo "   • Verify path-based watching is configured correctly"
    fi
    
    echo
}

# Export state management functions
export -f show_initial_state monitor_selective_sync show_results analyze_results
