# ArgoCD App-of-Apps + Selective Sync Demo

A demonstration of ArgoCD's **App-of-Apps pattern** combined with **selective syncing capabilities**. This demo shows how a parent application can manage multiple child applications, where each child application watches specific files and only syncs when their relevant files change.

## 🎯 What This Demonstrates

This demonstrates the **App-of-Apps pattern** with **selective sync** from the [full argocd-selective-sync project](https://github.com/nicholasadamou/argocd-selective-sync). It shows how to manage multiple microservices efficiently using ArgoCD.

### Core Concepts
- **Traditional GitOps**: One app watches entire repo → all changes trigger sync
- **App-of-Apps Pattern**: Parent app manages multiple child applications
- **Selective Sync**: Each child app watches only specific files → only relevant changes trigger sync
- **Service Isolation**: Different services sync independently based on their file changes

## 📁 Project Structure

```
.
├── README.md                        # This file
├── app-of-apps.yaml                 # Root application (manages environment controllers)
├── apps/                            # ArgoCD application definitions
│   ├── environments/               # Environment controllers
│   │   ├── dev-apps.yaml           # Dev environment controller
│   │   └── production-apps.yaml    # Production environment controller
│   └── services/                   # Service application definitions
│       ├── demo-app/
│       │   ├── dev.yaml            # Dev demo-app application
│       │   └── production.yaml     # Production demo-app application
│       └── api-service/
│           ├── dev.yaml            # Dev api-service application
│           └── production.yaml     # Production api-service application
├── environments/                    # Service manifests organized by service
│   ├── demo-app/
│   │   ├── dev/
│   │   │   ├── deployment.yaml     # Demo-app dev deployment (1 replica)
│   │   │   ├── service.yaml        # Demo-app dev ClusterIP service
│   │   │   └── post-sync-hook.yaml # Demo-app dev post-sync hook
│   │   └── production/
│   │       ├── deployment.yaml     # Demo-app prod deployment (3 replicas)
│   │       ├── service.yaml        # Demo-app prod LoadBalancer service
│   │       └── post-sync-hook.yaml # Demo-app prod post-sync hook
│   └── api-service/
│       ├── dev/
│       │   ├── deployment.yaml     # API service dev deployment (1 replica)
│       │   ├── service.yaml        # API service dev ClusterIP service
│       │   └── post-sync-hook.yaml # API service dev post-sync hook
│       └── production/
│           ├── deployment.yaml     # API service prod deployment (3 replicas)
│           ├── service.yaml        # API service prod LoadBalancer service
│           └── post-sync-hook.yaml # API service prod post-sync hook
└── scripts/
    ├── deploy-demo.sh              # Demo deployment script
    ├── demo-hooks.sh               # Demonstrate post-sync hooks behavior
    └── cleanup.sh                  # Cleanup script
```

## 🚀 How It Works

This demo uses the **App-of-Apps pattern** with **selective syncing** and **post-sync hooks**:

### App-of-Apps Hierarchy
1. **app-of-apps** (root) manages 2 environment controllers:
   - **dev-apps**: Manages all development applications
   - **production-apps**: Manages all production applications

2. **Environment controllers** manage service applications:
   - **dev-apps** → dev-demo-app, dev-api-service
   - **production-apps** → production-demo-app, production-api-service

3. **Service applications** watch their specific service directories:
   - **dev-demo-app**: Watches `environments/demo-app/dev/`
   - **dev-api-service**: Watches `environments/api-service/dev/`
   - **production-demo-app**: Watches `environments/demo-app/production/`
   - **production-api-service**: Watches `environments/api-service/production/`

### Selective Syncing by Service Directory
- Each service application watches only its own service directory
- Changes to demo-app files only affect demo-app applications
- Changes to api-service files only affect api-service applications

### Post-Sync Hooks
- **Dev Hooks**: Quick validation (10-15s wait, 2 retries, basic health checks)
- **Production Hooks**: Enhanced validation (20-30s wait, 3 retries, comprehensive checks)

### Selective Syncing + Hooks Behavior
- ✅ Update `environments/demo-app/dev/deployment.yaml` → **only dev-demo-app syncs + runs demo-app dev hook**
- ✅ Update `environments/api-service/dev/deployment.yaml` → **only dev-api-service syncs + runs api-service dev hook**
- ✅ Update `environments/demo-app/production/service.yaml` → **only production-demo-app syncs + runs demo-app production hook**
- ✅ Update `environments/api-service/production/service.yaml` → **only production-api-service syncs + runs api-service production hook**
- ✅ Update multiple service directories → **only relevant apps sync independently + respective hooks run**

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
vim app-of-apps.yaml                           # Change repoURL to your forked repository
vim apps/environments/dev-apps.yaml            # Change repoURL to your forked repository
vim apps/environments/production-apps.yaml     # Change repoURL to your forked repository
vim apps/services/demo-app/dev.yaml            # Change repoURL to your forked repository
vim apps/services/demo-app/production.yaml     # Change repoURL to your forked repository
vim apps/services/api-service/dev.yaml         # Change repoURL to your forked repository
vim apps/services/api-service/production.yaml  # Change repoURL to your forked repository

# Run the demo deployment (deploys root app-of-apps)
./scripts/deploy-demo.sh
```

## 🎯 Testing App-of-Apps + Selective Sync

### Scenario 1: Update Demo-App in Development Only
```bash
# Edit dev demo-app deployment
vim environments/dev/deployment.yaml  # Change replicas from 1 to 2

# Commit and push
git add environments/dev/deployment.yaml
git commit -m "Scale dev demo-app to 2 replicas"
git push

# Watch ArgoCD - only dev-demo-app will sync
kubectl get applications -n argocd -w

# Watch the post-sync hook job
kubectl get jobs -n demo-app-dev -w
kubectl logs -f job/dev-post-sync-validation -n demo-app-dev
```

**Result**: Only the `dev-demo-app` application syncs + demo-app dev post-sync hook runs. All other apps (dev-api-service, production apps) remain untouched.

### Scenario 2: Update API Service in Production Only
```bash
# Edit production api-service deployment
vim environments/production/api-service-deployment.yaml  # Change replicas from 3 to 5

# Commit and push
git add environments/production/api-service-deployment.yaml
git commit -m "Scale production api-service to 5 replicas"
git push

# Watch ArgoCD - only production-api-service will sync
kubectl get applications -n argocd -w

# Watch the enhanced post-sync hook job
kubectl get jobs -n demo-app-prod -w
kubectl logs -f job/production-api-post-sync-validation -n demo-app-prod
```

**Result**: Only the `production-api-service` application syncs + api-service production post-sync hook runs. All other apps remain untouched.

### Scenario 3: Update Different Services in Different Environments
```bash
# Edit demo-app in dev and api-service in production
vim environments/dev/deployment.yaml                    # Change demo-app image to nginx:1.22
vim environments/production/api-service-service.yaml    # Change api-service type to NodePort

# Commit and push
git add environments/dev/deployment.yaml environments/production/api-service-service.yaml
git commit -m "Update demo-app in dev and api-service in prod"
git push

# Watch ArgoCD - only dev-demo-app and production-api-service sync
kubectl get applications -n argocd -w
```

**Result**: Only `dev-demo-app` and `production-api-service` sync independently + their respective post-sync hooks run in parallel. Other apps remain untouched.

### Scenario 4: Update Same Service Across Environments
```bash
# Edit api-service in both environments
vim environments/dev/api-service-deployment.yaml        # Change image to httpd:2.5
vim environments/production/api-service-deployment.yaml # Change image to httpd:2.5

# Commit and push
git add environments/*/api-service-deployment.yaml
git commit -m "Update api-service to httpd:2.5 in all environments"
git push

# Watch ArgoCD - both api-service apps sync independently
kubectl get applications -n argocd -w
```

**Result**: Both `dev-api-service` and `production-api-service` sync independently + their respective post-sync hooks run in parallel. Demo-app applications remain untouched.

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
# List all applications (parent + children)
kubectl get applications -n argocd

# Get detailed status of parent app
kubectl describe application app-of-apps -n argocd

# Get detailed status of child applications
kubectl describe application dev-demo-app -n argocd
kubectl describe application dev-api-service -n argocd
kubectl describe application production-demo-app -n argocd
kubectl describe application production-api-service -n argocd

# Check post-sync validation jobs for all services
kubectl get jobs -n demo-app-dev
kubectl get jobs -n demo-app-prod

# View post-sync hook logs for all services
kubectl logs -l job-name=dev-post-sync-validation -n demo-app-dev
kubectl logs -l job-name=dev-api-post-sync-validation -n demo-app-dev
kubectl logs -l job-name=production-post-sync-validation -n demo-app-prod
kubectl logs -l job-name=production-api-post-sync-validation -n demo-app-prod

# Check deployed resources in both namespaces
kubectl get all -n demo-app-dev
kubectl get all -n demo-app-prod
```

### Access Applications
```bash
# Access dev demo-app (port 8080)
kubectl port-forward svc/demo-app-service -n demo-app-dev 8080:80

# Access dev api-service (port 8082)
kubectl port-forward svc/api-service -n demo-app-dev 8082:80

# Access production demo-app (port 8081)
kubectl port-forward svc/demo-app-service -n demo-app-prod 8081:80

# Access production api-service (port 8083)
kubectl port-forward svc/api-service -n demo-app-prod 8083:80

# Visit:
# http://localhost:8080 (dev demo-app)
# http://localhost:8081 (production demo-app)
# http://localhost:8082 (dev api-service)
# http://localhost:8083 (production api-service)
```

## 🧹 Cleanup

```bash
# Use the cleanup script (recommended)
./scripts/cleanup.sh

# Or manually:
kubectl delete application app-of-apps -n argocd  # This removes parent + all children
kubectl delete namespace demo-app-dev demo-app-prod
```

## 🆚 Comparison with Full Project

| Feature | This Demo | Full Project |
|---------|-----------|--------------|
| **Pattern** | App-of-Apps with selective sync | ApplicationSet with advanced selective sync |
| **Environments** | 2 (dev, production) | 3 (dev, staging, production) |
| **Applications** | 7 total (1 root + 2 env controllers + 4 services) | 7 total (1 ApplicationSet + 6 generated apps) |
| **Services** | 2 (demo-app, api-service) | 2 (demo-app, api-service) |
| **Post-Sync Hooks** | Per service (dev: 10-15s, prod: 20-30s) | Advanced custom validation per app |
| **Scripts** | 3 scripts | 8+ comprehensive scripts |
| **Management** | Hierarchical (root → env → services) | Automated app generation |
| **Complexity** | Intermediate (Proper App-of-Apps hierarchy) | Production-ready (Advanced patterns) |

## 💡 Key Takeaways

1. **App-of-Apps Pattern**: Parent application manages multiple child applications for better organization
2. **File-Pattern-Based Watching**: Each child application watches specific file patterns within the same directory
3. **Service-Level Isolation**: Changes to one service only trigger syncs for that specific service's applications
4. **Independent Syncing**: Changes only trigger syncs for applications watching the changed files
5. **Resource Efficiency**: No unnecessary syncs or deployments across unrelated services
6. **Scalable Architecture**: Easy to add new services or environments by adding new child applications
7. **GitOps Best Practice**: Maintain separation of concerns between services and environments

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

**This demonstrates the App-of-Apps pattern with selective sync.** For a production-ready implementation with ApplicationSets, advanced selective sync features, comprehensive monitoring, and automated management scripts, see the [full argocd-selective-sync project](https://github.com/nicholasadamou/argocd-selective-sync).
