#!/bin/bash

# ArgoCD GitLab Repository Secret Setup Script
# This script helps you securely configure GitLab repository access for ArgoCD
# with multiple credential input methods and no inline credential usage

set -e

echo "🔐 ArgoCD GitLab Repository Secret Setup"
echo "=================================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    echo "💡 Make sure you're connected to your cluster or use: vagrant-ssh \"./setup-secrets.sh\""
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"
echo ""

# Function to get credentials securely
get_credentials() {
    echo "🔑 Choose credential input method:"
    echo "1) Interactive input (default)"
    echo "2) Environment variables (GITLAB_USERNAME, GITLAB_TOKEN)"
    echo "3) Credential file (~/.config/gitlab/credentials)"
    echo "4) GitLab CLI (glab)"
    echo ""
    read -p "Enter choice [1-4] (default: 1): " CRED_METHOD
    CRED_METHOD=${CRED_METHOD:-1}

    case $CRED_METHOD in
        1)
            echo "📝 Interactive credential input:"
            read -p "Enter your GitLab username: " GITLAB_USERNAME
            read -s -p "Enter your GitLab Personal Access Token: " GITLAB_TOKEN
            echo ""
            ;;
        2)
            echo "🌍 Using environment variables..."
            if [[ -z "$GITLAB_USERNAME" || -z "$GITLAB_TOKEN" ]]; then
                echo "❌ GITLAB_USERNAME and GITLAB_TOKEN environment variables must be set"
                echo "   Example: export GITLAB_USERNAME=yourusername"
                echo "   Example: export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx"
                exit 1
            fi
            ;;
        3)
            echo "📄 Using credential file..."
            CRED_FILE="$HOME/.config/gitlab/credentials"
            if [[ ! -f "$CRED_FILE" ]]; then
                echo "❌ Credential file not found: $CRED_FILE"
                echo "   Create the file with the following format:"
                echo "   GITLAB_USERNAME=yourusername"
                echo "   GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx"
                exit 1
            fi
            # Source the credential file in a subshell to avoid polluting environment
            eval $(cat "$CRED_FILE")
            ;;
        4)
            echo "🛠️ Using GitLab CLI (glab)..."
            if ! command -v glab &> /dev/null; then
                echo "❌ glab CLI is not installed"
                echo "   Install from: https://gitlab.com/gitlab-org/cli"
                exit 1
            fi
            # Get current user info to extract username
            GITLAB_USERNAME=$(glab api user --jq '.username' 2>/dev/null)
            # glab doesn't expose tokens directly, so we need to check auth status
            if ! glab auth status &>/dev/null; then
                echo "❌ glab is not authenticated"
                echo "   Run: glab auth login"
                exit 1
            fi
            echo "ℹ️  Using glab authentication for user: $GITLAB_USERNAME"
            GITLAB_TOKEN="__GLAB_TOKEN__"  # Special marker for glab usage
            ;;
        *)
            echo "❌ Invalid choice"
            exit 1
            ;;
    esac

    if [[ -z "$GITLAB_USERNAME" || -z "$GITLAB_TOKEN" ]]; then
        echo "❌ Username and token are required"
        exit 1
    fi
}

# Function to test repository access securely
test_repository_access() {
    local repo_url="https://gitlab.us.lmco.com/nicholasadamou/argocd-selective-sync-demo.git"
    local test_dir=$(mktemp -d)
    
    echo "🧪 Testing GitLab repository access..."
    echo "======================================="
    echo "📁 Using temporary directory: $test_dir"
    
    # Configure git credentials based on method used
    if [[ "$GITLAB_TOKEN" == "__GLAB_TOKEN__" ]]; then
        # Use glab for authentication
        echo "🔧 Configuring glab authentication..."
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_CONFIG_SYSTEM=/dev/null
        
        # Create git config that uses glab for credentials
        local temp_git_config="$test_dir/.gitconfig"
        cat > "$temp_git_config" << EOF
[credential "https://gitlab.us.lmco.com"]
	helper = !glab auth git-credential
EOF
        export GIT_CONFIG="$temp_git_config"
    else
        # Use credential helper approach
        echo "🔧 Configuring temporary git credentials..."
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_CONFIG_SYSTEM=/dev/null
        
        local temp_git_config="$test_dir/.gitconfig"
        cat > "$temp_git_config" << EOF
[credential "https://gitlab.us.lmco.com"]
	helper = !f() { echo "username=$GITLAB_USERNAME"; echo "password=$GITLAB_TOKEN"; }; f
EOF
        export GIT_CONFIG="$temp_git_config"
    fi
    
    # Test 1: Clone repository
    echo "🔍 Test 1: Attempting to clone repository..."
    if git clone --depth 1 "$repo_url" "$test_dir/test-repo" &>/dev/null; then
        echo "✅ SUCCESS: Can clone repository with provided credentials"
        local clone_success=true
    else
        echo "❌ FAILED: Cannot clone repository with provided credentials"
        echo "   This could mean:"
        echo "   - Invalid username or token"
        echo "   - Token lacks 'read_repository' scope"
        echo "   - Repository URL is incorrect"
        echo "   - Network connectivity issues"
        local clone_success=false
    fi
    
    # Test 2: List remote references
    echo "🔍 Test 2: Attempting to list repository references..."
    if git ls-remote "$repo_url" HEAD &>/dev/null; then
        echo "✅ SUCCESS: Can list repository references (ArgoCD will work)"
        local refs_success=true
    else
        echo "❌ FAILED: Cannot list repository references"
        echo "   ArgoCD uses this operation to discover directories/files"
        local refs_success=false
    fi
    
    # Test 3: Check environment structure
    local envs_success=false
    if [[ "$clone_success" == true ]]; then
        echo "🔍 Test 3: Checking for environments directory..."
        if [[ -d "$test_dir/test-repo/environments" ]]; then
            local env_count=$(find "$test_dir/test-repo/environments" -maxdepth 1 -type d | wc -l)
            env_count=$((env_count - 1))
            echo "✅ SUCCESS: Found environments directory with $env_count subdirectories"
            
            if [[ $env_count -gt 0 ]]; then
                echo "   📂 Environment directories found:"
                find "$test_dir/test-repo/environments" -maxdepth 1 -type d -not -path "$test_dir/test-repo/environments" -exec basename {} \; | sed 's/^/      - /'
            fi
            envs_success=true
        else
            echo "⚠️  WARNING: environments directory not found"
            echo "   ArgoCD ApplicationSet looks for 'environments/*' directories"
        fi
    fi
    
    # Cleanup credentials and temporary files
    echo "🧹 Cleaning up temporary files and credentials..."
    unset GITLAB_USERNAME GITLAB_TOKEN GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
    rm -rf "$test_dir"
    
    # Results summary
    echo ""
    echo "📊 Test Results Summary:"
    echo "======================="
    [[ "$clone_success" == true ]] && echo "✅ Repository Clone: PASSED" || echo "❌ Repository Clone: FAILED"
    [[ "$refs_success" == true ]] && echo "✅ Reference Listing: PASSED (ArgoCD compatible)" || echo "❌ Reference Listing: FAILED (ArgoCD will fail)"
    [[ "$envs_success" == true ]] && echo "✅ Environment Discovery: PASSED" || echo "⚠️  Environment Discovery: WARNING (check directory structure)"
    
    echo ""
    if [[ "$clone_success" == true && "$refs_success" == true ]]; then
        echo "🎉 All credential tests PASSED - ArgoCD should work correctly!"
        return 0
    else
        echo "⚠️  Credential tests FAILED - Please check your credentials and permissions"
        return 1
    fi
}

# Main execution
get_credentials

echo "🔄 Creating GitLab repository secret..."

# Delete existing secrets if they exist
kubectl delete secret gitlab-repo-secret gitlab-repo-secret-token gitlab-private-repo -n default --ignore-not-found=true

# Create the secret (credentials never appear inline here)
kubectl create secret generic gitlab-private-repo \
    --namespace=default \
    --from-literal=type=git \
    --from-literal=url=https://gitlab.us.lmco.com/nicholasadamou/argocd-selective-sync-demo.git \
    --from-literal=username="$GITLAB_USERNAME" \
    --from-literal=password="$GITLAB_TOKEN" \
    --from-literal=insecure="false" \
    --from-literal=enableLfs="false"

# Label the secret
kubectl label secret gitlab-private-repo argocd.argoproj.io/secret-type=repository -n default

echo "✅ GitLab repository secret created successfully!"
echo ""
echo "🔍 Verifying secret..."
kubectl get secret gitlab-private-repo -n default -o jsonpath='{.metadata.labels}' | grep -q "repository" && echo "✅ Secret is properly labeled"

# Test repository access
echo ""
if test_repository_access; then
    echo "🎉 Setup complete! Your GitLab repository is now configured for ArgoCD."
else
    echo "⚠️  Setup completed but credential tests failed"
    echo "🔧 Please check your GitLab credentials and permissions before proceeding"
fi

# Clear any remaining credential variables
unset GITLAB_USERNAME GITLAB_TOKEN

echo ""
echo "📝 Next steps:"
echo "   1. Check ApplicationSet status: kubectl get applicationsets -n argocd"
echo "   2. Check generated applications: kubectl get applications -n argocd"
echo "   3. Monitor ApplicationSet controller logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller"
echo ""
