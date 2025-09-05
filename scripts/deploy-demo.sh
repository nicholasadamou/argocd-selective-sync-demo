#!/bin/bash

# deploy-demo.sh
# Script to deploy and demonstrate ArgoCD selective sync

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if ArgoCD is installed
    if ! kubectl get namespace argocd &> /dev/null; then
        log_error "ArgoCD namespace not found. Please install ArgoCD first."
        echo
        log_info "To install ArgoCD:"
        echo "  kubectl create namespace argocd"
        echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Deploy individual applications
deploy_applications() {
    log_header "🚀 Deploying individual ArgoCD applications..."
    
    # Deploy dev application
    log_info "Deploying dev application with post-sync hooks..."
    kubectl apply -f ../apps/dev/demo-app.yaml
    
    # Deploy production application  
    log_info "Deploying production application with enhanced post-sync hooks..."
    kubectl apply -f ../apps/production/demo-app.yaml
    
    log_success "Both applications deployed with post-sync hooks"
}

# Wait for applications
wait_for_applications() {
    log_info "Waiting for applications to be created..."
    
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local apps_found=0
        
        if kubectl get application dev-demo-app -n argocd &> /dev/null; then
            ((apps_found++))
        fi
        
        if kubectl get application production-demo-app -n argocd &> /dev/null; then
            ((apps_found++))
        fi
        
        if [ $apps_found -eq 2 ]; then
            log_success "Both applications created successfully"
            return 0
        fi
        
        log_info "Found $apps_found/2 applications, waiting... (attempt $((attempt+1))/$max_attempts)"
        sleep 3
        ((attempt++))
    done
    
    log_warning "Not all applications were created within the timeout"
}

# Show status
show_status() {
    log_header "📊 Application Status"
    echo
    
    # Show applications
    log_info "ArgoCD Applications:"
    kubectl get applications -n argocd -o wide 2>/dev/null || log_warning "No applications found"
    echo
    
    # Show namespaces
    log_info "Application Namespaces:"
    kubectl get ns | grep -E "(demo-app-dev|demo-app-prod)" || log_info "Namespaces not created yet"
    echo
    
    # Show pods if namespaces exist
    for ns in demo-app-dev demo-app-prod; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_info "Pods in $ns:"
            kubectl get pods -n "$ns" -o wide 2>/dev/null || echo "  No pods yet"
            echo
        fi
    done
}

# Demonstrate selective sync
demonstrate_selective_sync() {
    log_header "🎯 Selective Sync Demonstration"
    echo
    
    log_info "This demo shows ArgoCD selective sync with post-sync hooks:"
    echo
    echo "1. Two applications are created:"
    echo "   - dev-demo-app (watches: environments/dev/)"
    echo "   - production-demo-app (watches: environments/production/)"
    echo
    echo "2. Each app has its own post-sync validation hooks:"
    echo "   - DEV: Quick validation (10s wait, 2 retries)"
    echo "   - PRODUCTION: Enhanced validation (20s wait, 3 retries, stricter checks)"
    echo
    echo "3. Selective syncing behavior:"
    echo "   - Changes to environments/dev/ → ONLY dev app syncs + dev hook runs"
    echo "   - Changes to environments/production/ → ONLY production app syncs + production hook runs"
    echo
    log_info "Try this to see selective sync + hooks in action:"
    echo "  # Update dev environment (only dev app syncs + dev post-sync hook runs)"
    echo "  vim environments/dev/deployment.yaml  # Change replicas from 1 to 2"
    echo "  git add environments/dev/ && git commit -m 'Scale dev app' && git push"
    echo
    echo "  # Update production environment (only production app syncs + production post-sync hook runs)"
    echo "  vim environments/production/deployment.yaml  # Change replicas from 3 to 5"
    echo "  git add environments/production/ && git commit -m 'Scale prod app' && git push"
    echo
    echo "4. Monitor post-sync hooks:"
    echo "   kubectl get jobs -n demo-app-dev     # See dev validation jobs"
    echo "   kubectl get jobs -n demo-app-prod    # See production validation jobs"
    echo "   kubectl logs -l job-name=dev-post-sync-validation -n demo-app-dev"
    echo "   kubectl logs -l job-name=production-post-sync-validation -n demo-app-prod"
}

# Show useful commands
show_commands() {
    log_header "🛠️  Useful Commands"
    echo
    
    log_info "Monitor applications:"
    echo "  kubectl get applications -n argocd -w"
    echo
    
    log_info "Check application details:"
    echo "  kubectl describe application dev-demo-app -n argocd"
    echo "  kubectl describe application production-demo-app -n argocd"
    echo
    
    log_info "Access applications:"
    echo "  # Development"
    echo "  kubectl port-forward svc/demo-app-service -n demo-app-dev 8080:80"
    echo "  # Production"
    echo "  kubectl port-forward svc/demo-app-service -n demo-app-prod 8081:80"
    echo
    
    log_info "Force sync:"
    echo "  kubectl patch application dev-demo-app -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo "  kubectl patch application production-demo-app -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo
    
    log_info "Monitor post-sync hooks:"
    echo "  kubectl get jobs -n demo-app-dev -w"
    echo "  kubectl get jobs -n demo-app-prod -w"
    echo "  kubectl logs -f job/dev-post-sync-validation -n demo-app-dev"
    echo "  kubectl logs -f job/production-post-sync-validation -n demo-app-prod"
    echo
    
    log_info "Clean up:"
    echo "  ./scripts/cleanup.sh"
    echo "  # Or manually:"
    echo "  kubectl delete application dev-demo-app production-demo-app -n argocd"
    echo "  kubectl delete namespace demo-app-dev demo-app-prod"
}

# Main function
main() {
    echo
    log_header "=========================================="
    log_header "  ArgoCD Selective Sync Demo"
    log_header "=========================================="
    echo
    
    check_prerequisites
    deploy_applications
    wait_for_applications
    
    echo
    show_status
    demonstrate_selective_sync
    show_commands
    
    log_success "Demo deployment complete!"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
