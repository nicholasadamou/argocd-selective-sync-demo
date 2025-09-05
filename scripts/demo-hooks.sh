#!/bin/bash

# demo-hooks.sh
# Script to demonstrate post-sync hooks behavior

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

log_header() {
    echo -e "${PURPLE}$1${NC}"
}

# Show hook comparison
show_hook_comparison() {
    log_header "🎯 Post-Sync Hook Comparison"
    echo
    
    echo "This demo shows different post-sync validation hooks:"
    echo
    
    echo "📋 DEV Environment Hook:"
    echo "  • Wait time: 10 seconds"
    echo "  • Retries: 2"
    echo "  • Validation: Basic health check"
    echo "  • Purpose: Quick feedback for development"
    echo
    
    echo "🏭 PRODUCTION Environment Hook:"
    echo "  • Wait time: 20 seconds"
    echo "  • Retries: 3" 
    echo "  • Validation: Comprehensive health checks"
    echo "  • Purpose: Thorough validation for production"
    echo
    
    echo "🔍 Key Differences:"
    echo "  • Production waits longer for services to stabilize"
    echo "  • Production has more retry attempts"
    echo "  • Production performs multiple validation rounds"
    echo "  • Each hook only runs when its environment changes"
    echo
}

# Monitor hooks
monitor_hooks() {
    log_header "👀 Monitoring Post-Sync Hooks"
    echo
    
    log_info "Current post-sync validation jobs:"
    echo
    
    echo "🔍 DEV environment jobs:"
    kubectl get jobs -n demo-app-dev 2>/dev/null || echo "  No jobs found (apps not deployed yet?)"
    echo
    
    echo "🔍 PRODUCTION environment jobs:"
    kubectl get jobs -n demo-app-prod 2>/dev/null || echo "  No jobs found (apps not deployed yet?)"
    echo
    
    log_info "To see hook execution in real-time:"
    echo "  # Dev hooks"
    echo "  kubectl get jobs -n demo-app-dev -w"
    echo "  kubectl logs -f job/dev-post-sync-validation -n demo-app-dev"
    echo
    echo "  # Production hooks"
    echo "  kubectl get jobs -n demo-app-prod -w"
    echo "  kubectl logs -f job/production-post-sync-validation -n demo-app-prod"
    echo
}

# Show hook logs
show_hook_logs() {
    local env=$1
    local namespace="demo-app-${env}"
    local job_name="${env}-post-sync-validation"
    
    log_header "📄 ${env^^} Hook Logs"
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        if kubectl get job "$job_name" -n "$namespace" &> /dev/null; then
            echo "Latest execution logs:"
            kubectl logs "job/$job_name" -n "$namespace" --tail=50 || echo "No logs available yet"
        else
            log_warning "No post-sync job found for $env environment"
            echo "This means either:"
            echo "  • The application hasn't synced yet"
            echo "  • The post-sync hook hasn't been triggered"
            echo "  • The job has been cleaned up"
        fi
    else
        log_warning "Namespace $namespace not found"
        echo "Make sure you've deployed the applications first:"
        echo "  ./scripts/deploy-demo.sh"
    fi
    
    echo
}

# Trigger sync to show hooks
trigger_sync_demo() {
    log_header "🚀 Triggering Sync to Demonstrate Hooks"
    echo
    
    log_info "This will force a sync of both applications to show their post-sync hooks:"
    echo
    
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Demo cancelled"
        return 0
    fi
    
    echo
    log_info "Force syncing dev application..."
    if kubectl get application dev-demo-app -n argocd &> /dev/null; then
        kubectl patch application dev-demo-app -n argocd --type merge --patch '{"operation":{"sync":{}}}'
        log_success "Dev sync triggered"
    else
        log_warning "Dev application not found"
    fi
    
    log_info "Force syncing production application..."
    if kubectl get application production-demo-app -n argocd &> /dev/null; then
        kubectl patch application production-demo-app -n argocd --type merge --patch '{"operation":{"sync":{}}}'
        log_success "Production sync triggered"
    else
        log_warning "Production application not found"
    fi
    
    echo
    log_info "Watch the hooks execute:"
    echo "  kubectl get jobs -n demo-app-dev demo-app-prod -w"
    echo
    log_info "In separate terminals, you can follow the logs:"
    echo "  kubectl logs -f job/dev-post-sync-validation -n demo-app-dev"
    echo "  kubectl logs -f job/production-post-sync-validation -n demo-app-prod"
    echo
}

# Show help
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Demonstrate ArgoCD post-sync hooks behavior"
    echo
    echo "Commands:"
    echo "  compare     Show comparison between dev and production hooks"
    echo "  monitor     Monitor current post-sync jobs"  
    echo "  logs <env>  Show hook logs (env: dev or prod)"
    echo "  trigger     Force sync both apps to demonstrate hooks"
    echo "  help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 compare"
    echo "  $0 monitor"
    echo "  $0 logs dev"
    echo "  $0 logs prod"
    echo "  $0 trigger"
}

# Main function
main() {
    local command=${1:-""}
    
    case "$command" in
        "compare")
            show_hook_comparison
            ;;
        "monitor")
            monitor_hooks
            ;;
        "logs")
            local env=${2:-""}
            if [ -z "$env" ]; then
                echo "Error: Environment required (dev or prod)"
                echo "Usage: $0 logs <dev|prod>"
                exit 1
            fi
            if [[ ! "$env" =~ ^(dev|prod)$ ]]; then
                echo "Error: Environment must be 'dev' or 'prod'"
                exit 1
            fi
            show_hook_logs "$env"
            ;;
        "trigger")
            trigger_sync_demo
            ;;
        "help"|"-h"|"--help"|"")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
