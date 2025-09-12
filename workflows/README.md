# Argo Workflows Setup Guide

This directory contains the Argo Workflows configuration that replaces the previous post sync hooks. The workflows provide more advanced validation capabilities with better retry logic, monitoring, and resource management.

## Architecture

The workflow system consists of:

1. **WorkflowTemplates**: Reusable workflow definitions for dev and production environments
2. **Workflow Triggers**: ArgoCD post-sync hooks that trigger the workflows
3. **RBAC**: Service account and permissions for workflow execution

## Files Structure

```
workflows/
├── templates/
│   ├── dev-validation-workflow-template.yaml      # Dev environment validation template
│   └── production-validation-workflow-template.yaml  # Production validation template
├── rbac.yaml                                       # Service account and RBAC
└── README.md                                       # This file

environments/
├── dev-api-app/templates/validation-workflow.yaml
├── dev-demo-app/templates/validation-workflow.yaml
├── production-api-app/templates/validation-workflow.yaml
└── production-demo-app/templates/validation-workflow.yaml
```

## Prerequisites

1. **Argo Workflows Controller** must be installed in your cluster
2. **ArgoCD** with workflow support enabled
3. **Proper RBAC** permissions for workflow execution

## Installation Steps

### 1. Install Argo Workflows (if not already installed)

```bash
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/install.yaml
```

### 2. Apply RBAC and WorkflowTemplates

```bash
# Apply RBAC configuration
kubectl apply -f workflows/rbac.yaml

# Apply WorkflowTemplates
kubectl apply -f workflows/templates/
```

### 3. Verify Installation

```bash
# Check if WorkflowTemplates are created
kubectl get workflowtemplates -n argo

# Check service account
kubectl get serviceaccount argo-workflow -n argo
```

## How It Works

### Dev Environment Workflows
- **Template**: `dev-validation-workflow`
- **Wait Time**: 10-15 seconds
- **Retries**: Single attempt with fallback
- **Scope**: Basic health checks and connectivity tests

### Production Environment Workflows
- **Template**: `production-validation-workflow`
- **Wait Time**: 20-30 seconds
- **Retries**: 3-5 attempts with configurable delays
- **Scope**: Comprehensive health checks, retry logic, and stricter validation

### Workflow Parameters

Both templates accept the following parameters:

- `environment`: Target environment (dev/production)
- `service-name`: Name of the service being validated
- `service-type`: Type of service (api/demo)
- `health-endpoint`: Health check endpoint path
- `wait-time`: Seconds to wait before validation
- `retries`: Number of retry attempts (production only)
- `retry-delay`: Delay between retries (production only)

## Monitoring Workflows

### View Workflow Status
```bash
# List all workflows
kubectl get workflows --all-namespaces

# Get workflow details
kubectl describe workflow <workflow-name> -n <app-namespace>

# View workflow logs
kubectl logs -f <pod-name> -n <app-namespace>
```

### Argo Workflows UI
Access the Argo Workflows UI to monitor workflow execution:
```bash
kubectl port-forward svc/argo-server -n argo 2746:2746
```
Then open: https://localhost:2746

## Advantages Over Post Sync Hooks

1. **Better Resource Management**: Workflows have proper resource limits and garbage collection
2. **Advanced Retry Logic**: Configurable retry attempts with exponential backoff
3. **Monitoring & Observability**: Rich UI and logging capabilities
4. **Reusability**: Parameterized templates reduce code duplication
5. **Scalability**: Workflows can handle complex multi-step validations
6. **Integration**: Better integration with CI/CD pipelines and monitoring systems

## Troubleshooting

### Common Issues

1. **Workflow stuck in Pending**
   - Check if Argo Workflows controller is running
   - Verify RBAC permissions

2. **Validation failures**
   - Check service endpoints are correct
   - Verify network connectivity between workflow pods and services

3. **Template not found**
   - Ensure WorkflowTemplates are applied to the `argo` namespace
   - Check template names match in workflow triggers

### Debug Commands

```bash
# Check workflow controller logs
kubectl logs -n argo deployment/workflow-controller

# Describe failing workflow
kubectl describe workflow <workflow-name> -n <app-namespace>

# Check service connectivity
kubectl exec -it <workflow-pod> -n <app-namespace> -- curl http://service-url/health
```
