#!/bin/bash

# Deploy Service-Specific ArgoCD Controllers
# This script deploys individual ApplicationSet controllers for each service/environment combination

set -e

echo "🚀 Deploying ArgoCD Service-Specific Controllers..."

# Define controller files
CONTROLLERS=(
    "apps/controllers/demo-app-dev-controller.yaml"
    "apps/controllers/demo-app-production-controller.yaml"
    "apps/controllers/api-service-dev-controller.yaml"
    "apps/controllers/api-service-production-controller.yaml"
)

# Deploy each controller
for controller in "${CONTROLLERS[@]}"; do
    echo "📦 Deploying $controller..."
    kubectl apply -f "$controller"
done

echo "✅ All controllers deployed successfully!"

echo "📊 Current ApplicationSets:"
kubectl get applicationsets -n argocd

echo "📊 Current Applications:"
kubectl get applications -n argocd

echo ""
echo "🎯 You now have individual controllers for each service in each environment:"
echo "  - demo-app-dev-controller -> dev-demo-app"
echo "  - demo-app-production-controller -> production-demo-app"
echo "  - api-service-dev-controller -> dev-api-service"
echo "  - api-service-production-controller -> production-api-service"
echo ""
echo "🔧 To deploy individual controllers:"
echo "  kubectl apply -f apps/controllers/demo-app-dev-controller.yaml"
echo ""
echo "🗑️  To remove all controllers:"
echo "  kubectl delete applicationsets -n argocd -l app.kubernetes.io/part-of=selective-sync-demo"
