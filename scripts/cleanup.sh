#!/bin/bash

# cleanup.sh
# Script to clean up the ArgoCD app-of-apps pattern demo

set -euo pipefail

# Config
ARGOCD_NS=${ARGOCD_NS:-argocd}

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

force_remove_finalizers() {
    # Remove finalizers from stuck ArgoCD Applications in $ARGOCD_NS
    local stuck
    stuck=$(kubectl get application -n "$ARGOCD_NS" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.deletionTimestamp != null and (.metadata.finalizers | length) > 0) | .metadata.name' || true)
    if [[ -n "${stuck}" ]]; then
        while IFS= read -r app; do
            [[ -z "$app" ]] && continue
            log_warning "Force-removing finalizers from application: $app"
            kubectl patch application "$app" -n "$ARGOCD_NS" --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]' || true
        done <<< "$stuck"
    fi
}

# Main cleanup function
cleanup() {
    log_info "Starting cleanup of ArgoCD demo resources in namespace '$ARGOCD_NS'..."
    echo
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found; finalizer cleanup for stuck Applications may be limited"
    fi

    # 1) Delete ApplicationSets for this demo (if present)
    log_info "Deleting ApplicationSets labeled app.kubernetes.io/part-of=selective-sync-demo (if any)..."
    kubectl delete applicationsets -n "$ARGOCD_NS" -l app.kubernetes.io/part-of=selective-sync-demo --ignore-not-found || true

    # 2) Delete known Applications
    log_info "Deleting Applications (dev/prod apps and environment controllers)..."
    kubectl delete application \
        dev-api-app dev-demo-app dev-environment-controller \
        production-api-app production-demo-app production-environment-controller \
        -n "$ARGOCD_NS" --ignore-not-found || true

    # 3) Force-remove finalizers from any stuck Applications
    force_remove_finalizers || true

    # 4) Verify ArgoCD namespace is clear of Applications and ApplicationSets
    log_info "Verifying ArgoCD namespace is clear of Applications and ApplicationSets..."
    if kubectl get applications,applicationsets -n "$ARGOCD_NS" --no-headers 2>/dev/null | grep -q .; then
        log_warning "Some ArgoCD resources remain in '$ARGOCD_NS'. Attempting finalizer cleanup again..."
        force_remove_finalizers || true
        kubectl get applications,applicationsets -n "$ARGOCD_NS" || true
    else
        log_success "No Applications or ApplicationSets remain in '$ARGOCD_NS'"
    fi

    # 5) Delete demo namespaces
    log_info "Deleting demo namespaces (if they exist)..."
    kubectl delete namespace dev-api-app dev-demo-app production-api-app production-demo-app --ignore-not-found || true

    # 6) Final verification
    echo
    log_info "Final verification..."
    if kubectl get applications,applicationsets -n "$ARGOCD_NS" --no-headers 2>/dev/null | grep -q .; then
        log_warning "⚠️  ArgoCD resources still present in '$ARGOCD_NS'"
    else
        log_success "✅ No ArgoCD Applications/ApplicationSets in '$ARGOCD_NS'"
    fi

    if kubectl get namespaces --no-headers 2>/dev/null | grep -E "^(dev-api-app|dev-demo-app|production-api-app|production-demo-app)\s" >/dev/null; then
        log_warning "⚠️  Some demo namespaces still exist"
        kubectl get namespaces | grep -E "(dev-api-app|dev-demo-app|production-api-app|production-demo-app)" || true
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
    echo "Clean up the ArgoCD app-of-apps pattern demo"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -f, --force   Skip confirmation prompt"
    echo
    echo "Environment variables:"
    echo "  ARGOCD_NS       ArgoCD namespace (default: argocd)"
    echo
    echo "This will remove:"
    echo "  • Environment controllers: dev-environment-controller, production-environment-controller"
    echo "  • Applications: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • ApplicationSets labeled app.kubernetes.io/part-of=selective-sync-demo (if any)"
    echo "  • Namespaces: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
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
    log_warning "This will remove the ArgoCD app-of-apps pattern demo from namespace '$ARGOCD_NS':"
    echo "  • Environment controllers: dev-environment-controller, production-environment-controller"
    echo "  • Applications: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • ApplicationSets labeled app.kubernetes.io/part-of=selective-sync-demo (if any)"
    echo "  • Namespaces: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
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
