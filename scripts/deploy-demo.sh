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

# Deploy app-of-apps parent application
deploy_applications() {
    log_header "🚀 Deploying App-of-Apps parent application..."
    
    # Deploy parent app-of-apps application
    log_info "Deploying parent application that manages all child applications..."
    kubectl apply -f app-of-apps.yaml
    
    log_success "App-of-Apps parent application deployed"
    log_info "This will automatically create the environment controllers:"
    echo "  - dev-apps (manages all dev applications)"
    echo "  - production-apps (manages all production applications)"
    echo
    log_info "Each environment controller will then create its service applications:"
    echo "  - dev-apps → dev-demo-app, dev-api-service"
    echo "  - production-apps → production-demo-app, production-api-service"
}

# Wait for applications
wait_for_applications() {
    log_info "Waiting for parent app and child applications to be created..."
    
    local max_attempts=30
    local attempt=0
    
    # First wait for parent app
    log_info "Waiting for app-of-apps parent application..."
    while [ $attempt -lt 10 ]; do
        if kubectl get application app-of-apps -n argocd &> /dev/null; then
            log_success "App-of-Apps parent application created"
            break
        fi
        log_info "Waiting for parent app... (attempt $((attempt+1))/10)"
        sleep 3
        ((attempt++))
    done
    
    # Then wait for environment controllers
    log_info "Waiting for environment controllers to be created..."
    attempt=0
    while [ $attempt -lt 15 ]; do
        local env_controllers=0
        local expected_controllers=("dev-apps" "production-apps")
        
        for controller in "${expected_controllers[@]}"; do
            if kubectl get application "$controller" -n argocd &> /dev/null; then
                ((env_controllers++))
            fi
        done
        
        if [ $env_controllers -eq 2 ]; then
            log_success "Both environment controllers created successfully"
            break
        fi
        
        log_info "Found $env_controllers/2 environment controllers, waiting... (attempt $((attempt+1))/15)"
        sleep 3
        ((attempt++))
    done
    
    # Finally wait for service applications
    log_info "Waiting for service applications to be created by environment controllers..."
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local apps_found=0
        local expected_apps=("dev-demo-app" "dev-api-service" "production-demo-app" "production-api-service")
        
        for app in "${expected_apps[@]}"; do
            if kubectl get application "$app" -n argocd &> /dev/null; then
                ((apps_found++))
            fi
        done
        
        if [ $apps_found -eq 4 ]; then
            log_success "All 4 service applications created successfully"
            return 0
        fi
        
        log_info "Found $apps_found/4 service applications, waiting... (attempt $((attempt+1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_warning "Not all service applications were created within the timeout"
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
    log_header "🎯 App-of-Apps + Selective Sync Demonstration"
    echo
    
    log_info "This demo shows ArgoCD App-of-Apps pattern with selective sync and post-sync hooks:"
    echo
    echo "1. App-of-Apps Hierarchy:"
    echo "   - app-of-apps (root) manages 2 environment controllers:"
    echo "     * dev-apps (dev environment controller)"
    echo "     * production-apps (production environment controller)"
    echo "   - Each environment controller manages its service applications:"
    echo "     * dev-apps → dev-demo-app, dev-api-service"
    echo "     * production-apps → production-demo-app, production-api-service"
    echo
    echo "2. Selective Syncing per Service:"
    echo "   - dev-demo-app watches only: deployment.yaml, service.yaml, post-sync-hook.yaml"
    echo "   - dev-api-service watches only: api-service-*.yaml files"
    echo "   - production-demo-app watches only: deployment.yaml, service.yaml, post-sync-hook.yaml"
    echo "   - production-api-service watches only: api-service-*.yaml files"
    echo
    echo "3. Each app has its own post-sync validation hooks:"
    echo "   - DEV apps: Quick validation (10-15s wait, 2 retries)"
    echo "   - PRODUCTION apps: Enhanced validation (20-30s wait, 3 retries)"
    echo
    echo "4. Selective syncing behavior examples:"
    echo "   - Update environments/demo-app/dev/deployment.yaml → ONLY dev-demo-app syncs"
    echo "   - Update environments/api-service/dev/deployment.yaml → ONLY dev-api-service syncs"
    echo "   - Update environments/demo-app/production/service.yaml → ONLY production-demo-app syncs"
    echo "   - Update environments/api-service/production/service.yaml → ONLY production-api-service syncs"
    echo
    log_info "Try these examples to see selective sync + hooks in action:"
    echo "  # Update demo-app in dev (only dev-demo-app syncs)"
    echo "  vim environments/demo-app/dev/deployment.yaml  # Change replicas from 1 to 2"
    echo "  git add environments/demo-app/dev/deployment.yaml && git commit -m 'Scale dev demo-app' && git push"
    echo
    echo "  # Update api-service in production (only production-api-service syncs)"
    echo "  vim environments/api-service/production/deployment.yaml  # Change replicas from 3 to 5"
    echo "  git add environments/api-service/production/deployment.yaml && git commit -m 'Scale prod api-service' && git push"
    echo
    echo "5. Monitor post-sync hooks:"
    echo "   kubectl get jobs -n demo-app-dev     # See dev validation jobs"
    echo "   kubectl get jobs -n demo-app-prod    # See production validation jobs"
    echo "   kubectl logs -l job-name=dev-post-sync-validation -n demo-app-dev"
    echo "   kubectl logs -l job-name=dev-api-post-sync-validation -n demo-app-dev"
    echo "   kubectl logs -l job-name=production-post-sync-validation -n demo-app-prod"
    echo "   kubectl logs -l job-name=production-api-post-sync-validation -n demo-app-prod"
}

# Show useful commands
show_commands() {
    log_header "🔧️  Useful Commands"
    echo
    
    log_info "Monitor all applications (parent + children):"
    echo "  kubectl get applications -n argocd -w"
    echo
    
    log_info "Check parent app-of-apps:"
    echo "  kubectl describe application app-of-apps -n argocd"
    echo
    
    log_info "Check individual child applications:"
    echo "  kubectl describe application dev-demo-app -n argocd"
    echo "  kubectl describe application dev-api-service -n argocd"
    echo "  kubectl describe application production-demo-app -n argocd"
    echo "  kubectl describe application production-api-service -n argocd"
    echo
    
    log_info "Access applications:"
    echo "  # Development - demo-app"
    echo "  kubectl port-forward svc/demo-app-service -n demo-app-dev 8080:80"
    echo "  # Development - api-service"
    echo "  kubectl port-forward svc/api-service -n demo-app-dev 8082:80"
    echo "  # Production - demo-app"
    echo "  kubectl port-forward svc/demo-app-service -n demo-app-prod 8081:80"
    echo "  # Production - api-service"
    echo "  kubectl port-forward svc/api-service -n demo-app-prod 8083:80"
    echo
    
    log_info "Force sync individual applications:"
    echo "  kubectl patch application dev-demo-app -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo "  kubectl patch application dev-api-service -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo "  kubectl patch application production-demo-app -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo "  kubectl patch application production-api-service -n argocd --type merge --patch '{\"operation\":{\"sync\":{}}}'" 
    echo
    
    log_info "Monitor post-sync hooks (all services):"
    echo "  kubectl get jobs -n demo-app-dev -w"
    echo "  kubectl get jobs -n demo-app-prod -w"
    echo "  kubectl logs -f job/dev-post-sync-validation -n demo-app-dev"
    echo "  kubectl logs -f job/dev-api-post-sync-validation -n demo-app-dev"
    echo "  kubectl logs -f job/production-post-sync-validation -n demo-app-prod"
    echo "  kubectl logs -f job/production-api-post-sync-validation -n demo-app-prod"
    echo
    
    log_info "Clean up:"
    echo "  ./scripts/cleanup.sh"
    echo "  # Or manually:"
    echo "  kubectl delete application app-of-apps -n argocd  # This removes parent + all children"
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
