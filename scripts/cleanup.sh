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
    
    # Remove individual applications
    log_info "Removing individual applications..."
    
    for app in dev-demo-app production-demo-app; do
        if kubectl get application "$app" -n argocd &> /dev/null; then
            log_info "Removing application: $app"
            kubectl delete application "$app" -n argocd
            log_success "Application $app removed"
        else
            log_warning "Application $app not found"
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
    local apps_remaining
    apps_remaining=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -E "(dev-demo-app|production-demo-app)" | wc -l || echo "0")
    
    if [ "$apps_remaining" -eq 0 ]; then
        log_success "✅ No demo applications remaining"
    else
        log_warning "⚠️  $apps_remaining demo applications still exist"
    fi
    
    # Check namespaces
    local ns_remaining
    ns_remaining=$(kubectl get namespaces --no-headers 2>/dev/null | grep -E "(demo-app-dev|demo-app-prod)" | wc -l || echo "0")
    
    if [ "$ns_remaining" -eq 0 ]; then
        log_success "✅ No demo namespaces remaining"
    else
        log_warning "⚠️  $ns_remaining demo namespaces still exist"
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
    echo "  • Applications 'dev-demo-app' and 'production-demo-app'"
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
    log_warning "This will remove the ArgoCD selective sync demo:"
    echo "  • Applications 'dev-demo-app' and 'production-demo-app'"
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
