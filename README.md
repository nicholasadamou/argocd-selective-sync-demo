# ArgoCD Selective Sync Demo

A simplified demonstration of ArgoCD's selective syncing capabilities. This demo shows how different applications can watch different paths in a Git repository and only sync when their specific files change.

## 🎯 What This Demonstrates

This is a **basic version** of the concept from the [full argocd-selective-sync project](https://github.com/nicholasadamou/argocd-selective-sync). It shows the core idea of selective syncing in a simple, easy-to-understand way.

### Core Concept
- **Traditional GitOps**: One app watches entire repo → all changes trigger sync
- **Selective Sync**: Multiple apps each watch specific paths → only relevant changes trigger sync

## 📁 Project Structure

```
.
├── README.md                        # This file
├── applicationset.yaml              # Reference file (replaced by apps/)
├── apps/                            # Individual ArgoCD application definitions
│   ├── dev/
│   │   └── demo-app.yaml           # Dev app with basic post-sync hook
│   └── production/
│       └── demo-app.yaml           # Production app with enhanced post-sync hook
├── environments/                    # Environment-specific manifests
│   ├── dev/                        # Development environment
│   │   ├── deployment.yaml         # Dev app (1 replica)
│   │   └── service.yaml            # ClusterIP service
│   └── production/                 # Production environment
│       ├── deployment.yaml         # Prod app (3 replicas)
│       └── service.yaml            # LoadBalancer service
└── scripts/
    ├── deploy-demo.sh              # Demo deployment script
    ├── demo-hooks.sh               # Demonstrate post-sync hooks behavior
    └── cleanup.sh                  # Cleanup script
```

## 🚀 How It Works

This demo uses **individual ArgoCD Applications** with **post-sync hooks**:

1. **dev-demo-app** watches `environments/dev/` + runs dev post-sync validation
2. **production-demo-app** watches `environments/production/` + runs production post-sync validation

### Post-Sync Hooks
- **Dev Hook**: Quick validation (10s wait, 2 retries, basic health check)
- **Production Hook**: Enhanced validation (20s wait, 3 retries, comprehensive checks)

### Selective Syncing + Hooks Behavior
- ✅ Update `environments/dev/deployment.yaml` → **only dev app syncs + dev hook runs**
- ✅ Update `environments/production/service.yaml` → **only production app syncs + production hook runs**
- ✅ Update both directories → **both apps sync independently + respective hooks run**

## 📋 Prerequisites

- Kubernetes cluster (local or remote)
- `kubectl` configured to access your cluster
- ArgoCD installed on your cluster

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

Open browser to `https://localhost:8080`

**Get admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo
```

### 3. Clone and Deploy Demo

```bash
# Clone this demo repository
git clone https://github.com/nicholasadamou/argocd-selective-sync-demo.git
cd argocd-selective-sync-demo

# Update the repository URLs in application definitions
vim apps/dev/demo-app.yaml        # Change repoURL to your forked repository
vim apps/production/demo-app.yaml # Change repoURL to your forked repository

# Run the demo deployment
./scripts/deploy-demo.sh
```

## 🎯 Testing Selective Sync

### Scenario 1: Update Development Only
```bash
# Edit dev deployment
vim environments/dev/deployment.yaml  # Change replicas from 1 to 2

# Commit and push
git add environments/dev/deployment.yaml
git commit -m "Scale dev app to 2 replicas"
git push

# Watch ArgoCD - only dev-demo-app will sync
kubectl get applications -n argocd -w

# Watch the post-sync hook job
kubectl get jobs -n demo-app-dev -w
kubectl logs -f job/dev-post-sync-validation -n demo-app-dev
```

**Result**: Only the `dev-demo-app` application syncs + dev post-sync validation hook runs. Production remains untouched.

### Scenario 2: Update Production Only
```bash
# Edit production service
vim environments/production/service.yaml  # Change type from LoadBalancer to NodePort

# Commit and push
git add environments/production/service.yaml
git commit -m "Change production service to NodePort"
git push

# Watch ArgoCD - only production-demo-app will sync
kubectl get applications -n argocd -w

# Watch the enhanced post-sync hook job
kubectl get jobs -n demo-app-prod -w
kubectl logs -f job/production-post-sync-validation -n demo-app-prod
```

**Result**: Only the `production-demo-app` application syncs + enhanced production post-sync validation hook runs. Development remains untouched.

### Scenario 3: Update Both Environments
```bash
# Edit both environments
vim environments/dev/deployment.yaml        # Change image to nginx:1.22
vim environments/production/deployment.yaml # Change image to nginx:1.22

# Commit and push
git add environments/
git commit -m "Update nginx to version 1.22 in both environments"
git push

# Watch ArgoCD - both apps sync independently
kubectl get applications -n argocd -w
```

**Result**: Both applications sync independently + both respective post-sync hooks run in parallel.

## 🔍 Demonstrating Post-Sync Hooks

```bash
# Compare dev vs production hooks
./scripts/demo-hooks.sh compare

# Monitor current post-sync jobs
./scripts/demo-hooks.sh monitor

# View hook execution logs
./scripts/demo-hooks.sh logs dev
./scripts/demo-hooks.sh logs prod

# Force trigger both apps to see hooks in action
./scripts/demo-hooks.sh trigger
```

### Hook Behavior Differences
- **Dev Hook**: Quick validation (10s wait, 2 retries) - optimized for fast development feedback
- **Production Hook**: Comprehensive validation (20s wait, 3 retries) - thorough checks for production stability

## 📊 Monitoring

### Check Application Status
```bash
# List all applications
kubectl get applications -n argocd

# Get detailed status
kubectl describe application dev-demo-app -n argocd
kubectl describe application production-demo-app -n argocd

# Check post-sync validation jobs
kubectl get jobs -n demo-app-dev
kubectl get jobs -n demo-app-prod

# View post-sync hook logs
kubectl logs -l job-name=dev-post-sync-validation -n demo-app-dev
kubectl logs -l job-name=production-post-sync-validation -n demo-app-prod

# Check deployed resources
kubectl get all -n demo-app-dev
kubectl get all -n demo-app-prod
```

### Access Applications
```bash
# Access dev app (port 8080)
kubectl port-forward svc/demo-app-service -n demo-app-dev 8080:80

# Access production app (port 8081)
kubectl port-forward svc/demo-app-service -n demo-app-prod 8081:80

# Visit http://localhost:8080 and http://localhost:8081
```

## 🧹 Cleanup

```bash
# Use the cleanup script (recommended)
./scripts/cleanup.sh

# Or manually:
kubectl delete application dev-demo-app production-demo-app -n argocd
kubectl delete namespace demo-app-dev demo-app-prod
```

## 🆚 Comparison with Full Project

| Feature | This Demo | Full Project |
|---------|-----------|--------------|
| **Environments** | 2 (dev, production) | 3 (dev, staging, production) |
| **Applications** | 2 total | 6 total (3 envs × 2 services) |
| **Services** | 1 (demo-app) | 2 (demo-app, api-service) |
| **Post-Sync Hooks** | Basic (dev: 10s, prod: 20s) | Custom per application |
| **Scripts** | 1 basic script | 8+ comprehensive scripts |
| **Complexity** | Beginner-friendly | Production-ready |

## 💡 Key Takeaways

1. **Path-Based Watching**: Each ArgoCD application watches a specific directory path
2. **Independent Syncing**: Changes only trigger syncs for applications watching the changed path
3. **Resource Efficiency**: No unnecessary syncs or deployments
4. **GitOps Best Practice**: Maintain separation of concerns between environments

## 🔗 Learn More

- **Full Implementation**: [argocd-selective-sync](https://github.com/nicholasadamou/argocd-selective-sync)
- **ArgoCD Documentation**: [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)
- **ApplicationSet Documentation**: [https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

**This is a simplified demo version.** For a production-ready implementation with advanced features like per-app post-sync hooks, comprehensive monitoring, and management scripts, see the [full argocd-selective-sync project](https://github.com/nicholasadamou/argocd-selective-sync).
