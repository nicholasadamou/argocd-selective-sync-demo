#!/bin/bash

# demo-selective-sync.sh
# Script to demonstrate ArgoCD selective sync with app-of-apps pattern

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}$1${NC}"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        log_error "git is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir &> /dev/null; then
        log_error "Not in a git repository"
        exit 1
    fi
    
    # Check if remote origin is configured
    if ! git remote get-url origin &> /dev/null; then
        log_error "No remote origin configured. Cannot push changes for ArgoCD sync."
        log_error "Please configure a remote origin: git remote add origin <repository-url>"
        exit 1
    fi
    
    # Check if we can reach the remote (basic connectivity test)
    log_info "Checking connectivity to git remote..."
    if ! git ls-remote origin &> /dev/null; then
        log_error "Cannot connect to remote git repository"
        log_error "Please check your network connection and repository access permissions"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if applications exist
    local apps_count
    apps_count=$(kubectl get applications -n default --no-headers 2>/dev/null | grep -E "(dev-api-app|dev-demo-app)" | wc -l || echo "0")
    if [ "$apps_count" -lt 2 ]; then
        log_error "Required applications not found. Please deploy the app-of-apps pattern first:"
        echo "  ./scripts/deploy-demo.sh"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Show current state
show_initial_state() {
    log_header "📊 Initial State Before Selective Sync Test"
    echo
    
    log_step "Current Applications:"
    kubectl get applications -n default | grep -E "(dev-api-app|dev-demo-app|NAME)" || echo "No matching applications found"
    echo
    
    log_step "Current Pod Count in Each Namespace:"
    echo "Dev API App namespace:"
    kubectl get pods -n dev-api-app --no-headers 2>/dev/null | grep -v "Completed\|post-sync" | wc -l || echo "0"
    echo "Dev Demo App namespace:"
    kubectl get pods -n dev-demo-app --no-headers 2>/dev/null | grep -v "Completed\|post-sync" | wc -l || echo "0"
    echo
    
    log_step "Current Replica Counts:"
    echo "Dev API App:"
    kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "N/A"
    echo "Dev Demo App:"
    kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "N/A"
    echo
    
    log_step "Current Git Revision:"
    local current_rev
    current_rev=$(kubectl get application dev-api-app -n default -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8 || echo "Unknown")
    echo "ArgoCD Sync Revision: $current_rev"
    echo "Git HEAD: $(git rev-parse --short HEAD)"
    echo
}

# Make selective change
make_selective_change() {
    log_header "🎯 Making Selective Change - Scale dev-api-app Only"
    echo
    
    # Get current replica count
    local current_replicas
    current_replicas=$(grep "replicas:" environments/dev-api-app/deployment.yaml | awk '{print $2}' || echo "1")
    local new_replicas=$((current_replicas + 1))
    
    log_step "Scaling dev-api-app from $current_replicas to $new_replicas replicas"
    log_info "This should trigger sync ONLY on dev-api-app, NOT on dev-demo-app"
    echo
    
    # Make the change
    sed -i.bak "s/replicas: $current_replicas/replicas: $new_replicas/" environments/dev-api-app/deployment.yaml
    
    log_info "File changed:"
    echo "  environments/dev-api-app/deployment.yaml: replicas $current_replicas → $new_replicas"
    echo
    
    # Show the diff
    log_step "Git diff of the change:"
    git diff environments/dev-api-app/deployment.yaml || echo "No diff available"
    echo
    
    # Commit and push
    log_step "Committing and pushing change..."
    git add environments/dev-api-app/deployment.yaml
    
    # Ensure git identity is configured for the demo
    if ! git config user.email > /dev/null 2>&1; then
        log_info "Configuring git identity for demo..."
        git config user.email "argocd-demo@example.com"
        git config user.name "ArgoCD Demo Script"
    fi
    
    git commit -m "Demo: Scale dev-api-app from $current_replicas to $new_replicas replicas (selective sync test)"
    
    # Push the change
    log_info "Pushing changes to remote repository..."
    if git push; then
        log_success "Changes pushed successfully to remote repository"
        log_info "ArgoCD should now detect the change and trigger selective sync"
    else
        log_error "Failed to push changes to remote repository"
        log_error "Demo cannot continue without pushing changes to trigger ArgoCD sync"
        exit 1
    fi
    
    echo
}

# Monitor selective sync
monitor_selective_sync() {
    log_header "👀 Monitoring Selective Sync Behavior"
    echo
    
    log_info "Monitoring for up to 60 seconds to observe selective sync..."
    echo
    
    local start_time=$(date +%s)
    local max_wait=60
    local api_app_synced=false
    local demo_app_status=""
    local initial_demo_status=""
    
    # Get initial demo app status
    initial_demo_status=$(kubectl get application dev-demo-app -n default -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    
    while [ $(($(date +%s) - start_time)) -lt $max_wait ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        printf "\r${CYAN}[%02ds]${NC} Checking application status..." $elapsed
        
        # Check dev-api-app status
        local api_status
        api_status=$(kubectl get application dev-api-app -n default -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        # Check dev-demo-app status 
        demo_app_status=$(kubectl get application dev-demo-app -n default -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        # Check if api app went through sync cycle
        if [[ "$api_status" == "Synced" ]] && ! $api_app_synced; then
            api_app_synced=true
            echo
            log_success "✅ dev-api-app has completed sync at ${elapsed}s"
        fi
        
        sleep 2
    done
    
    echo
    echo
}

# Show results
show_results() {
    log_header "📋 Selective Sync Results"
    echo
    
    # Application sync status
    log_step "Final Application Sync Status:"
    kubectl get applications -n default | grep -E "(dev-api-app|dev-demo-app|NAME)" || echo "No applications found"
    echo
    
    # Pod counts
    log_step "Pod Counts After Change:"
    local api_pods demo_pods
    api_pods=$(kubectl get pods -n dev-api-app --no-headers 2>/dev/null | grep -v "Completed\|post-sync" | wc -l || echo "0")
    demo_pods=$(kubectl get pods -n dev-demo-app --no-headers 2>/dev/null | grep -v "Completed\|post-sync" | wc -l || echo "0")
    
    echo "Dev API App pods: $api_pods"
    echo "Dev Demo App pods: $demo_pods"
    echo
    
    # Replica counts
    log_step "Deployment Replica Counts:"
    local api_replicas demo_replicas
    api_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "N/A")
    demo_replicas=$(kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "N/A")
    
    echo "Dev API App replicas: $api_replicas"
    echo "Dev Demo App replicas: $demo_replicas"
    echo
    
    # Check post-sync hook activity
    log_step "Post-Sync Hook Activity (last 5 minutes):"
    local api_hooks demo_hooks
    api_hooks=$(kubectl get jobs -n dev-api-app --no-headers 2>/dev/null | grep "post-sync" | wc -l || echo "0")
    demo_hooks=$(kubectl get jobs -n dev-demo-app --no-headers 2>/dev/null | grep "post-sync" | wc -l || echo "0")
    
    echo "Dev API App post-sync jobs: $api_hooks"
    echo "Dev Demo App post-sync jobs: $demo_hooks"
    echo
    
    # Recent events for both applications
    log_step "Recent ArgoCD Events (last 5 minutes):"
    echo
    echo "📱 dev-api-app events:"
    kubectl get events -n default --field-selector involvedObject.name=dev-api-app --sort-by='.lastTimestamp' 2>/dev/null | tail -3 || echo "  No recent events"
    echo
    echo "📱 dev-demo-app events:"
    kubectl get events -n default --field-selector involvedObject.name=dev-demo-app --sort-by='.lastTimestamp' 2>/dev/null | tail -3 || echo "  No recent events"
    echo
}

# Cleanup demo changes
cleanup_demo() {
    echo
    log_header "🧹 Cleaning Up Demo Changes"
    echo
    
    log_step "Reverting the scaling change..."
    
    # Check if there are commits to revert
    local demo_commit
    demo_commit=$(git log --oneline -1 --grep="Demo: Scale dev-api-app" --format="%h" || echo "")
    
    if [ -n "$demo_commit" ]; then
        log_info "Found demo commit: $demo_commit"
        
        # Revert the commit
        if git revert --no-edit HEAD; then
            log_success "Successfully reverted scaling commit"
        else
            log_warning "Failed to revert commit automatically. Manual cleanup may be needed."
            return 1
        fi
        
        # Show the revert commit
        log_info "Revert commit created:"
        git log --oneline -1
        echo
        
        # Push the revert commit
        log_step "Pushing revert commit to remote repository..."
        if git push; then
            log_success "Revert pushed successfully to remote repository"
            log_info "ArgoCD should now detect the revert and sync back to original state"
        else
            log_warning "Failed to push revert commit. Manual push may be needed."
            log_info "You can manually push with: git push"
        fi
        echo
        
        log_step "Waiting for ArgoCD to sync the revert..."
        echo
        
        # Wait for sync to complete
        local start_time=$(date +%s)
        local max_wait=30
        
        while [ $(($(date +%s) - start_time)) -lt $max_wait ]; do
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            printf "\r${CYAN}[%02ds]${NC} Waiting for revert to sync..." $elapsed
            
            # Check if replicas are back to 1
            local api_replicas
            api_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
            
            if [ "$api_replicas" -eq 1 ]; then
                echo
                log_success "✅ dev-api-app scaled back down to 1 replica"
                break
            fi
            
            sleep 2
        done
        
        echo
        echo
        
        # Verify final state
        log_step "Final state after cleanup:"
        local final_replicas
        final_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
        echo "Dev API App replicas: $final_replicas"
        
        if [ "$final_replicas" -eq 1 ]; then
            log_success "🎉 Cleanup completed successfully - environment restored to original state"
        else
            log_warning "⚠️  Environment may not be fully restored (replicas: $final_replicas)"
        fi
    else
        log_info "No demo commit found to revert"
    fi
    
    echo
}

# Analyze results
analyze_results() {
    log_header "🔍 Selective Sync Analysis"
    echo
    
    # Check if selective sync worked
    local api_replicas demo_replicas
    api_replicas=$(kubectl get deployment -n dev-api-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
    demo_replicas=$(kubectl get deployment -n dev-demo-app -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
    
    # Get git revisions
    local api_rev demo_rev
    api_rev=$(kubectl get application dev-api-app -n default -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8 || echo "Unknown")
    demo_rev=$(kubectl get application dev-demo-app -n default -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-8 || echo "Unknown")
    local current_git_rev=$(git rev-parse --short HEAD)
    
    echo "Expected Behavior Analysis:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check if dev-api-app scaled
    if [ "$api_replicas" -gt 1 ]; then
        log_success "✅ dev-api-app scaled to $api_replicas replicas (EXPECTED)"
    else
        log_warning "⚠️  dev-api-app still has $api_replicas replica (unexpected)"
    fi
    
    # Check if dev-demo-app remained unchanged
    if [ "$demo_replicas" -eq 1 ]; then
        log_success "✅ dev-demo-app remained at $demo_replicas replica (EXPECTED - selective sync worked)"
    else
        log_warning "⚠️  dev-demo-app changed to $demo_replicas replicas (unexpected)"
    fi
    
    # Check git revisions
    echo
    echo "Git Revision Analysis:"
    if [[ "$api_rev" == "$current_git_rev" ]]; then
        log_success "✅ dev-api-app synced to latest revision $api_rev"
    else
        log_warning "⚠️  dev-api-app at revision $api_rev, expected $current_git_rev"
    fi
    
    if [[ "$demo_rev" == "$current_git_rev" ]]; then
        log_info "ℹ️  dev-demo-app at revision $demo_rev (same as dev-api-app - ArgoCD refreshed both)"
        log_info "   This is normal - ArgoCD periodically refreshes all apps, but only changed ones sync"
    fi
    
    echo
    echo "Selective Sync Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$api_replicas" -gt 1 ] && [ "$demo_replicas" -eq 1 ]; then
        log_success "🎉 SELECTIVE SYNC WORKING PERFECTLY!"
        echo "   • Only dev-api-app was affected by the change"
        echo "   • dev-demo-app remained stable and unchanged"
        echo "   • Each application syncs independently based on its path"
    else
        log_warning "⚠️  Selective sync may not be working as expected"
        echo "   • Check ArgoCD application configurations"
        echo "   • Verify path-based watching is configured correctly"
    fi
    
    echo
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Demonstrate ArgoCD selective sync with app-of-apps pattern"
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -q, --quiet      Run with minimal output"
    echo "  -y, --yes        Skip confirmation prompts (includes cleanup)"
    echo "  --no-cleanup     Skip automatic cleanup (leave demo changes)"
    echo
    echo "This script will:"
    echo "  1. Show current state of dev applications"
    echo "  2. Scale dev-api-app deployment (increase replicas by 1)"
    echo "  3. Commit and PUSH the change to trigger ArgoCD sync"
    echo "  4. Monitor selective sync behavior"
    echo "  5. Verify that ONLY dev-api-app syncs (not dev-demo-app)"
    echo "  6. Analyze and report results"
    echo "  7. Automatically clean up demo changes (revert and push)"
    echo
    echo "Prerequisites:"
    echo "  • Kubernetes cluster access (kubectl configured)"
    echo "  • ArgoCD app-of-apps pattern deployed"
    echo "  • Git repository with remote origin configured"
    echo "  • Git push access to the remote repository"
    echo "  • Git user identity (script will configure if needed)"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive demo with cleanup prompt"
    echo "  $0 -y                 # Auto-run with automatic cleanup"
    echo "  $0 -q -y              # Quiet auto-run with cleanup"
    echo "  $0 --no-cleanup       # Interactive demo, skip cleanup"
    echo "  $0 -y --no-cleanup    # Auto-run, leave changes for inspection"
}

# Main function
main() {
    local quiet=false
    local auto_yes=false
    local skip_cleanup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            --no-cleanup)
                skip_cleanup=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set quiet mode
    if $quiet; then
        exec 3>&1
        exec > >(grep -E "(SUCCESS|ERROR|WARNING|STEP)" >&3)
    fi
    
    echo
    log_header "==========================================="
    log_header "  ArgoCD Selective Sync Demonstration"
    log_header "==========================================="
    echo
    
    check_prerequisites
    echo
    
    if ! $auto_yes; then
        log_warning "⚠️  IMPORTANT: This demo will modify your repository!"
        echo
        log_info "This script will:"
        echo "  • Create and commit a scaling change (increase dev-api-app replicas)"
        echo "  • PUSH the commit to your remote git repository"
        echo "  • Wait for ArgoCD to sync the changes"
        echo "  • Optionally revert and push the cleanup automatically"
        echo
        log_warning "Your git repository will be modified and changes will be pushed!"
        echo
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Demo cancelled"
            exit 0
        fi
        echo
    fi
    
    show_initial_state
    make_selective_change
    monitor_selective_sync
    show_results
    analyze_results
    
    # Handle cleanup based on flags and user preference
    if $skip_cleanup; then
        echo
        log_info "Cleanup skipped as requested. To manually revert:"
        echo "  git log --oneline -2"
        echo "  git revert HEAD  # Revert the scaling commit"
        echo
    elif ! $auto_yes; then
        echo
        log_info "The demo has created a scaling commit that should be reverted."
        read -p "Would you like to automatically clean up the demo changes? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo
            log_info "Skipping automatic cleanup. To manually revert:"
            echo "  git log --oneline -2"
            echo "  git revert HEAD  # Revert the scaling commit"
            echo
        else
            cleanup_demo
        fi
    else
        # Auto-cleanup in non-interactive mode
        cleanup_demo
    fi
    
    echo
    log_header "🎉 Selective Sync Demonstration Complete!"
    echo
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
