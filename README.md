# ArgoCD App-of-Apps Pattern Demo

A comprehensive demonstration of ArgoCD's "app-of-apps" pattern with selective syncing capabilities. This demo shows how environment controllers manage individual applications, each with their own dedicated Argo Workflows for validation.

## 🎯 What This Demonstrates

This demo showcases the **App-of-Apps pattern** where each environment has a controller that manages multiple applications within that environment, providing better separation of concerns and granular control.

### Core Concept
- **Traditional GitOps**: One app watches entire repo → all changes trigger sync
- **ApplicationSet Pattern**: Single controller generates multiple apps automatically
- **App-of-Apps Pattern**: Environment controllers manage individual applications → fine-grained control with per-app workflows

## 📁 Project Structure

```
.
├── README.md                        # This file - main project documentation
├── github-repo-secret.template.yaml # Template for GitHub repository access
├── github-repo-secret.yaml          # Generated secret file (excluded from Git)
├── .gitignore                       # Excludes secrets from version control
├── docs/                           # Documentation
│   └── SECRETS-README.md           # Secret management guide
├── scripts/                        # Utility scripts
│   ├── setup-secrets.sh            # Interactive secret setup with testing
│   ├── demo-selective-sync.sh      # selective sync demo (Helm-only workflow)
│   ├── deploy-demo.sh              # Deploy the demo environment
│   ├── cleanup.sh                  # Clean up deployed resources
│   ├── credentials.example         # Example credentials file
│   ├── demo/                       # Modern demo framework
│   │   ├── README.md               # Demo framework documentation
│   │   ├── run.sh                  # Main demo runner script
│   │   └── lib/                    # Demo library modules
│   │       ├── demo-common.sh       # Common utilities and logging
│   │       ├── demo-state.sh        # State management and monitoring
│   │       ├── demo-workflow.sh     # Core workflow orchestration
│   │       └── demo-cleanup.sh      # Cleanup and artifact management
│   └── helm/                       # Helm repository and Nexus setup
│       ├── README.md               # Helm workflow documentation
│       ├── lib/                    # Shared library functions
│       │   └── nexus-common.sh     # Common functions for Nexus operations
│       ├── build-helm-packages.sh  # Package environments as Helm charts
│       ├── setup-nexus.sh          # Complete Nexus setup with Helm repository
│       ├── upload-helm-packages.sh # Upload Helm packages to Nexus repository
│       ├── helm-workflow.sh        # Complete Helm workflow management
│       └── complete_onboarding.sh  # Manual EULA acceptance and onboarding
├── app-of-apps/                    # App-of-Apps pattern structure
│   ├── environments/               # Environment controllers (parent apps)
│   │   ├── dev/
│   │   │   └── dev-environment-controller.yaml
│   │   └── production/
│   │       └── production-environment-controller.yaml
│   └── applications/               # Individual application definitions (as Helm charts)
│       ├── dev/                    # Dev environment applications
│       │   ├── Chart.yaml          # Environment controller chart metadata
│       │   └── templates/          # ArgoCD application definitions
│       │       ├── dev-api-app.yaml
│       │       └── dev-demo-app.yaml
│       └── production/             # Production environment applications
│           ├── Chart.yaml          # Environment controller chart metadata
│           └── templates/          # ArgoCD application definitions
│               ├── production-api-app.yaml
│               └── production-demo-app.yaml
├── environments/                   # Helm charts (workloads)
│   ├── dev-api-app/                # Dev API Helm chart
│   │   ├── Chart.yaml              # Chart metadata and version
│   │   └── templates/              # Kubernetes manifests as Helm templates
│   │       ├── deployment.yaml     # API deployment template
│   │       ├── service.yaml        # API service template
│   │       └── validation-workflow.yaml # API-specific Argo Workflow validation
│   ├── dev-demo-app/               # Dev Demo Helm chart
│   │   ├── Chart.yaml              # Chart metadata and version
│   │   └── templates/              # Kubernetes manifests as Helm templates
│   │       ├── deployment.yaml     # Demo deployment template
│   │       ├── service.yaml        # Demo service template
│   │       └── validation-workflow.yaml # Demo app Argo Workflow validation
│   ├── production-api-app/         # Production API Helm chart
│   │   ├── Chart.yaml              # Chart metadata and version
│   │   └── templates/              # Kubernetes manifests as Helm templates
│   │       ├── deployment.yaml     # API deployment template
│   │       ├── service.yaml        # API service template
│   │       └── validation-workflow.yaml # Production API Argo Workflow validation
│   └── production-demo-app/        # Production Demo Helm chart
│       ├── Chart.yaml              # Chart metadata and version
│       └── templates/              # Kubernetes manifests as Helm templates
│           ├── deployment.yaml     # Demo deployment template
│           ├── service.yaml        # Demo service template
│           └── validation-workflow.yaml # Production demo app Argo Workflow validation
├── helm-packages/                  # Generated Helm packages (created by build scripts)
│   ├── dev-api-app-0.1.0.tgz       # Dev API app Helm package
│   ├── dev-demo-app-0.1.0.tgz      # Dev demo app Helm package
│   ├── dev-applications-0.1.0.tgz   # Dev environment controller package
│   ├── production-api-app-0.1.0.tgz # Production API app Helm package
│   ├── production-demo-app-0.1.0.tgz # Production demo app Helm package
│   └── production-applications-0.1.0.tgz # Production environment controller package
└── workflows/                      # Argo Workflows configuration
    ├── templates/                  # WorkflowTemplate definitions
    │   ├── dev-validation-workflow-template.yaml      # Dev validation template
    │   └── production-validation-workflow-template.yaml # Production validation template
    ├── rbac.yaml                   # Service account and RBAC for workflows
    └── README.md                   # Workflows setup and documentation
```

## 🚀 How It Works

This demo uses the **App-of-Apps pattern** with **environment controllers** managing **individual applications**, each with **dedicated Argo Workflows for validation**:

### App-of-Apps Architecture

1. **Environment Controllers** (Parent Apps):
   - `dev-environment-controller` manages all dev applications
   - `production-environment-controller` manages all production applications

2. **Individual Applications** (Child Apps - Helm Charts):
   - `dev-api-app` → deploys from Helm chart `dev-api-app` + triggers API-specific validation workflow
   - `dev-demo-app` → deploys from Helm chart `dev-demo-app` + triggers demo app validation workflow
   - `production-api-app` → deploys from Helm chart `production-api-app` + triggers production API validation workflow
   - `production-demo-app` → deploys from Helm chart `production-demo-app` + triggers production demo validation workflow

### App-of-Apps Benefits
- **Granular Control**: Each application has its own lifecycle and validation workflows
- **Environment Separation**: Environment controllers provide clear boundaries
- **Per-App Customization**: Different sync policies, retry logic, and workflows per application
- **Scalability**: Easy to add new applications to existing environments
- **Observability**: Individual application status and workflow execution monitoring
- **Flexible Deployment**: Deploy environment controllers independently

### Argo Workflows for Validation (Per Application)
- **Dev API Workflow**: API-specific validation (15s wait, single attempt, API endpoint checks)
- **Dev Demo Workflow**: Quick validation (10s wait, single attempt, basic health check)  
- **Production API Workflow**: Comprehensive API validation (30s wait, 5 retries, multiple endpoints)
- **Production Demo Workflow**: Enhanced validation (20s wait, 3 retries, comprehensive checks)

### Selective Syncing + Per-App Workflow Behavior (Helm Workflow)
- ✅ Update `environments/dev-api-app/templates/deployment.yaml` + use `helm-workflow.sh` → **only dev-api-app syncs from new chart version + API-specific dev workflow triggers**
- ✅ Update `environments/production-demo-app/templates/service.yaml` + use Helm workflow → **only production-demo-app syncs from updated chart + production demo workflow triggers**
- ✅ Update multiple Helm templates + rebuild packages → **only affected apps sync from their new chart versions + respective workflows run in parallel**
- ✅ Each application has its own chart version, independent sync cycle, and validation workflow
- ✅ ArgoCD pulls chart updates from Nexus repository based on `targetRevision` changes

## 📋 Prerequisites

### Core Requirements
- Kubernetes cluster (local or remote)
- `kubectl` configured to access your cluster
- ArgoCD installed on your cluster
- **Argo Workflows** installed on your cluster
- GitHub Personal Access Token (for private repository access)
- `git` command-line tool

### For Helm Repository Setup (Required)
This demo requires the Helm repository setup with Nexus:
- **Docker** installed and running
- **Helm CLI** installed and available in your PATH
- **curl** for API interactions with Nexus
- Network connectivity to Nexus instance

## 🛠️ Quick Setup

### 1. Install ArgoCD and Argo Workflows (if not already installed)

```bash
# Install Argo Workflows
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/install.yaml

# Wait for services to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/workflow-controller -n argo
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

# Set up Argo Workflows (REQUIRED for validation)
kubectl apply -f workflows/rbac.yaml
kubectl apply -f workflows/templates/

# Deploy the App-of-Apps environment controllers
# This will deploy environment controllers which manage individual applications
kubectl apply -f app-of-apps/environments/dev/dev-environment-controller.yaml
kubectl apply -f app-of-apps/environments/production/production-environment-controller.yaml

# Alternative: Use the setup script (recommended)
./scripts/deploy-demo.sh
```

### 4. Verify Setup

```bash
# Check Argo Workflows are installed
kubectl get workflowtemplates -n argo
kubectl get serviceaccount argo-workflow -n argo

# Check environment controller applications were created
kubectl get applications -n argocd -l app-type=environment-controller

# Check individual applications were created by environment controllers
kubectl get applications -n argocd --show-labels

# Monitor application status
watch kubectl get applications -n argocd

# Check ArgoCD logs if needed
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

## 🚀 Helm Repository Setup (Required)

This demo uses ArgoCD applications configured to use Helm charts from a local Nexus repository. **The Helm setup is required** for this demo as all applications are configured to use Helm chart sources. The demo scripts only support Helm-based workflows.

### Why Use Helm Charts?
- **Versioning**: Proper semantic versioning for application releases
- **Packaging**: Self-contained application packages with dependencies
- **Templating**: Parameterized deployments across environments
- **Repository**: Centralized chart storage and distribution
- **ArgoCD Integration**: Native Helm support with `targetRevision` control

### Automated Setup

The scripts provide a complete automated setup:

```bash
# 1. Build Helm packages from environment manifests
./scripts/helm/build-helm-packages.sh

# 2. Set up Nexus Repository Manager with Helm repository
./scripts/helm/setup-nexus.sh

# 3. For manual EULA acceptance (if needed)
./scripts/helm/complete_onboarding.sh

# 4. Enhanced workflow management
./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app 2  # Scale and publish new version
./scripts/helm/upload-helm-packages.sh                         # Upload packages only
```

### What Gets Created

**Nexus Repository Manager:**
- Running on `http://localhost:8081`
- Admin credentials: `admin` / `admin123`
- Anonymous access enabled for ArgoCD
- Helm repository: `helm-hosted`

**Helm Packages Created:**
- `dev-api-app-0.1.0.tgz`
- `dev-demo-app-0.1.0.tgz`
- `dev-applications-0.1.0.tgz` (environment controller)
- `production-api-app-0.1.0.tgz`
- `production-demo-app-0.1.0.tgz`
- `production-applications-0.1.0.tgz` (environment controller)

**ArgoCD Integration:**
All ArgoCD applications are pre-configured to use the Helm repository:

```yaml
spec:
  source:
    repoURL: http://10.42.0.1:8081/repository/helm-hosted/
    chart: dev-api-app
    targetRevision: 0.1.0
```

For detailed Helm setup documentation, see **[scripts/helm/README.md](scripts/helm/README.md)**.

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

### Scenario 1: Update Dev API App Only (Helm Workflow)
```bash
# Use the Helm workflow to scale dev-api-app
./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app 2

# This command will:
# 1. Update replicas in environments/dev-api-app/templates/deployment.yaml
# 2. Bump the chart version in environments/dev-api-app/Chart.yaml  
# 3. Rebuild and upload Helm packages to Nexus
# 4. Update targetRevision in app-of-apps/applications/dev/templates/dev-api-app.yaml
# 5. Commit and push all changes

# Watch ArgoCD - only dev-api-app will sync
kubectl get applications -n argocd -w

# Watch the API-specific validation workflow
kubectl get workflows -n dev-api-app -w
kubectl get pods -l workflows.argoproj.io/workflow -n dev-api-app
```

**Result**: Only the `dev-api-app` application syncs from the new Helm chart version + API-specific dev validation workflow is triggered. All other apps remain untouched.

### Scenario 2: Update Production Demo App Service (Manual Helm Workflow)
```bash
# Manually edit the Helm template
vim environments/production-demo-app/templates/service.yaml  # Change type from ClusterIP to NodePort

# Use Helm workflow to publish changes
./scripts/helm/helm-workflow.sh bump-version production-demo-app patch
./scripts/helm/build-helm-packages.sh
./scripts/helm/upload-helm-packages.sh
./scripts/helm/helm-workflow.sh update-argocd-target production-demo-app

# Commit and push the changes
git add -A
git commit -m "Change production demo service to NodePort"
git push

# Watch ArgoCD - only production-demo-app will sync
kubectl get applications -n argocd -w

# Watch the enhanced validation workflow
kubectl get workflows -n production-demo-app -w
kubectl get pods -l workflows.argoproj.io/workflow -n production-demo-app
```

**Result**: Only the `production-demo-app` application syncs from the updated Helm chart + enhanced production validation workflow is triggered. All other apps remain untouched.

### Scenario 3: Update Multiple Applications (Image Updates)
```bash
# Update both API applications with new image using Helm workflow
# First update dev-api-app
vim environments/dev-api-app/templates/deployment.yaml  # Change image to nginx:1.22
./scripts/helm/helm-workflow.sh bump-version dev-api-app patch

# Then update production-api-app  
vim environments/production-api-app/templates/deployment.yaml  # Change image to nginx:1.22
./scripts/helm/helm-workflow.sh bump-version production-api-app patch

# Build and upload all packages
./scripts/helm/build-helm-packages.sh
./scripts/helm/upload-helm-packages.sh

# Update ArgoCD targetRevisions for both apps
./scripts/helm/helm-workflow.sh update-argocd-target dev-api-app
./scripts/helm/helm-workflow.sh update-argocd-target production-api-app

# Commit and push all changes
git add -A
git commit -m "Update nginx to version 1.22 in API apps (Helm workflow)"
git push

# Watch ArgoCD - both API apps sync independently
kubectl get applications -n argocd -w

# Watch both API validation workflows run in parallel
kubectl get workflows -n dev-api-app,production-api-app -w
```

**Result**: Both API applications sync independently from their updated Helm chart versions + both respective API validation workflows are triggered in parallel. Demo apps remain untouched.

## 🎯 Demonstrating Selective Sync

```bash
# Interactive selective sync demonstration with guided workflow
./scripts/demo/run.sh

# Dry run - see what would be done without executing (recommended first)
./scripts/demo/run.sh --dry-run

# Run with minimal output
./scripts/demo/run.sh --quiet
```

### 🔍 **Dry Run Mode**
Before running the full demo, use the `--dry-run` flag to see exactly what the script would do:

```bash
./scripts/demo-selective-sync.sh -n
# or
./scripts/demo-selective-sync.sh --dry-run
```

**Dry run shows:**
- 📝 Exact files that would be modified
- 📦 Helm workflow commands that would execute
- 📝 Git operations (add, commit, push)
- 🎯 Expected ArgoCD sync behavior
- 👀 Monitoring steps that would be performed
- 🔄 Cleanup options available

**Perfect for:**
- Understanding the workflow before executing
- Training and documentation purposes
- Verifying script behavior in different environments

### 📦 **Helm-Based Workflow**
The demo script uses the complete Helm-based deployment workflow:

- **Prerequisites**: Helm CLI, Nexus Repository Manager, Docker
- **Integration**: Uses `helm-workflow.sh` for complete end-to-end workflow
- **Semantic Versioning**: Automatically bumps chart versions using semantic versioning
- **Nexus Repository**: Builds, packages, and uploads Helm charts to Nexus
- **ArgoCD Integration**: Updates `targetRevision` in ArgoCD application manifests

### 🚀 **What the Demo Does:**
1. **Verify prerequisites** - Helm CLI, Nexus, Docker, etc.
2. **Show current state** of both dev applications
3. **Scale dev-api-app** using complete Helm workflow:
   - Update replicas in Helm template (`environments/dev-api-app/templates/deployment.yaml`)
   - Bump chart version in `environments/dev-api-app/Chart.yaml`
   - Rebuild and upload Helm packages to Nexus repository
   - Update `targetRevision` in `app-of-apps/applications/dev/templates/dev-api-app.yaml`
   - Commit and push all changes to Git
4. **Monitor sync behavior** in real-time
5. **Verify selective sync** - only dev-api-app should sync from new chart version
6. **Analyze results** and confirm expected behavior
7. **Auto-cleanup** with revert workflow

## 🔍 Demonstrating Argo Workflows

```bash
# Monitor current validation workflows
kubectl get workflows --all-namespaces

# View workflow execution logs
kubectl logs -l workflows.argoproj.io/workflow --all-namespaces

# Check workflow templates
kubectl get workflowtemplates -n argo

# Describe a specific workflow
kubectl describe workflow <workflow-name> -n <app-namespace>

# Monitor workflows in real-time
watch kubectl get workflows --all-namespaces
```

### Workflow Behavior Differences (Per Application)
- **Dev Demo Workflow**: Quick validation (10s wait, single attempt) - optimized for fast development feedback
- **Dev API Workflow**: API validation (15s wait, single attempt) - API-specific endpoint checks
- **Production Demo Workflow**: Comprehensive validation (20s wait, 3 retries) - thorough checks for production stability
- **Production API Workflow**: Extensive API validation (30s wait, 5 retries) - comprehensive API testing

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

# Check validation workflows
kubectl get workflows --all-namespaces

# View workflow execution logs 
kubectl get pods -l workflows.argoproj.io/workflow --all-namespaces
kubectl logs -l workflows.argoproj.io/workflow --all-namespaces

# Check workflow templates
kubectl get workflowtemplates -n argo

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
# Use the cleanup script (recommended)
./scripts/cleanup.sh

# Or manually:
# Delete the environment controllers (this will cascade to individual applications)
kubectl delete application dev-environment-controller -n argocd
kubectl delete application production-environment-controller -n argocd

# Clean up application namespaces
kubectl delete namespace dev-demo-app dev-api-app production-demo-app production-api-app
```

## 💡 Key Takeaways

1. **App-of-Apps Pattern**: Environment controllers manage individual applications for better separation of concerns
2. **Path-Based Watching**: Each individual ArgoCD application watches a specific directory path
3. **Independent Syncing**: Changes only trigger syncs for applications watching the changed path
4. **Per-App Customization**: Each application can have its own sync policies, retry logic, and validation workflows
5. **Resource Efficiency**: No unnecessary syncs or deployments
6. **Granular Control**: Fine-grained management of application lifecycle and validation
7. **Environment Isolation**: Clear boundaries between environments via dedicated controllers
8. **GitOps Best Practice**: Maintain separation of concerns with flexible deployment strategies

## 🔗 Learn More

- **ArgoCD Documentation**: [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)
- **Argo Workflows Documentation**: [https://argoproj.github.io/argo-workflows/](https://argoproj.github.io/argo-workflows/)
- **ApplicationSet Documentation**: [https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
