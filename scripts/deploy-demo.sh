#!/bin/bash

# deploy-demo.sh
# Script to deploy and demonstrate ArgoCD app-of-apps pattern

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
    
    # Check if ArgoCD CRDs are installed (assuming ArgoCD is running in argocd namespace)
    if ! kubectl get crd applications.argoproj.io &> /dev/null; then
        log_error "ArgoCD CRDs not found. Please install ArgoCD first."
        echo
        log_info "To install ArgoCD:"
        echo "  kubectl create namespace argocd"
        echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Deploy App-of-Apps
deploy_applications() {
    log_header "🚀 Deploying App-of-Apps Environment Controllers..."
    
    # Deploy environment controllers (which will automatically manage individual applications)
    log_info "Deploying environment controllers that will manage individual applications..."
    
    log_info "Deploying dev environment controller..."
    kubectl apply -f app-of-apps/environments/dev/dev-environment-controller.yaml
    
    log_info "Deploying production environment controller..."
    kubectl apply -f app-of-apps/environments/production/production-environment-controller.yaml
    
    log_success "Environment controllers deployed - they will automatically manage individual applications with post-sync hooks"
    
    # Give environment controllers a moment to process
    log_info "Waiting for environment controllers to sync and create applications..."
    sleep 8
    
    # Check initial status
    log_info "Checking environment controller status..."
    local dev_status prod_status
    dev_status=$(kubectl get application dev-environment-controller -n default -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Pending")
    prod_status=$(kubectl get application production-environment-controller -n default -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Pending")
    
    log_info "Dev environment controller: $dev_status"
    log_info "Production environment controller: $prod_status"
}

# Wait for applications
wait_for_applications() {
    log_info "Waiting for individual applications to be created by environment controllers..."
    
    # Temporarily disable strict error checking for this function
    set +e
    
    local max_attempts=25
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local apps_found=0
        
        # Check for all 4 applications in default namespace
        for app in dev-demo-app dev-api-app production-demo-app production-api-app; do
            if kubectl get application "$app" -n default &> /dev/null; then
                apps_found=$((apps_found + 1))
            fi
        done
        
        if [ $apps_found -eq 4 ]; then
            log_success "All applications created successfully by environment controllers"
            return 0
        fi
        
        log_info "Found $apps_found/4 applications, waiting... (attempt $((attempt+1))/$max_attempts)"
        
        # Check environment controller status after a few attempts
        if [ $attempt -eq 8 ] || [ $attempt -eq 15 ]; then
            log_info "Checking environment controller status..."
            local dev_sync_status prod_sync_status
            dev_sync_status=$(kubectl get application dev-environment-controller -n default -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            prod_sync_status=$(kubectl get application production-environment-controller -n default -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            
            log_info "Dev environment controller sync status: $dev_sync_status"
            log_info "Production environment controller sync status: $prod_sync_status"
            
            if [[ "$dev_sync_status" == *"Error"* ]] || [[ "$prod_sync_status" == *"Error"* ]]; then
                log_warning "Environment controller sync error detected"
                log_info "This is likely due to Git repository access issues"
            fi
        fi
        
        sleep 4
        ((attempt++))
    done
    
    log_warning "Not all applications were created within the timeout"
    log_info "Checking environment controller status for errors..."
    
    # Show environment controller status
    local dev_status prod_status
    dev_status=$(kubectl get application dev-environment-controller -n default -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "Unable to get status")
    prod_status=$(kubectl get application production-environment-controller -n default -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "Unable to get status")
    
    log_warning "Dev environment controller status: $dev_status"
    log_warning "Production environment controller status: $prod_status"
    
    if [[ "$dev_status" == *"authentication"* ]] || [[ "$prod_status" == *"authentication"* ]] || [[ "$dev_status" == *"repository not found"* ]] || [[ "$prod_status" == *"repository not found"* ]]; then
        log_error "Git repository access issue detected!"
        log_info "Please check:"
        echo "  1. Repository URL is correct in environment controller files"
        echo "  2. Repository credentials are properly configured"
        echo "  3. Repository exists and is accessible"
        echo "  "
        log_info "Repository secret: $(kubectl get secrets -n default -l argocd.argoproj.io/secret-type=repository -o name 2>/dev/null || echo 'None found')"
    fi
    
    log_info "Continuing with demo despite application creation issues..."
    
    # Re-enable strict error checking
    set -e
    
    return 0  # Don't fail the script
}

# Show status
show_status() {
    log_header "📊 Application Status"
    echo
    
    # Temporarily disable strict error checking
    set +e
    
    # Show environment controllers
    log_info "Environment Controllers:"
    kubectl get applications -n default -l app-type=environment-controller -o wide 2>/dev/null || log_warning "No environment controllers found"
    echo
    
    # Show individual applications
    log_info "Individual Applications:"
    kubectl get applications -n default --show-labels 2>/dev/null | grep -v environment-controller || log_warning "No individual applications found"
    echo
    
    # Show namespaces
    log_info "Application Namespaces:"
    kubectl get ns | grep -E "(dev-demo-app|dev-api-app|production-demo-app|production-api-app)" || log_info "Namespaces not created yet"
    echo
    
    # Show pods if namespaces exist
    for ns in dev-demo-app dev-api-app production-demo-app production-api-app; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log_info "Pods in $ns:"
            kubectl get pods -n "$ns" -o wide 2>/dev/null || echo "  No pods yet"
            echo
        fi
    done
    
    # Re-enable strict error checking
    set -e
}

# Demonstrate selective sync
demonstrate_selective_sync() {
    log_header "🎯 App-of-Apps Pattern Demonstration"
    echo
    
    log_info "This demo shows ArgoCD app-of-apps pattern with selective sync and per-app post-sync hooks:"
    echo
    echo "1. Environment Controllers (Parent Apps) manage individual applications:"
    echo "   - dev-environment-controller → manages dev applications"
    echo "   - production-environment-controller → manages production applications"
    echo
    echo "2. Individual Applications (Child Apps) with dedicated hooks:"
    echo "   - dev-demo-app (watches: environments/dev-demo-app/) + demo validation hook"
    echo "   - dev-api-app (watches: environments/dev-api-app/) + API-specific validation hook"
    echo "   - production-demo-app (watches: environments/production-demo-app/) + enhanced demo hook"
    echo "   - production-api-app (watches: environments/production-api-app/) + comprehensive API hook"
    echo
    echo "3. Per-application sync behavior:"
    echo "   - DEV apps: Quick validation, automated sync, lower resources"
    echo "   - PRODUCTION apps: Enhanced validation, manual sync, higher resources"
    echo
    echo "4. Selective syncing behavior:"
    echo "   - Changes to environments/dev-demo-app/ → ONLY dev-demo-app syncs + demo hook runs"
    echo "   - Changes to environments/production-api-app/ → ONLY production-api-app syncs + API hook runs"
    echo "   - Other applications remain completely untouched"
    echo
    echo "5. App-of-Apps benefits:"
    echo "   - Granular control: Each app has its own lifecycle and hooks"
    echo "   - Environment separation: Clear boundaries via environment controllers"
    echo "   - Per-app customization: Different policies, retries, and validation per app"
    echo
    log_info "Try this to see selective sync in action:"
    echo "  # Update only dev demo app (only dev-demo-app syncs)"
    echo "  vim environments/dev-demo-app/deployment.yaml  # Change replicas from 1 to 2"
    echo "  git add environments/dev-demo-app/ && git commit -m 'Scale dev demo app' && git push"
    echo
    echo "  # Update only production API app (only production-api-app syncs)"
    echo "  vim environments/production-api-app/deployment.yaml  # Change replicas from 3 to 5"
    echo "  git add environments/production-api-app/ && git commit -m 'Scale prod API app' && git push"
    echo
    echo "4. Monitor applications by environment:"
    echo "   kubectl get applications -l environment=dev"
    echo "   kubectl get applications -l environment=production"
    echo "   kubectl get applications -l service=demo-app"
    echo "   kubectl get applications -l service=api-app"
}

# Show useful commands
show_commands() {
    echo
    log_header "🛠️  Useful Commands"
    echo
    
    log_info "Monitor environment controllers:"
    echo "  kubectl get applications -n default -l app-type=environment-controller -w"
    echo
    
    log_info "Monitor individual applications:"
    echo "  kubectl get applications -n default --show-labels -w"
    echo
    
    log_info "Check application details:"
    echo "  kubectl describe application dev-demo-app -n default"
    echo "  kubectl describe application production-api-app -n default"
    echo
    
    log_info "Access applications:"
    echo "  # Dev Demo App (web frontend)"
    echo "  kubectl port-forward svc/demo-app-dev-service -n dev-demo-app 8080:80"
    echo "  # Dev API App (backend)"
    echo "  kubectl port-forward svc/api-app-dev-service -n dev-api-app 8090:3000"
    echo "  # Production Demo App"
    echo "  kubectl port-forward svc/demo-app-production-service -n production-demo-app 8081:80"
    echo "  # Production API App"
    echo "  kubectl port-forward svc/api-app-production-service -n production-api-app 8091:3000"
    echo
    
    log_info "Force sync specific apps:"
    echo "  kubectl patch application dev-demo-app -n default --type merge --patch '{\"operation\":{\"sync\":{}}}'"
    echo "  kubectl patch application production-api-app -n default --type merge --patch '{\"operation\":{\"sync\":{}}}'"
    echo
    
    log_info "Monitor by environment:"
    echo "  kubectl get all -n dev-demo-app"
    echo "  kubectl get all -n production-api-app"
    echo "  kubectl get applications -l environment=dev -w"
    echo
    
    log_info "Clean up:"
    echo "  ./scripts/cleanup.sh"
    echo "  # Or manually:"
    echo "  kubectl delete application dev-environment-controller -n default"
    echo "  kubectl delete application production-environment-controller -n default"
}

# Main function
main() {
    echo
    log_header "=========================================="
    log_header "  ArgoCD App-of-Apps Pattern Demo"
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
