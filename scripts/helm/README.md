# Helm Repository Setup Scripts

This directory contains scripts to automate the setup of a local Nexus repository for Helm charts and the packaging/uploading of environment charts for ArgoCD.

## Overview

The scripts in this directory automate the complete workflow for:

1. **Building Helm packages** from Kubernetes manifests in the `environments/` directory
2. **Setting up Nexus Repository Manager** with proper configuration
3. **Creating a Helm repository** in Nexus
4. **Uploading Helm packages** to the repository
5. **Configuring anonymous access** for ArgoCD integration

## Prerequisites

Before running these scripts, ensure you have:

- **Vagrant** environment running with Docker support
- **vagrant-scripts** toolkit installed and available in your PATH:
  - `vagrant-ssh` - Enhanced SSH access to Vagrant
  - `vagrant-scp` - File transfer to/from Vagrant
- **Helm CLI** installed and available in your PATH
- Proper network connectivity between your host and Vagrant environment

**Install vagrant-scripts:**
```bash
# Clone and install the vagrant-scripts toolkit
git clone https://github.com/nicholasadamou/vagrant-scripts.git
cd vagrant-scripts
./install.sh
```

## Scripts

### 1. `build-helm-packages.sh`

Converts Kubernetes manifests in `environments/` directories into Helm charts and packages them.

**What it does:**
- Creates `helm-packages/` directory in project root
- Validates each environment directory has proper Helm chart structure
- Packages each chart into `.tgz` files
- Verifies Chart.yaml and templates/ directory exist

**Usage:**
```bash
# From project root directory
./scripts/helm/build-helm-packages.sh
```

**Output:**
- `helm-packages/dev-api-app-0.1.0.tgz`
- `helm-packages/dev-demo-app-0.1.0.tgz`
- `helm-packages/dev-applications-0.1.0.tgz`
- `helm-packages/production-api-app-0.1.0.tgz`
- `helm-packages/production-demo-app-0.1.0.tgz`
- `helm-packages/production-applications-0.1.0.tgz`

### 2. `setup-nexus.sh`

Completely automates Nexus Repository Manager setup and Helm chart deployment.

**What it does:**
1. **Container Management:**
   - Stops and removes any existing Nexus container
   - Starts fresh sonatype/nexus3 container on port 8081
   - Waits for Nexus to be fully ready (up to 5 minutes)

2. **Nexus Configuration:**
   - Retrieves initial admin password from container
   - Accepts End User License Agreement (EULA)
   - Completes onboarding wizard
   - Changes admin password from random initial to `admin123`
   - Enables anonymous access for easier ArgoCD integration

3. **Helm Repository Setup:**
   - Creates `helm-hosted` repository in Nexus
   - Configures proper storage and write policies

4. **Package Deployment:**
   - Copies all Helm packages from `helm-packages/` to Vagrant
   - Uploads each package to the Nexus repository
   - Verifies successful upload

5. **Verification:**
   - Tests repository access
   - Validates all components are working

**Usage:**
```bash
# From project root directory (after running build-helm-packages.sh)
./scripts/helm/setup-nexus.sh

# For a completely fresh installation (removes existing data)
./scripts/helm/setup-nexus.sh --fresh
```

**Options:**
- `--fresh`: Force a clean installation by removing existing container and persistent data volume
- `--help`: Show help message and exit

### 3. `complete_onboarding.sh`

Handles manual EULA acceptance and onboarding completion for Nexus Repository Manager.

**What it does:**
1. **Prerequisites Check:**
   - Verifies vagrant-ssh is available
   - Validates project directory structure
   - Confirms Nexus container is running

2. **EULA Management:**
   - Checks current EULA acceptance status
   - Provides web interface instructions for EULA acceptance
   - Monitors and validates EULA acceptance completion
   - Handles the interactive onboarding process

3. **Integration:**
   - Called automatically by `setup-nexus.sh`
   - Can be run standalone for troubleshooting
   - Handles cases where automated EULA acceptance fails

**Usage:**
```bash
# Called automatically by setup-nexus.sh (recommended)
./scripts/helm/setup-nexus.sh

# Manual execution (for troubleshooting)
./scripts/helm/complete_onboarding.sh
```

**When to use manually:**
- If `setup-nexus.sh` fails during EULA acceptance
- For troubleshooting onboarding issues
- When you need to re-run just the onboarding step

### 3. `upload-helm-packages.sh`

Dedicated script for uploading Helm packages to Nexus repository.

**What it does:**
1. **Package Transfer:**
   - Copies Helm packages from `./helm-packages/` to Vagrant environment
   - Uses base64 encoding for reliable file transfer across platforms
   - Handles multiple package files automatically

2. **Nexus Upload:**
   - Uploads packages to the `helm-hosted` repository
   - Verifies successful upload for each package
   - Provides detailed logging for troubleshooting

3. **Prerequisites Check:**
   - Validates Nexus container is running
   - Checks vagrant-scripts availability
   - Ensures packages directory exists

**Usage:**
```bash
# Upload all packages in ./helm-packages/
./scripts/helm/upload-helm-packages.sh
```

**When to use:**
- After building packages with `build-helm-packages.sh`
- When you need to re-upload without full Nexus setup
- As part of automated CI/CD workflows
- For troubleshooting upload issues separately

### 4. `helm-workflow.sh`

Comprehensive Helm workflow management for complete version lifecycle.

**What it does:**
1. **Version Management:**
   - Semantic version bumping (major, minor, patch)
   - Updates Chart.yaml versions automatically
   - Maintains proper version history

2. **ArgoCD Integration:**
   - Updates targetRevision in ArgoCD application manifests
   - Handles both dev and production environments
   - Ensures consistency between chart and ArgoCD versions

3. **Complete Workflows:**
   - Scale applications and publish new versions
   - Build and upload packages to Nexus
   - Handle replica scaling without version changes

**Commands:**
```bash
# Scale app to 3 replicas and publish new version
./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app 3

# Bump version without scaling
./scripts/helm/helm-workflow.sh bump-version dev-api-app minor

# Build and upload all packages
./scripts/helm/helm-workflow.sh publish-packages

# Scale replicas only (no version bump)
./scripts/helm/helm-workflow.sh scale-only dev-api-app 2
```

**Integration:**
- Used by `demo-selective-sync.sh` automatically
- Can be used standalone for manual operations
- Integrates with build and upload scripts

### 5. Shared Library: `lib/nexus-common.sh`

A common library providing shared functionality across all scripts to eliminate code duplication and ensure consistency.

**Features:**
- **Logging Functions:** Standardized `log()`, `warn()`, `error()`, `success()` with color coding
- **Vagrant Integration:** `vagrant_ssh()`, `vagrant_upload()` helper functions
- **Prerequisite Checking:** `check_prerequisites()` with flexible dependency validation
- **Nexus Operations:** `check_nexus_container()`, `wait_for_nexus()`, `test_nexus_auth()`
- **EULA Management:** `check_eula_status()` for consistent EULA handling
- **Common Configuration:** Shared variables for URLs, container names, passwords
- **Initialization:** `nexus_common_init()` for consistent script startup

**Benefits:**
- **DRY Principle:** No code duplication between scripts
- **Consistency:** All scripts use identical error handling and logging
- **Maintainability:** Changes to common functionality in one place
- **Flexibility:** Support for different prerequisite combinations per script

**Configuration Variables:**
```bash
NEXUS_URL="http://localhost:8081"           # Nexus URL
NEW_ADMIN_PASSWORD="admin123"               # New admin password
CONTAINER_NAME="nexus"                      # Docker container name
HELM_REPO_NAME="helm-hosted"                # Nexus repository name
```

## Complete Workflow

To set up the complete Helm repository from scratch:

### Automated Setup (Recommended)
```bash
# 1. Navigate to project root
cd /path/to/argocd-selective-sync-demo

# 2. Build Helm packages from environment manifests
./scripts/helm/build-helm-packages.sh

# 3a. Complete setup with existing data (if any)
./scripts/helm/setup-nexus.sh

# 3b. OR for a completely fresh setup (recommended for first run)
./scripts/helm/setup-nexus.sh --fresh
```

### Manual/Troubleshooting Workflow
If you need more control or encounter issues:

```bash
# 1. Build packages
./scripts/helm/build-helm-packages.sh

# 2. Set up Nexus (may require manual EULA acceptance)
./scripts/helm/setup-nexus.sh --fresh

# 3. If EULA acceptance fails, complete it manually
./scripts/helm/complete_onboarding.sh

# 4. Re-run setup to complete the process
./scripts/helm/setup-nexus.sh
```

### Script Dependencies
- `build-helm-packages.sh` → Standalone (requires Helm CLI)
- `setup-nexus.sh` → Calls `complete_onboarding.sh` and `upload-helm-packages.sh`
- `upload-helm-packages.sh` → Standalone package upload (uses common library)
- `helm-workflow.sh` → Uses `build-helm-packages.sh` and `upload-helm-packages.sh`
- `complete_onboarding.sh` → Standalone EULA and onboarding management
- All scripts use `lib/nexus-common.sh` for shared functionality

### Modern Workflow (Recommended)
```bash
# Complete workflow with version management
./scripts/helm/helm-workflow.sh scale-and-publish dev-api-app 2

# This single command handles:
# 1. Scale replicas in deployment template
# 2. Bump chart version (semantic versioning)
# 3. Update ArgoCD targetRevision
# 4. Build Helm packages
# 5. Upload to Nexus repository
```

## Post-Setup Information

After successful execution, you'll have:

### Nexus Repository Manager
- **URL:** http://localhost:8081
- **Admin Credentials:** `admin` / `admin123`
- **Anonymous Access:** Enabled

### Helm Repository
- **Repository Name:** `helm-hosted`
- **Repository URL:** http://10.42.0.1:8081/repository/helm-hosted/
- **Available Charts:**
  - `dev-api-app` (version 0.1.0)
  - `dev-demo-app` (version 0.1.0)
  - `dev-applications` (version 0.1.0)
  - `production-api-app` (version 0.1.0)
  - `production-demo-app` (version 0.1.0)
  - `production-applications` (version 0.1.0)

### ArgoCD Integration

The ArgoCD Application manifests in `app-of-apps/` are already configured to use the Helm repository:

```yaml
spec:
  source:
    repoURL: http://10.42.0.1:8081/repository/helm-hosted/
    chart: dev-api-app
    targetRevision: 0.1.0
```

## Troubleshooting

### Common Issues

1. **Script fails with "Please run this script from the project root directory"**
   - Ensure you're running the script from the repository root where `README.md` and `environments/` exist
   - The common library validates directory structure automatically

2. **"vagrant-ssh command not found" or "vagrant-scp command not found"**
   - Install the vagrant-scripts toolkit: `git clone https://github.com/nicholasadamou/vagrant-scripts.git && cd vagrant-scripts && ./install.sh`
   - Verify commands are available: `which vagrant-ssh` and `which vagrant-scp`
   - Check that `~/.local/bin` is in your PATH

3. **"Missing required dependencies" error**
   - The scripts now check prerequisites automatically using the common library
   - Install missing dependencies as indicated by the error messages
   - Each script checks only the dependencies it actually needs

4. **"Nexus failed to start within expected time"**
   - Nexus container may need more time to initialize
   - Check if port 8081 is already in use: `vagrant-ssh "netstat -tlnp | grep 8081"`
   - Verify Docker is running in your Vagrant environment: `vagrant-ssh "docker ps"`
   - Try restarting with `--fresh` flag: `./scripts/helm/setup-nexus.sh --fresh`

5. **EULA acceptance issues**
   - If `setup-nexus.sh` hangs on EULA acceptance, run `complete_onboarding.sh` manually
   - Open `http://localhost:8081` in browser and complete onboarding manually
   - The scripts will guide you through the web interface steps
   - Check EULA status: `vagrant-ssh "curl -u admin:admin123 http://localhost:8081/service/rest/v1/system/eula"`

6. **Package upload failures**
   - Ensure helm-packages directory exists with .tgz files
   - Run `build-helm-packages.sh` first to create packages
   - Check network connectivity between host and Vagrant
   - Verify Nexus container is running: `vagrant-ssh "docker ps | grep nexus"`

7. **Authentication issues**
   - Scripts automatically handle password changes from initial random password to `admin123`
   - If manual intervention needed, check container logs: `vagrant-ssh "docker logs nexus"`
   - Reset password using Nexus web interface if necessary

8. **helm-workflow.sh issues**
   - Ensure you're running from project root directory
   - Check that Chart.yaml exists in target environment directory
   - Verify ArgoCD application files exist in correct locations
   - For version conflicts, manually check and resolve Chart.yaml versions
   - Use individual scripts for debugging: `build-helm-packages.sh` then `upload-helm-packages.sh`

9. **upload-helm-packages.sh failures**
   - Ensure `./helm-packages/` directory exists with .tgz files
   - Check base64 command availability in both host and Vagrant
   - Verify file permissions and paths
   - Test with single package first for troubleshooting

### Manual Verification

To manually verify the setup:

```bash
# Check if Nexus is running
vagrant-ssh "docker ps | grep nexus"

# Test repository access
curl -u admin:admin123 http://localhost:8081/service/rest/v1/repositories

# List uploaded packages
curl -u admin:admin123 http://localhost:8081/service/rest/v1/search?repository=helm-hosted

# Test helm workflow commands
./scripts/helm/helm-workflow.sh bump-version dev-api-app patch
./scripts/helm/upload-helm-packages.sh
```

### Cleanup

To completely clean up and start over:

```bash
# Option 1: Use the --fresh flag on next run
./scripts/helm/setup-nexus.sh --fresh

# Option 2: Manual cleanup
# Stop and remove Nexus container
vagrant-ssh "docker stop nexus && docker rm nexus"

# Remove persistent data
vagrant-ssh "docker volume rm nexus-data"

# Remove local packages
rm -rf helm-packages/
```

## Script Features

### Modular Architecture
- **Shared Library:** `lib/nexus-common.sh` eliminates code duplication
- **Specialized Scripts:** Each script focuses on specific functionality
- **Consistent Interface:** Standardized logging, error handling, and configuration
- **Flexible Prerequisites:** Scripts check only required dependencies

### Error Handling
- Comprehensive error checking at each step using common library
- Colored output for easy identification of issues (INFO, WARN, ERROR, SUCCESS)
- Graceful failure with helpful error messages and suggested solutions
- Automatic cleanup of failed states
- Prerequisite validation before execution

### Logging
- Detailed progress logging with standardized format
- Color-coded output using shared logging functions
- Clear indication of current operation and step progress
- Consistent message formatting across all scripts

### Robustness
- Waits for services to be fully ready with configurable timeouts
- Retries on temporary failures with exponential backoff
- Validates preconditions before execution using common library
- Verifies successful completion at each step
- Container state management and health checking

### Reproducibility
- Idempotent operations (can be run multiple times safely)
- Consistent environment setup using shared configuration
- Automated credential management and EULA handling
- Minimal manual intervention required
- Self-contained package creation and deployment

## Integration with ArgoCD

Once the Helm repository is set up, ArgoCD will:

1. Pull Helm charts from the local Nexus repository
2. Deploy applications based on the `targetRevision` specified
3. Automatically sync when `targetRevision` is updated
4. Use the charts for application deployment instead of raw Kubernetes manifests

This setup enables proper versioning and selective sync capabilities for ArgoCD applications.

## Integration with Demo Script

The `../demo-selective-sync.sh` script automatically detects and integrates with the Helm setup:

```bash
# Automatically detects Helm configuration and uses appropriate workflow
./scripts/demo-selective-sync.sh
```

**Smart Detection:**
- **Helm Mode**: Detects `chart:` configuration in ArgoCD apps
- **Git Mode**: Falls back to traditional Git-based workflow
- **Automatic Workflow**: Uses `helm-workflow.sh` for complete version management
- **No Manual Selection**: Zero configuration required

**Helm Mode Demo Flow:**
1. Detect Helm chart configuration in ArgoCD applications
2. Scale `dev-api-app` replicas using `helm-workflow.sh scale-and-publish`
3. Monitor ArgoCD sync behavior with new `targetRevision`
4. Verify selective sync (only `dev-api-app` affected)
5. Auto-cleanup with proper Git revert workflow

This demonstrates the complete Helm workflow:
- ✅ Semantic versioning
- ✅ Package management
- ✅ ArgoCD integration
- ✅ Selective sync behavior
