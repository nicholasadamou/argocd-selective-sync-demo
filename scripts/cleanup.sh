#!/bin/bash

# cleanup.sh
# Script to clean up the ArgoCD app-of-apps pattern demo

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
    log_info "Starting cleanup of ArgoCD app-of-apps pattern demo..."
    echo
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Remove environment controllers (this will automatically cascade to individual applications)
    log_info "Removing environment controllers..."
    
    for controller in dev-environment-controller production-environment-controller; do
        if kubectl get application "$controller" -n argocd &> /dev/null; then
            log_info "Removing environment controller: $controller"
            kubectl delete application "$controller" -n argocd
            log_success "Environment controller $controller removed"
        else
            log_warning "Environment controller $controller not found"
        fi
    done
    
    # Wait a moment for environment controllers to clean up individual applications
    log_info "Waiting for environment controllers to clean up individual applications..."
    sleep 8
    
    # Fallback: Remove any remaining individual applications
    log_info "Checking for any remaining individual applications..."
    for app in dev-demo-app dev-api-app production-demo-app production-api-app; do
        if kubectl get application "$app" -n argocd &> /dev/null; then
            log_info "Removing remaining application: $app"
            kubectl delete application "$app" -n argocd
            log_success "Application $app removed"
        fi
    done
    
    # Remove namespaces
    log_info "Removing demo namespaces..."
    
    for ns in dev-demo-app dev-api-app production-demo-app production-api-app; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_info "Removing namespace: $ns"
            kubectl delete namespace "$ns" --timeout=60s
            log_success "Namespace $ns removed"
        else
            log_warning "Namespace $ns not found"
        fi
    done
    
    # Remove workflows and workflow templates
    log_info "Removing Argo Workflows components..."
    
    # Remove any running workflows (check all namespaces since workflows run in app namespaces)
    local workflows
    workflows=$(kubectl get workflows --all-namespaces --no-headers 2>/dev/null | grep -E "(dev-.*-validation|production-.*-validation)" | awk '{print $1,$2}' | tr ' ' '/' || true)
    if [ -n "$workflows" ]; then
        log_info "Removing validation workflows..."
        for workflow in $workflows; do
            local ns=$(echo $workflow | cut -d'/' -f1)
            local name=$(echo $workflow | cut -d'/' -f2)
            kubectl delete workflow "$name" -n "$ns" 2>/dev/null || log_warning "Workflow $name in $ns may not exist"
        done
        log_success "Validation workflows removed"
    else
        log_info "No validation workflows found"
    fi
    
    # Remove workflow templates
    for template in dev-validation-workflow production-validation-workflow; do
        if kubectl get workflowtemplate "$template" -n argo &> /dev/null; then
            log_info "Removing workflow template: $template"
            kubectl delete workflowtemplate "$template" -n argo
            log_success "Workflow template $template removed"
        else
            log_warning "Workflow template $template not found"
        fi
    done
    
    # Remove workflow service account (but keep the namespace)
    if kubectl get serviceaccount argo-workflow -n argo &> /dev/null; then
        log_info "Removing workflow service account and RBAC..."
        kubectl delete serviceaccount argo-workflow -n argo
        kubectl delete role argo-workflow-role -n argo 2>/dev/null || true
        kubectl delete rolebinding argo-workflow-binding -n argo 2>/dev/null || true
        log_success "Workflow RBAC components removed"
    else
        log_info "Workflow service account not found"
    fi
    
    # Verify cleanup
    echo
    log_info "Verifying cleanup..."
    
    # Check applications
    local apps_remaining
    apps_remaining=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -E "(dev-demo-app|dev-api-app|production-demo-app|production-api-app|dev-environment-controller|production-environment-controller)" | wc -l 2>/dev/null || echo "0")
    # Trim whitespace and ensure it's a valid integer
    apps_remaining=$(echo "$apps_remaining" | tr -d '\n\r\t ' || echo "0")
    apps_remaining=${apps_remaining:-0}
    
    if [ "$apps_remaining" -eq 0 ] 2>/dev/null; then
        log_success "✅ No demo applications remaining"
    else
        log_warning "⚠️  $apps_remaining demo applications still exist"
    fi
    
    # Check namespaces
    local ns_remaining
    ns_remaining=$(kubectl get namespaces --no-headers 2>/dev/null | grep -E "(dev-demo-app|dev-api-app|production-demo-app|production-api-app)" | wc -l 2>/dev/null || echo "0")
    # Trim whitespace and ensure it's a valid integer
    ns_remaining=$(echo "$ns_remaining" | tr -d '\n\r\t ' || echo "0")
    ns_remaining=${ns_remaining:-0}
    
    if [ "$ns_remaining" -eq 0 ] 2>/dev/null; then
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
    echo "Clean up the ArgoCD app-of-apps pattern demo"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -f, --force   Skip confirmation prompt"
    echo
    echo "This will remove:"
    echo "  • Environment controllers: dev-environment-controller, production-environment-controller"
    echo "  • Applications: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • Namespaces: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • Workflow templates and validation workflows"
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
    log_warning "This will remove the ArgoCD app-of-apps pattern demo:"
    echo "  • Environment controllers: dev-environment-controller, production-environment-controller"
    echo "  • Applications: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • Namespaces: dev-demo-app, dev-api-app, production-demo-app, production-api-app"
    echo "  • Workflow templates and validation workflows"
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
