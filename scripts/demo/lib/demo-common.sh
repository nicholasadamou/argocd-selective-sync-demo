#!/bin/bash

# demo-common.sh
# Common functions and variables for the ArgoCD selective sync demo

# Source the Helm common library for Nexus operations
DEMO_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
SCRIPTS_DIR="$(dirname "$(dirname "$DEMO_LIB_DIR")")"
source "$SCRIPTS_DIR/helm/lib/nexus-common.sh"

# Additional colors for demo-specific output
PURPLE='\033[0;35m'
CYAN='\033[0;36m'

# Demo-specific configuration
DRY_RUN=false

# Enhanced logging functions for demo
log_header() {
    echo -e "${PURPLE}$1${NC}"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Helper function for kubectl commands
kube_exec() {
    kubectl "$@"
}

# Check prerequisites specific to the demo
check_demo_prerequisites() {
    log "Checking prerequisites for Helm-based selective sync demo..."
    
    # Use common library's prerequisite checking with Helm-specific requirements
    check_prerequisites "kubectl git helm curl docker"
    
    # Check if we're in project root directory
    if [ ! -f "README.md" ] || [ ! -d "environments" ]; then
        error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check if remote origin is configured
    if ! git remote get-url origin &> /dev/null; then
        error "No remote origin configured. Cannot push changes for ArgoCD sync."
        error "Please configure a remote origin: git remote add origin <repository-url>"
        exit 1
    fi
    
    # Check connectivity to git remote
    log "Checking connectivity to git remote..."
    if ! git ls-remote origin &> /dev/null; then
        error "Cannot connect to remote git repository"
        error "Please check your network connection and repository access permissions"
        exit 1
    fi
    
    # Verify ArgoCD applications are configured for Helm
    if ! grep -q "chart:" app-of-apps/applications/dev/templates/dev-api-app.yaml 2>/dev/null; then
        error "ArgoCD applications are not configured for Helm charts"
        error "This demo only supports Helm-based deployments"
        exit 1
    fi
    
    # Check if helm-workflow script exists
    if [ ! -x "./scripts/helm/helm-workflow.sh" ]; then
        error "helm-workflow.sh script not found or not executable"
        exit 1
    fi
    
    # Check if applications exist in cluster
    local apps_count=0
    if kubectl get applications -n argocd --no-headers >/dev/null 2>&1; then
        apps_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -E '(dev-api-app|dev-demo-app)' | wc -l || echo "0")
        # Clean up any non-numeric characters
        apps_count=$(echo "$apps_count" | tr -cd '0-9' || echo "0")
    fi
    if [ "$apps_count" -lt 2 ]; then
        error "Required applications not found (found: $apps_count). Please deploy the app-of-apps pattern first:"
        echo "  ./scripts/deploy-demo.sh"
        exit 1
    fi
    
    success "Prerequisites check passed - Helm-based selective sync ready"
}

# Initialize demo environment
demo_init() {
    # Initialize common library
    nexus_common_init
    
    # Check demo-specific prerequisites
    check_demo_prerequisites
}

# Export demo-specific functions
export -f log_header log_step kube_exec
export -f check_demo_prerequisites demo_init
