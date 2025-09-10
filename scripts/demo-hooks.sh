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
    
    echo "This demo shows different post-sync validation hooks managed by app-of-apps pattern:"
    echo
    
    echo "📋 DEV Environment Hooks:"
    echo "  • Demo App Hook: 10s wait, 2 retries, basic health check"
    echo "  • API App Hook: 15s wait, 2 retries, API endpoint validation"
    echo "  • Purpose: Quick feedback for development"
    echo
    
    echo "🏭 PRODUCTION Environment Hooks:"
    echo "  • Demo App Hook: 20s wait, 3 retries, comprehensive health checks"
    echo "  • API App Hook: 30s wait, 5 retries, extensive API validation"
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
    kubectl get jobs -n dev-demo-app 2>/dev/null || echo "  No demo app jobs found"
    kubectl get jobs -n dev-api-app 2>/dev/null || echo "  No API app jobs found"
    echo
    
    echo "🔍 PRODUCTION environment jobs:"
    kubectl get jobs -n production-demo-app 2>/dev/null || echo "  No demo app jobs found"
    kubectl get jobs -n production-api-app 2>/dev/null || echo "  No API app jobs found"
    echo
    
    log_info "To see hook execution in real-time:"
    echo "  # Dev hooks"
    echo "  kubectl get jobs -n dev-demo-app -w"
    echo "  kubectl get jobs -n dev-api-app -w"
    echo "  kubectl logs -f job/dev-post-sync-validation -n dev-demo-app"
    echo "  kubectl logs -f job/dev-api-post-sync-validation -n dev-api-app"
    echo
    echo "  # Production hooks"
    echo "  kubectl get jobs -n production-demo-app -w"
    echo "  kubectl get jobs -n production-api-app -w"
    echo "  kubectl logs -f job/production-post-sync-validation -n production-demo-app"
    echo "  kubectl logs -f job/production-api-post-sync-validation -n production-api-app"
    echo
}

# Show hook logs
show_hook_logs() {
    local env=$1
    local app_type=${2:-"demo"} # demo or api
    local namespace="${env}-${app_type}-app"
    local job_name="${env}-${app_type}-post-sync-validation"
    
    log_header "📄 $(echo $env | tr '[:lower:]' '[:upper:]') $(echo $app_type | tr '[:lower:]' '[:upper:]') App Hook Logs"
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        if kubectl get job "$job_name" -n "$namespace" &> /dev/null; then
            echo "Latest execution logs:"
            kubectl logs "job/$job_name" -n "$namespace" --tail=50 || echo "No logs available yet"
        else
            log_warning "No post-sync job found for $env $app_type app"
            echo "This means either:"
            echo "  • The application hasn't synced yet"
            echo "  • The post-sync hook hasn't been triggered"
            echo "  • The job has been cleaned up"
        fi
    else
        log_warning "Namespace $namespace not found"
        echo "Make sure you've deployed the app-of-apps pattern first:"
        echo "  ./scripts/deploy-demo.sh"
        echo "  # Or directly: kubectl apply -f app-of-apps/environments/"
    fi
    
    echo
}

# Trigger sync to show hooks
trigger_sync_demo() {
    log_header "🚀 Triggering Sync to Demonstrate Hooks"
    echo
    
    log_info "This will force a sync of all applications to show their per-app post-sync hooks:"
    echo
    
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Demo cancelled"
        return 0
    fi
    
    echo
    log_info "Force syncing all applications..."
    
    for app in dev-demo-app dev-api-app production-demo-app production-api-app; do
        if kubectl get application "$app" -n argocd &> /dev/null; then
            kubectl patch application "$app" -n argocd --type merge --patch '{"operation":{"sync":{}}}'
            log_success "$app sync triggered"
        else
            log_warning "$app application not found"
        fi
    done
    
    echo
    log_info "Watch the hooks execute:"
    echo "  # Dev environment hooks"
    echo "  kubectl get jobs -n dev-demo-app -w"
    echo "  kubectl get jobs -n dev-api-app -w"
    echo 
    echo "  # Production environment hooks"
    echo "  kubectl get jobs -n production-demo-app -w"
    echo "  kubectl get jobs -n production-api-app -w"
    echo
    log_info "In separate terminals, you can follow the logs:"
    echo "  kubectl logs -f job/dev-post-sync-validation -n dev-demo-app"
    echo "  kubectl logs -f job/dev-api-post-sync-validation -n dev-api-app"
    echo "  kubectl logs -f job/production-post-sync-validation -n production-demo-app"
    echo "  kubectl logs -f job/production-api-post-sync-validation -n production-api-app"
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
    echo "  logs <env> [app]  Show hook logs (env: dev/prod, app: demo/api)"
    echo "  trigger     Force sync all apps to demonstrate hooks"
    echo "  help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 compare"
    echo "  $0 monitor"
    echo "  $0 logs dev demo"
    echo "  $0 logs prod api"
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
            local app_type=${3:-"demo"}
            if [ -z "$env" ]; then
                echo "Error: Environment required (dev or prod)"
                echo "Usage: $0 logs <dev|prod> [demo|api]"
                exit 1
            fi
            if [[ ! "$env" =~ ^(dev|prod)$ ]]; then
                echo "Error: Environment must be 'dev' or 'prod'"
                exit 1
            fi
            if [[ ! "$app_type" =~ ^(demo|api)$ ]]; then
                echo "Error: App type must be 'demo' or 'api'"
                exit 1
            fi
            show_hook_logs "$env" "$app_type"
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
