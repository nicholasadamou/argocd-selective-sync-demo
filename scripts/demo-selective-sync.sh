#!/bin/bash

# demo-selective-sync.sh
# Wrapper script for the modular ArgoCD selective sync demo
# The actual implementation has been refactored into scripts/demo/ for better maintainability

set -euo pipefail

# Get script directory and locate the modular demo runner
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
MODULAR_DEMO="$SCRIPT_DIR/demo/run.sh"

# Check if the modular demo exists
if [ ! -x "$MODULAR_DEMO" ]; then
    echo "Error: Modular demo script not found at: $MODULAR_DEMO"
    echo "Please ensure the demo has been properly set up."
    exit 1
fi

# Pass all arguments to the modular demo script
exec "$MODULAR_DEMO" "$@"
