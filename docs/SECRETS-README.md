# ArgoCD GitHub Repository Secret Management

This repository requires GitHub repository access credentials to work with ArgoCD. **Never commit actual secrets to Git!**

## 🔐 Secure Setup Methods

### Method 1: Using the Setup Script (Recommended)

The setup script provides secure credential handling with **no inline credential usage** and comprehensive testing.

```bash
# Run the interactive setup script
./scripts/setup-secrets.sh
```

#### Script Features:
- ✅ **Secure credential handling** - No credentials exposed in URLs or command line
- ✅ **Comprehensive testing** - Validates repository access before setup
- ✅ **Environment verification** - Checks for required directory structure
- ✅ **Automatic cleanup** - Clears credentials from memory after use
- ✅ **Git credential helper** - Uses temporary credential configuration

### Method 1a: Enhanced Setup Script (Multiple Authentication Options)

For advanced users, an enhanced version with multiple authentication methods:

```bash
# Interactive credential input (default)
./scripts/setup-secrets.sh

# Using environment variables
export GITHUB_USERNAME="your_username"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
./scripts/setup-secrets.sh

# Using credential file
mkdir -p ~/.config/github
echo "GITHUB_USERNAME=your_username" > ~/.config/github/credentials
echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxx" >> ~/.config/github/credentials
chmod 600 ~/.config/github/credentials
./scripts/setup-secrets.sh

# Using GitHub CLI (gh)
gh auth login
./scripts/setup-secrets.sh
```

### Method 2: Using the Template File

```bash
# 1. Copy the template
cp github-repo-secret.template.yaml github-repo-secret.yaml

# 2. Edit the file and replace placeholders
# Replace YOUR_GITHUB_USERNAME with your GitHub username
# Replace YOUR_PERSONAL_ACCESS_TOKEN with your token

# 3. Apply to cluster
kubectl apply -f github-repo-secret.yaml
```

### Method 3: Direct kubectl Command

```bash
kubectl create secret generic github-private-repo \
  --namespace=argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/nicholasadamou/argocd-selective-sync-demo.git \
  --from-literal=username="YOUR_USERNAME" \
  --from-literal=password="YOUR_TOKEN" \
  --from-literal=insecure="false"

kubectl label secret github-private-repo argocd.argoproj.io/secret-type=repository -n argocd
```

## 🎫 Creating GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Create a new token with these scopes:
   - `repo` (minimum required for ArgoCD)
   - `read:user` (optional, for user information)
3. Set appropriate expiration date (recommend 90 days or less)
4. Copy the token immediately (you won't see it again!)

### Token Format
GitHub Personal Access Tokens typically start with `ghp_` followed by 36 characters:
```
ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## 🛡️ Security Best Practices

### ✅ DO:
- **Use secure credential methods** - Prefer credential files or environment variables over interactive input in CI/CD
- **Use `.gitignore`** to exclude secret files from version control
- **Use template files** with placeholders for team sharing
- **Use setup scripts** for consistent deployment across environments
- **Rotate tokens regularly** (every 90 days recommended)
- **Set minimal token permissions** - Only grant necessary scopes
- **Use temporary credential storage** - Scripts clean up after execution
- **Verify credential access** before creating Kubernetes secrets

### ❌ DON'T:
- **Commit actual secrets** to Git repositories
- **Share tokens** in chat, email, or documentation
- **Use tokens with excessive permissions** - Avoid admin or write access unless required
- **Store credentials in plain text** without proper file permissions
- **Use inline credentials** in URLs or command arguments
- **Leave credentials in shell history** or process lists

## 📁 Files in This Repository

### Root Directory
- `applicationset.yaml` - ArgoCD ApplicationSet configuration
- `github-repo-secret.template.yaml` - Template file (safe to commit)
- `github-repo-secret.yaml` - Actual secret file (⚠️ IGNORED by Git)
- `.gitignore` - Excludes secret files from Git

### Scripts Directory (`scripts/`)
- `setup-secrets.sh` - Secure interactive setup script with comprehensive testing
- `setup-secrets.sh` - Enhanced version with multiple authentication methods
- `credentials.example` - Template for credential file approach

### Documentation Directory (`docs/`)
- `SECRETS-README.md` - This file - secret management guide

### Environment Configurations (`environments/`)
- `dev/` - Development environment Kubernetes manifests
- `production/` - Production environment Kubernetes manifests

## 🔍 Verifying Setup

### Quick Verification
```bash
# Check if secret exists and is properly labeled
kubectl get secret github-private-repo -n argocd
kubectl get secret github-private-repo -n argocd -o jsonpath='{.metadata.labels}'

# Check ApplicationSet status
kubectl get applicationsets -n argocd

# Check generated applications
kubectl get applications -n argocd
```

### Detailed Verification
```bash
# View secret contents (base64 encoded)
kubectl get secret github-private-repo -n argocd -o yaml

# Check ApplicationSet events
kubectl describe applicationset argocd-selective-sync -n argocd

# Monitor ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Test repository connectivity (manual)
git ls-remote https://github.com/nicholasadamou/argocd-selective-sync-demo.git
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Repository Access Denied
```bash
# Symptoms: ApplicationSet shows repository access errors
# Check token permissions and expiration
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller | grep "access denied\|authentication failed"
```

**Solutions:**
- Verify token has `read_repository` scope
- Check if token is expired
- Ensure username is correct
- Re-run setup script to update credentials

#### 2. Applications Not Generated
```bash
# Check ApplicationSet status
kubectl get applicationset argocd-selective-sync -n argocd -o yaml
```

**Solutions:**
- Verify `environments/` directory structure in repository
- Check ApplicationSet generator configuration
- Review ApplicationSet controller logs for errors

#### 3. Secret Not Found
```bash
# Check if secret exists in correct namespace
kubectl get secrets -n argocd | grep github
```

**Solutions:**
- Re-run setup script
- Verify secret is in `argocd` namespace
- Check secret has proper ArgoCD label

### Reset and Recreate
```bash
# Clean up existing secrets
kubectl delete secret github-private-repo -n argocd --ignore-not-found

# Re-run setup
./scripts/setup-secrets.sh

# Or use enhanced version
./scripts/setup-secrets.sh
```

## 🚨 If Secrets Are Accidentally Committed

If you accidentally commit secrets:

1. **Immediately** revoke the token in GitHub
2. Remove the secret from Git history:
   ```bash
   git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch github-repo-secret.yaml' --prune-empty --tag-name-filter cat -- --all
   ```
3. Force push to update remote (⚠️ be careful with force push)
4. Generate new token and reconfigure

## 🛡️ Security Features Summary

### Setup Script Security
The `setup-secrets.sh` script implements multiple security measures:

- **No inline credentials** - Credentials never appear in URLs or command arguments
- **Git credential helper** - Uses temporary credential configuration instead of inline auth
- **Memory cleanup** - Clears all credential variables after use
- **Temporary isolation** - Uses temporary directories and configurations
- **Comprehensive testing** - Validates access before creating secrets
- **Process isolation** - Credentials not visible in process lists

### Enhanced Script Features
The `setup-secrets.sh` provides additional security options:

- **Multiple authentication methods** - Interactive, environment, file, or CLI-based
- **Credential file support** - Secure file-based credential storage
- **GitHub CLI integration** - Leverages existing `gh` authentication
- **Flexible deployment** - Supports different environments and workflows

### Kubernetes Secret Security
- **Namespace isolation** - Secrets stored in appropriate namespaces
- **Proper labeling** - ArgoCD-compatible secret labeling
- **Minimal permissions** - Tokens with only required repository access
- **Base64 encoding** - Standard Kubernetes secret encoding
