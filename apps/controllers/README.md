# ArgoCD Application Controllers

This directory contains ArgoCD ApplicationSet controllers organized by service and environment.

## Structure

### Service-Specific Controllers
Each service has its own controller for each environment:

- **demo-app-dev-controller.yaml** - Controls demo-app in dev environment
- **demo-app-production-controller.yaml** - Controls demo-app in production environment
- **api-service-dev-controller.yaml** - Controls api-service in dev environment
- **api-service-production-controller.yaml** - Controls api-service in production environment

### Master Controller
- **master-controller.yaml** - App-of-Apps pattern controller that deploys all service-specific controllers

## Benefits of This Structure

1. **Granular Control**: Each service can be managed independently
2. **Environment Isolation**: Dev and production controllers are separate
3. **Selective Deployment**: You can deploy only specific service controllers
4. **Easier Troubleshooting**: Issues are isolated to specific service/environment combinations
5. **Better Labeling**: Each controller and its applications have specific labels for filtering

## Deployment

Deploy the master controller to get all service controllers:

```bash
kubectl apply -f apps/controllers/master-controller.yaml
```

Or deploy individual service controllers:

```bash
kubectl apply -f apps/controllers/demo-app-dev-controller.yaml
```

## Generated Applications

Each controller creates applications with the following naming convention:
- Dev applications: `dev-{service-name}`
- Production applications: `production-{service-name}`

## Labels

Applications are labeled with:
- `environment`: dev or production
- `service`: demo-app or api-service
- `controller`: name of the managing controller
- `app.kubernetes.io/part-of`: selective-sync-demo

## Migration from Old Controllers

The old environment-wide controllers (`dev-controller.yaml` and `production-controller.yaml`) have been moved to the `old-controllers/` directory. These created all services for an environment in a single ApplicationSet.

The new structure provides better granularity and control over individual services.
