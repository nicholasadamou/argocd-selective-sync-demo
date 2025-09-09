#!/bin/bash

# cleanup.sh
# Script to clean up the ArgoCD selective sync demo

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Main cleanup function
cleanup() {
    log_info "Starting cleanup of ArgoCD selective sync demo..."
    echo
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Remove parent app-of-apps application (this will cascade delete all child apps)
    log_info "Removing app-of-apps parent application..."
    
    if kubectl get application app-of-apps -n argocd &> /dev/null; then
        log_info "Removing parent application: app-of-apps"
        kubectl delete application app-of-apps -n argocd
        log_success "Parent app-of-apps removed (child apps will be cascaded)"
    else
        log_warning "App-of-apps parent application not found"
    fi
    
    # Also clean up environment ApplicationSets and service apps in case they exist
    log_info "Cleaning up any remaining environment ApplicationSets and service applications..."
    
    # Clean up ApplicationSets first
    for appset in dev-apps production-apps; do
        if kubectl get applicationset "$appset" -n argocd &> /dev/null; then
            log_info "Removing ApplicationSet: $appset"
            kubectl delete applicationset "$appset" -n argocd
            log_success "ApplicationSet $appset removed"
        fi
    done
    
    # Clean up any remaining individual applications
    for app in dev-demo-app dev-api-service production-demo-app production-api-service; do
        if kubectl get application "$app" -n argocd &> /dev/null; then
            log_info "Removing application: $app"
            kubectl delete application "$app" -n argocd
            log_success "Application $app removed"
        fi
    done
    
    # Wait a moment for applications to be cleaned up
    log_info "Waiting for applications to be cleaned up..."
    sleep 5
    
    # Remove namespaces
    log_info "Removing demo namespaces..."
    
    for ns in demo-app-dev demo-app-prod; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_info "Removing namespace: $ns"
            kubectl delete namespace "$ns" --timeout=60s
            log_success "Namespace $ns removed"
        else
            log_warning "Namespace $ns not found"
        fi
    done
    
    # Verify cleanup
    echo
    log_info "Verifying cleanup..."
    
    # Check applications
    local apps_count
    apps_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -cE "(app-of-apps|dev-apps|production-apps|dev-demo-app|dev-api-service|production-demo-app|production-api-service)" 2>/dev/null || echo "0")
    
    if [ "$apps_count" -eq 0 ] 2>/dev/null; then
        log_success "✅ No demo applications remaining"
    elif [[ "$apps_count" =~ ^[0-9]+$ ]] && [ "$apps_count" -gt 0 ]; then
        log_warning "⚠️  $apps_count demo applications still exist"
    else
        log_success "✅ No demo applications remaining"
    fi
    
    # Check namespaces
    local ns_count
    ns_count=$(kubectl get namespaces --no-headers 2>/dev/null | grep -cE "(demo-app-dev|demo-app-prod)" 2>/dev/null || echo "0")
    
    if [ "$ns_count" -eq 0 ] 2>/dev/null; then
        log_success "✅ No demo namespaces remaining"
    elif [[ "$ns_count" =~ ^[0-9]+$ ]] && [ "$ns_count" -gt 0 ]; then
        log_warning "⚠️  $ns_count demo namespaces still exist"
    else
        log_success "✅ No demo namespaces remaining"
    fi
    
    echo
    log_success "🧹 Cleanup completed!"
    echo
    log_info "ArgoCD itself is still running and ready for new deployments."
    log_info "To redeploy the demo, run: ./scripts/deploy-demo.sh"
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clean up the ArgoCD selective sync demo"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -f, --force   Skip confirmation prompt"
    echo
    echo "This will remove:"
    echo "  • App-of-apps parent application and all environment ApplicationSets"
    echo "  • Environment ApplicationSets: dev-apps, production-apps"
    echo "  • Service applications: dev-demo-app, dev-api-service, production-demo-app, production-api-service"
    echo "  • Namespaces 'demo-app-dev' and 'demo-app-prod'"
    echo "  • Post-sync validation jobs"
    echo
    echo "ArgoCD itself will remain running."
}

# Main function
main() {
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo
    log_warning "This will remove the ArgoCD app-of-apps selective sync demo:"
    echo "  • App-of-apps parent application and all environment ApplicationSets"
    echo "  • Environment ApplicationSets: dev-apps, production-apps"
    echo "  • Service applications: dev-demo-app, dev-api-service, production-demo-app, production-api-service"
    echo "  • Namespaces 'demo-app-dev' and 'demo-app-prod'"
    echo "  • Post-sync validation jobs"
    echo
    log_info "ArgoCD itself will remain running."
    
    if [ "$force" = false ]; then
        read -p "Are you sure you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    echo
    cleanup
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
