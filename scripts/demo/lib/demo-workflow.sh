#!/bin/bash

# demo-workflow.sh
# Functions for executing the Helm workflow and making demo changes

# Source common demo functions
source "$(dirname "${BASH_SOURCE[0]}")/demo-common.sh"

# Make selective change using Helm workflow
make_selective_change() {
    log_header "🎯 Making Selective Change - Scale dev-api-app Only"
    echo
    
    # Get current replica count from Helm template (sanitize to numeric, default to 1)
    local current_replicas
    current_replicas=$(grep -m1 -E '^[[:space:]]*replicas:' environments/dev-api-app/templates/deployment.yaml 2>/dev/null | awk '{print $2}' | tr -cd '0-9')
    if [[ -z "$current_replicas" ]]; then
        current_replicas=1
    fi
    local new_replicas=$(( current_replicas + 1 ))
    
    log_step "Scaling dev-api-app from $current_replicas to $new_replicas replicas"
    log "This should trigger sync ONLY on dev-api-app, NOT on dev-demo-app"
    log "Using Helm workflow: version bump → package → upload → ArgoCD targetRevision update"
    echo
    
    # Execute Helm workflow using helm-workflow.sh script
    log_step "Executing Helm workflow..."
    
    if ./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app $new_replicas; then
        success "Helm workflow completed successfully"
        log "Changes made:"
        log "  • Scaled dev-api-app to $new_replicas replicas"
        log "  • Chart version bumped"
        log "  • Packages rebuilt and uploaded to Nexus"
        log "  • ArgoCD targetRevision updated"
    else
        error "Helm workflow failed"
        exit 1
    fi
    
    # Show the changes that were made
    log_step "Files changed by Helm workflow:"
    git status --porcelain | sed 's/^/  /'
    echo
    
    # Show key diffs
    log_step "Key changes:"
    echo "Chart version update:"
    git diff environments/dev-api-app/Chart.yaml | grep "^[-+]version:" | sed 's/^/  /' || echo "  No version changes visible"
    echo "Replica count update:"
    git diff environments/dev-api-app/templates/deployment.yaml | grep "^[-+].*replicas:" | sed 's/^/  /' || echo "  No replica changes visible"
    echo "ArgoCD targetRevision update:"
    git diff app-of-apps/applications/dev/templates/dev-api-app.yaml | grep "^[-+].*targetRevision:" | sed 's/^/  /' || echo "  No targetRevision changes visible"
    echo
    
    # Commit and push changes for Helm workflow
    log_step "Committing and pushing changes..."
    git add -A  # Add all changes (important for Helm workflow)
    
    # Ensure git identity is configured for the demo
    if ! git config user.email > /dev/null 2>&1; then
        log "Configuring git identity for demo..."
        git config user.email "argocd-demo@example.com"
        git config user.name "ArgoCD Demo Script"
    fi
    
    git commit -m "Demo: Scale dev-api-app from $current_replicas to $new_replicas replicas (Helm workflow selective sync test)"
    
    # Push the change
    log "Pushing changes to remote repository..."
    if git push; then
        success "Changes pushed successfully to remote repository"
        log "ArgoCD should now detect the change and trigger selective sync"
        log "ArgoCD will pull new Helm chart version from Nexus repository"
        log "Allowing 3 seconds for ArgoCD to detect the push..."
        sleep 3  # Brief delay to allow ArgoCD webhook/polling to detect change
    else
        error "Failed to push changes to remote repository"
        error "Demo cannot continue without pushing changes to trigger ArgoCD sync"
        exit 1
    fi
    
    echo
}

# Make selective change (dry run version)
make_selective_change_dry_run() {
    log_header "🔍 DRY RUN: What Would Be Done - Scale dev-api-app Only"
    echo
    
    # Get current replica count from Helm template (sanitize to numeric, default to 1)
    local current_replicas
    current_replicas=$(grep -m1 -E '^[[:space:]]*replicas:' environments/dev-api-app/templates/deployment.yaml 2>/dev/null | awk '{print $2}' | tr -cd '0-9')
    if [[ -z "$current_replicas" ]]; then
        current_replicas=1
    fi
    local new_replicas=$(( current_replicas + 1 ))
    
    log_step "Would scale dev-api-app from $current_replicas to $new_replicas replicas"
    log "This would trigger sync ONLY on dev-api-app, NOT on dev-demo-app"
    log "Would use Helm workflow: version bump → package → upload → ArgoCD targetRevision update"
    echo
    
    # Show what the Helm workflow would do
    log_step "Helm workflow would execute:"
    echo "  📋 ./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app $new_replicas"
    echo "  📦 This would:"
    echo "     • Update replicas in environments/dev-api-app/templates/deployment.yaml: $current_replicas → $new_replicas"
    echo "     • Bump chart version in environments/dev-api-app/Chart.yaml (patch version)"
    echo "     • Rebuild ONLY dev-api-app Helm package (not all packages)"
    echo "     • Upload ONLY dev-api-app package to Nexus (selective upload)"
    echo "     • Update targetRevision in app-of-apps/applications/dev/templates/dev-api-app.yaml"
    echo
    
    # Show what files would be changed
    log_step "Files that would be changed:"
    echo "  📝 environments/dev-api-app/Chart.yaml (version bump)"
    echo "  📝 environments/dev-api-app/templates/deployment.yaml (replicas: $current_replicas → $new_replicas)"
    echo "  📝 app-of-apps/applications/dev/templates/dev-api-app.yaml (targetRevision update)"
    echo
    
    # Show what Git operations would happen
    log_step "Git operations that would be performed:"
    echo "  🔧 git config user.email \"argocd-demo@example.com\" (if not set)"
    echo "  🔧 git config user.name \"ArgoCD Demo Script\" (if not set)"
    echo "  📥 git add -A"
    echo "  📝 git commit -m \"Demo: Scale dev-api-app from $current_replicas to $new_replicas replicas (Helm workflow selective sync test)\""
    echo "  📤 git push"
    echo
    
    # Show what would happen in ArgoCD
    log_step "Expected ArgoCD behavior:"
    echo "  🎯 ArgoCD would detect targetRevision change in dev-api-app"
    echo "  📦 ArgoCD would pull new Helm chart version from Nexus repository"
    echo "  🚀 ONLY dev-api-app would sync (selective sync)"
    echo "  🔍 dev-demo-app would remain unchanged"
    echo "  ✅ API-specific post-sync validation hook would run"
    echo
    
    # Show monitoring that would occur
    log_step "Monitoring that would be performed:"
    echo "  👀 Watch ArgoCD applications for sync status changes"
    echo "  📊 Monitor deployment replica scaling in dev-api-app namespace"
    echo "  ⏱️  Track sync completion and health status"
    echo "  📈 Verify selective sync worked (only dev-api-app changed)"
    echo
    
    # Show cleanup options
    log_step "Cleanup options that would be available:"
    echo "  🔄 Git revert: git revert HEAD && git push"
    echo "  🧹 Helm artifacts cleanup:"
    echo "     • Remove local package file: helm-packages/dev-api-app-[new-version].tgz"
    echo "     • Delete package from Nexus repository via REST API"
    echo "     • Search and remove component by name and version"
    echo "  📋 Manual cleanup instructions provided"
    echo
}

# Export workflow functions
export -f make_selective_change make_selective_change_dry_run
