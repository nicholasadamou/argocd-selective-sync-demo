# ArgoCD App-of-Apps Pattern Demo

A comprehensive demonstration of ArgoCD's "app-of-apps" pattern with selective syncing capabilities. This demo shows how environment controllers manage individual applications, each with their own dedicated post-sync hooks.

## 🎯 What This Demonstrates

This demo showcases the **App-of-Apps pattern** where each environment has a controller that manages multiple applications within that environment, providing better separation of concerns and granular control.

### Core Concept
- **Traditional GitOps**: One app watches entire repo → all changes trigger sync
- **ApplicationSet Pattern**: Single controller generates multiple apps automatically
- **App-of-Apps Pattern**: Environment controllers manage individual applications → fine-grained control with per-app hooks

## 📁 Project Structure

```
.
├── README.md                        # This file - main project documentation
├── github-repo-secret.template.yaml # Template for GitHub repository access
├── .gitignore                       # Excludes secrets from version control
├── docs/                           # Documentation
│   └── SECRETS-README.md           # Secret management guide
├── scripts/                        # Utility scripts
│   ├── setup-secrets.sh            # Interactive secret setup with testing
│   ├── deploy-controllers.sh       # Deploy service-specific controllers
│   └── cleanup.sh                  # Enhanced cleanup for argocd namespace
├── apps/                          # Service-specific controller structure (NEW)
│   └── controllers/               # Individual service controllers
│       ├── README.md              # Controller documentation
│       ├── demo-app-dev-controller.yaml
│       ├── demo-app-production-controller.yaml
│       ├── api-service-dev-controller.yaml
│       ├── api-service-production-controller.yaml
│       └── master-controller.yaml # App-of-Apps controller for git-based deployment
├── app-of-apps/                    # Original App-of-Apps pattern structure
│   ├── environments/               # Environment controllers (parent apps)
│   │   ├── dev/
│   │   │   └── dev-environment-controller.yaml
│   │   └── production/
│   │       └── production-environment-controller.yaml
│   └── applications/               # Individual application definitions
│       ├── dev/
│       │   ├── dev-api-app.yaml
│       │   └── dev-demo-app.yaml
│       └── production/
│           ├── production-api-app.yaml
│           └── production-demo-app.yaml
│   ├── dev-controller.yaml        # Moved from root
│   └── production-controller.yaml # Moved from root
└── environments/                   # Application manifests (workloads)
    ├── api-service/               # API service environments
    │   ├── dev/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── post-sync-hook.yaml
    │   └── production/
    │       ├── deployment.yaml
    │       ├── service.yaml (NodePort for kind compatibility)
    │       └── post-sync-hook.yaml
    ├── demo-app/                  # Demo app environments
    │   ├── dev/
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── post-sync-hook.yaml
    │   └── production/
    │       ├── deployment.yaml
    │       ├── service.yaml (NodePort for kind compatibility)
    │       └── post-sync-hook.yaml
    ├── dev-api-app/              # Legacy structure (still used by app-of-apps)
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── post-sync-hook.yaml
    ├── dev-demo-app/             # Legacy structure (still used by app-of-apps)
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── post-sync-hook.yaml
    ├── production-api-app/       # Legacy structure (still used by app-of-apps)
    │   ├── deployment.yaml
    │   ├── service.yaml (NodePort)
    │   └── post-sync-hook.yaml
    └── production-demo-app/      # Legacy structure (still used by app-of-apps)
        ├── deployment.yaml
        ├── service.yaml (NodePort)
        └── post-sync-hook.yaml
```

## 🚀 How It Works

This demo uses the **App-of-Apps pattern** with **environment controllers** managing **individual applications**, each with **dedicated post-sync hooks**:

### App-of-Apps Architecture

This demo now supports **two deployment patterns**:

#### ✨ **NEW: Service-Specific Controllers** (Recommended)

**Individual ApplicationSet controllers for each service/environment combination:**
1. **`demo-app-dev-controller`** → Manages `dev-demo-app` application
2. **`demo-app-production-controller`** → Manages `production-demo-app` application  
3. **`api-service-dev-controller`** → Manages `dev-api-service` application
4. **`api-service-production-controller`** → Manages `production-api-service` application

**Benefits:**
- ✅ **Granular Control**: Each service can be managed independently
- ✅ **Environment Isolation**: Dev and production controllers are completely separate
- ✅ **Selective Deployment**: Deploy only specific service controllers as needed
- ✅ **Enhanced Labeling**: Better labels for filtering and management
- ✅ **Easier Troubleshooting**: Issues isolated to specific service/environment combinations

#### 🔄 **Original: Environment Controllers** (Legacy)

1. **Environment Controllers** (Parent Apps):
   - `dev-environment-controller` manages all dev applications
   - `production-environment-controller` manages all production applications

2. **Individual Applications** (Child Apps):
   - `dev-api-app` → watches `environments/dev-api-app/` + runs API-specific post-sync validation
   - `dev-demo-app` → watches `environments/dev-demo-app/` + runs demo app post-sync validation
   - `production-api-app` → watches `environments/production-api-app/` + runs production API validation
   - `production-demo-app` → watches `environments/production-demo-app/` + runs production demo validation

### App-of-Apps Benefits
- **Granular Control**: Each application has its own lifecycle and post-sync hooks
- **Environment Separation**: Environment controllers provide clear boundaries
- **Per-App Customization**: Different sync policies, retry logic, and hooks per application
- **Scalability**: Easy to add new applications to existing environments
- **Observability**: Individual application status and health checks
- **Flexible Deployment**: Deploy environment controllers independently
- **kind Compatibility**: Production services use NodePort instead of LoadBalancer for local clusters

### Post-Sync Hooks (Per Application)
- **Dev API Hook**: API-specific validation (15s wait, 2 retries, API endpoint checks)
- **Dev Demo Hook**: Quick validation (10s wait, 2 retries, basic health check)
- **Production API Hook**: Comprehensive API validation (30s wait, 5 retries, multiple endpoints)
- **Production Demo Hook**: Enhanced validation (20s wait, 3 retries, comprehensive checks)

### Selective Syncing + Per-App Hooks Behavior
- ✅ Update `environments/dev-api-app/deployment.yaml` → **only dev-api-app syncs + API-specific dev hook runs**
- ✅ Update `environments/production-demo-app/service.yaml` → **only production-demo-app syncs + production demo hook runs**
- ✅ Update multiple app directories → **only affected apps sync + respective hooks run in parallel**
- ✅ Each application has its own independent sync cycle and validation

## 📋 Prerequisites

- Kubernetes cluster (local or remote) - **kind/Docker Desktop supported**
- `kubectl` configured to access your cluster
- ArgoCD installed on your cluster (in `argocd` namespace)
- GitHub Personal Access Token (for private repository access)
- `git` command-line tool
- `jq` (optional, for enhanced cleanup script functionality)

## ⚙️ Configuration Notes

- **Branch Targeting**: All ArgoCD applications point to `feature/app-of-apps-selective-sync` branch
- **Service Types**: Production services use `NodePort` for kind/local cluster compatibility
- **Namespace**: ArgoCD resources are deployed to `argocd` namespace (not `default`)
- **Self-Healing**: All applications have `selfHeal: true` enabled for demo purposes

## 🛠️ Quick Setup

### 1. Install ArgoCD (if not already installed)

```bash
# Create argocd namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### 2. Access ArgoCD UI (Optional)

```bash
# Port forward to access UI locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open browser to `https://localhost:8080/argocd`

**Get admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo
```

### 3. Clone and Deploy Demo

```bash
# Clone this demo repository
git clone https://github.com/nicholasadamou/argocd-selective-sync-demo.git
cd argocd-selective-sync-demo

# Configure GitHub repository access (REQUIRED for private repos)
# See docs/SECRETS-README.md for detailed instructions
./scripts/setup-secrets.sh

# OPTION 1: Deploy service-specific controllers (NEW - Recommended)
# Individual controllers for each service in each environment
./scripts/deploy-controllers.sh

# OPTION 2: Deploy App-of-Apps environment controllers (Original pattern)
# Environment controllers which manage individual applications
kubectl apply -f app-of-apps/environments/dev/dev-environment-controller.yaml
kubectl apply -f app-of-apps/environments/production/production-environment-controller.yaml

# OPTION 3: Use the original setup script
./scripts/deploy-demo.sh
```

### 4. Verify Setup

```bash
# Check environment controller applications were created
kubectl get applications -n argocd -l app-type=environment-controller

# Check individual applications were created by environment controllers
kubectl get applications -n argocd --show-labels

# Monitor application status
watch kubectl get applications -n argocd

# Check ArgoCD logs if needed
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

## 🔐 Secret Management

This repository uses GitHub for source control and requires proper authentication setup for ArgoCD to access private repositories.

### 🔄 Quick Setup

```bash
# Interactive setup with credential testing (recommended)
./scripts/setup-secrets.sh
```

This script will:
- Prompt for your GitHub credentials securely
- Create the Kubernetes secret for ArgoCD
- Test repository access with your credentials
- Verify ArgoCD can discover environment directories
- Provide detailed feedback on any issues

### 📚 Detailed Documentation

For comprehensive secret management documentation, see:
- **[docs/SECRETS-README.md](docs/SECRETS-README.md)** - Complete guide to secret management

### 🔒 Security Notes

- ✅ Secrets are excluded from Git via `.gitignore`
- ✅ Template files use placeholders (safe to commit)
- ✅ Setup script includes credential testing
- ⚠️ Never commit actual secrets to version control
- ⚠️ Rotate GitHub tokens regularly

## 🎯 Testing Selective Sync

### Scenario 1: Update Dev API App Only
```bash
# Edit dev API deployment
vim environments/dev-api-app/deployment.yaml  # Change replicas from 1 to 2

# Commit and push
git add environments/dev-api-app/deployment.yaml
git commit -m "Scale dev API app to 2 replicas"
git push

# Watch ArgoCD - only dev-api-app will sync
kubectl get applications -n argocd -w

# Watch the API-specific post-sync hook job
kubectl get jobs -n dev-api-app -w
kubectl logs -f job/dev-api-post-sync-validation -n dev-api-app
```

**Result**: Only the `dev-api-app` application syncs + API-specific dev post-sync validation hook runs. All other apps remain untouched.

### Scenario 2: Update Production Demo App Only
```bash
# Edit production demo service
vim environments/production-demo-app/service.yaml  # Change type from ClusterIP to NodePort

# Commit and push
git add environments/production-demo-app/service.yaml
git commit -m "Change production demo service to NodePort"
git push

# Watch ArgoCD - only production-demo-app will sync
kubectl get applications -n argocd -w

# Watch the enhanced post-sync hook job
kubectl get jobs -n production-demo-app -w
kubectl logs -f job/production-post-sync-validation -n production-demo-app
```

**Result**: Only the `production-demo-app` application syncs + enhanced production post-sync validation hook runs. All other apps remain untouched.

### Scenario 3: Update Multiple Applications
```bash
# Edit multiple application deployments
vim environments/dev-api-app/deployment.yaml        # Change image to nginx:1.22
vim environments/production-api-app/deployment.yaml # Change image to nginx:1.22

# Commit and push
git add environments/dev-api-app/deployment.yaml environments/production-api-app/deployment.yaml
git commit -m "Update nginx to version 1.22 in API apps"
git push

# Watch ArgoCD - both API apps sync independently
kubectl get applications -n argocd -w

# Watch both API post-sync hooks run in parallel
kubectl get jobs -n dev-api-app -w &
kubectl get jobs -n production-api-app -w
```

**Result**: Both API applications sync independently + both respective API post-sync hooks run in parallel. Demo apps remain untouched.

## 🎯 Demonstrating Selective Sync

```bash
# Automated selective sync demonstration
./scripts/demo-selective-sync.sh

# Run without prompts (great for CI/demos)
./scripts/demo-selective-sync.sh -y

# Quiet mode (minimal output)
./scripts/demo-selective-sync.sh -q -y
```

This script will:
1. **Show current state** of both dev applications
2. **Scale dev-api-app** (increase replicas by 1) 
3. **Monitor sync behavior** in real-time
4. **Verify selective sync** - only dev-api-app should sync
5. **Analyze results** and confirm expected behavior

## 🔍 Demonstrating Post-Sync Hooks

```bash
# Compare dev vs production hooks across all apps
./scripts/demo-hooks.sh compare

# Monitor current post-sync jobs
./scripts/demo-hooks.sh monitor

# View hook execution logs for specific apps
./scripts/demo-hooks.sh logs dev demo
./scripts/demo-hooks.sh logs dev api
./scripts/demo-hooks.sh logs prod demo
./scripts/demo-hooks.sh logs prod api

# Force trigger all apps to see hooks in action
./scripts/demo-hooks.sh trigger
```

### Hook Behavior Differences (Per Application)
- **Dev Demo Hook**: Quick validation (10s wait, 2 retries) - optimized for fast development feedback
- **Dev API Hook**: API validation (15s wait, 2 retries) - API-specific endpoint checks
- **Production Demo Hook**: Comprehensive validation (20s wait, 3 retries) - thorough checks for production stability
- **Production API Hook**: Extensive API validation (30s wait, 5 retries) - comprehensive API testing

## 📊 Monitoring

### Check Application Status
```bash
# List environment controllers
kubectl get applications -n argocd -l app-type=environment-controller

# List all individual applications
kubectl get applications -n argocd --show-labels

# Get detailed status
kubectl describe application dev-demo-app -n argocd
kubectl describe application production-api-app -n argocd

# Check post-sync validation jobs by namespace
kubectl get jobs -n dev-demo-app
kubectl get jobs -n dev-api-app
kubectl get jobs -n production-demo-app
kubectl get jobs -n production-api-app

# View post-sync hook logs
kubectl logs -l job-name=dev-post-sync-validation -n dev-demo-app
kubectl logs -l job-name=dev-api-post-sync-validation -n dev-api-app
kubectl logs -l job-name=production-post-sync-validation -n production-demo-app
kubectl logs -l job-name=production-api-post-sync-validation -n production-api-app

# Check deployed resources per environment
kubectl get all -n dev-demo-app
kubectl get all -n production-api-app
```

### Access Applications
```bash
# Access dev applications
kubectl port-forward svc/demo-app-dev-service -n dev-demo-app 8080:80
kubectl port-forward svc/api-app-dev-service -n dev-api-app 8090:3000

# Access production applications
kubectl port-forward svc/demo-app-production-service -n production-demo-app 8081:80
kubectl port-forward svc/api-app-production-service -n production-api-app 8091:3000

# Visit the applications:
# - Dev Demo App: http://localhost:8080
# - Dev API App: http://localhost:8090
# - Production Demo App: http://localhost:8081
# - Production API App: http://localhost:8091
```

## 🧹 Cleanup

```bash
# Use the enhanced cleanup script (recommended)
./scripts/cleanup.sh

# Force cleanup without confirmation
./scripts/cleanup.sh --force

# Use different ArgoCD namespace
ARGOCD_NS=custom-argocd ./scripts/cleanup.sh
```

The cleanup script now:
- ✅ **Cleans argocd namespace** - Removes Applications and ApplicationSets
- ✅ **Handles stuck resources** - Force-removes finalizers from stuck Applications  
- ✅ **Deletes demo namespaces** - Removes all created application namespaces
- ✅ **Supports multiple patterns** - Works with both service-specific and environment controllers
- ✅ **Comprehensive verification** - Shows what was cleaned up

**Manual cleanup (if needed):**
```bash
# Delete environment controllers (original pattern)
kubectl delete application dev-environment-controller production-environment-controller -n argocd

# Delete service-specific controllers (new pattern)
kubectl delete applicationsets -n argocd -l app.kubernetes.io/part-of=selective-sync-demo

# Clean up application namespaces
kubectl delete namespace dev-demo-app dev-api-app production-demo-app production-api-app
```

## 💡 Key Takeaways

1. **App-of-Apps Pattern**: Environment controllers manage individual applications for better separation of concerns
2. **Path-Based Watching**: Each individual ArgoCD application watches a specific directory path
3. **Independent Syncing**: Changes only trigger syncs for applications watching the changed path
4. **Per-App Customization**: Each application can have its own sync policies, retry logic, and post-sync hooks
5. **Resource Efficiency**: No unnecessary syncs or deployments
6. **Granular Control**: Fine-grained management of application lifecycle and validation
7. **Environment Isolation**: Clear boundaries between environments via dedicated controllers
8. **GitOps Best Practice**: Maintain separation of concerns with flexible deployment strategies

## 🔗 Learn More

- **ArgoCD Documentation**: [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)
- **ApplicationSet Documentation**: [https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)