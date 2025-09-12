#!/bin/bash

# run.sh - Modular entrypoint for the ArgoCD selective sync demo (Helm-only)
# Uses libraries in scripts/demo/lib to keep code organized and maintainable.

set -euo pipefail

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_LIB_DIR="$SCRIPT_DIR/lib"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source demo libraries
source "$DEMO_LIB_DIR/demo-common.sh"
source "$DEMO_LIB_DIR/demo-state.sh"
source "$DEMO_LIB_DIR/demo-workflow.sh"
source "$DEMO_LIB_DIR/demo-cleanup.sh"

# Usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Demonstrate ArgoCD selective sync with Helm-based app-of-apps pattern"
    echo "This script only supports Helm chart deployments with Nexus repository."
    echo
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -n, --dry-run    Show what would be done without executing"
    echo "  -q, --quiet      Run with minimal output"
    echo "  -y, --yes        Skip confirmation prompts (includes cleanup)"
    echo "  --no-cleanup     Skip automatic cleanup (leave demo changes)"
    echo
    echo "This script demonstrates the complete Helm-based selective sync workflow:"
    echo "  1. Show current state of dev applications and chart versions"
    echo "  2. Execute Helm workflow (./scripts/helm/helm-workflow.sh scale-and-publish):"
    echo "     • Scale dev-api-app replicas in Helm template"
    echo "     • Bump chart version using semantic versioning"
    echo "     • Rebuild and upload ONLY the changed app's Helm package"
    echo "     • Update ArgoCD targetRevision to new chart version"
    echo "  3. Commit and push all repository changes"
    echo "  4. Monitor ArgoCD selective sync behavior from Nexus repository"
    echo "  5. Verify ONLY dev-api-app syncs from new chart (not dev-demo-app)"
    echo "  6. Analyze results and confirm selective sync worked"
    echo "  7. Automatically clean up with complete revert workflow + Helm artifact removal"
    echo
}

main() {
    local quiet=false
    local auto_yes=false
    local skip_cleanup=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage; exit 0 ;;
            -n|--dry-run)
                DRY_RUN=true; shift ;;
            -q|--quiet)
                quiet=true; shift ;;
            -y|--yes)
                auto_yes=true; shift ;;
            --no-cleanup)
                skip_cleanup=true; shift ;;
            *)
                error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done

    # Quiet mode routing to only show important lines
    if $quiet; then
        exec 3>&1
        exec > >(grep -E "(SUCCESS|ERROR|WARNING|STEP)" >&3)
    fi

    echo
    log_header "==========================================="
    log_header "  ArgoCD Selective Sync Demonstration"
    if $DRY_RUN; then log_header "           (DRY RUN MODE)"; fi
    log_header "==========================================="
    echo

    # Init and prerequisites
    (cd "$REPO_ROOT" && demo_init)
    echo

    if $DRY_RUN; then
        log "🔍 DRY RUN MODE: Showing what would be done without executing"; echo
    elif ! $auto_yes; then
        warn "⚠️  IMPORTANT: This demo will modify your repository using Helm workflow!"; echo
        log "This script will execute the complete Helm workflow:"
        echo "  • Scale dev-api-app replicas in Helm template (environments/dev-api-app/templates/deployment.yaml)"
        echo "  • Bump chart version in Chart.yaml using semantic versioning"
        echo "  • Rebuild and upload ONLY the changed Helm package to Nexus repository"
        echo "  • Update ArgoCD targetRevision to point to the new chart version"
        echo "  • COMMIT and PUSH all changes to your remote git repository"
        echo "  • Wait for ArgoCD to sync from the new Helm chart version"
        echo "  • Optionally revert with complete cleanup (revert commit + push + Nexus artifact removal)"
        echo
        warn "Repository files will be modified, Helm packages rebuilt, and changes pushed!"; echo
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then log "Demo cancelled"; exit 0; fi
        echo
    fi

    # Run demo
    (cd "$REPO_ROOT" && show_initial_state)

    if $DRY_RUN; then
        (cd "$REPO_ROOT" && make_selective_change_dry_run)
        echo; log "🔍 DRY RUN: No actual changes were made"; log "Run without --dry-run to execute the full demo"
    else
        (cd "$REPO_ROOT" && make_selective_change)
        (cd "$REPO_ROOT" && monitor_selective_sync)
        (cd "$REPO_ROOT" && show_results)
        (cd "$REPO_ROOT" && analyze_results)

        # Cleanup handling
        if $skip_cleanup; then
            echo; log "Cleanup skipped as requested. To manually revert:"
            echo "  git log --oneline -2"; echo "  git revert HEAD  # Revert the scaling commit"; echo
        elif ! $auto_yes; then
            echo; log "The demo has created a scaling commit that should be reverted."
            read -p "Would you like to automatically clean up the demo changes? (Y/n): " -r
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                echo; log "Skipping automatic cleanup. To manually revert:"
                echo "  git log --oneline -2"; echo "  git revert HEAD  # Revert the scaling commit"; echo
            else
                (cd "$REPO_ROOT" && cleanup_demo)
            fi
        else
            (cd "$REPO_ROOT" && cleanup_demo)
        fi
    fi

    echo; log_header "🎉 Selective Sync Demonstration Complete!"; echo
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

