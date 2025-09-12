# Modular ArgoCD Selective Sync Demo

This directory contains the modularized implementation of the ArgoCD selective sync demonstration. The original monolithic `demo-selective-sync.sh` script has been refactored into smaller, maintainable modules for better organization and readability.

## 📁 Structure

```
scripts/demo/
├── README.md                    # This file
├── run.sh                      # Main entrypoint script
└── lib/                        # Library modules
    ├── demo-common.sh          # Common functions and prerequisites
    ├── demo-state.sh           # State management and monitoring
    ├── demo-workflow.sh        # Helm workflow execution
    └── demo-cleanup.sh         # Cleanup and artifact removal
```

## 🎯 Module Responsibilities

### `run.sh` - Main Entrypoint
- **Purpose**: Orchestrates the entire demo workflow
- **Size**: ~143 lines (vs. 850+ in monolithic version)
- **Functions**: Argument parsing, user interaction, workflow coordination
- **Dependencies**: All lib modules

### `lib/demo-common.sh` - Common Functions
- **Purpose**: Shared functionality and prerequisites checking
- **Size**: ~106 lines
- **Functions**: Prerequisites validation, Vagrant lock checking, logging, initialization
- **Dependencies**: `scripts/helm/lib/nexus-common.sh`

### `lib/demo-state.sh` - State Management
- **Purpose**: State display, monitoring, and analysis
- **Size**: ~264 lines
- **Functions**: `show_initial_state()`, `monitor_selective_sync()`, `show_results()`, `analyze_results()`
- **Dependencies**: `demo-common.sh`

### `lib/demo-workflow.sh` - Workflow Execution
- **Purpose**: Helm workflow execution and dry-run simulation
- **Size**: ~161 lines
- **Functions**: `make_selective_change()`, `make_selective_change_dry_run()`
- **Dependencies**: `demo-common.sh`

### `lib/demo-cleanup.sh` - Cleanup Operations
- **Purpose**: Git revert and Helm artifact cleanup
- **Size**: ~180 lines
- **Functions**: `cleanup_demo()` with comprehensive artifact removal
- **Dependencies**: `demo-common.sh`

## 🔄 Migration Benefits

### Before (Monolithic)
- **Single file**: 850+ lines
- **Hard to maintain**: All functionality mixed together
- **Difficult to test**: Individual functions not easily isolated
- **Poor readability**: Long functions with multiple responsibilities

### After (Modular)
- **Multiple files**: Largest is 264 lines
- **Easy to maintain**: Clear separation of concerns
- **Testable**: Each module can be tested independently
- **Better readability**: Focused, single-responsibility modules

## 🚀 Usage

The refactoring is transparent to users. All existing commands work exactly the same:

```bash
# All these commands work identically to the original script
./scripts/demo-selective-sync.sh                    # Interactive demo
./scripts/demo-selective-sync.sh --dry-run          # Show what would be done
./scripts/demo-selective-sync.sh -y                 # Auto-run with cleanup
./scripts/demo-selective-sync.sh --no-cleanup       # Skip cleanup

# Direct access to modular version
./scripts/demo/run.sh --help                        # Same functionality
```

## 🛠️ Development

### Adding New Features
1. **State-related features**: Add to `lib/demo-state.sh`
2. **Workflow enhancements**: Add to `lib/demo-workflow.sh`  
3. **Cleanup improvements**: Add to `lib/demo-cleanup.sh`
4. **Common utilities**: Add to `lib/demo-common.sh`

### Testing Individual Modules
```bash
# Test prerequisites only
source scripts/demo/lib/demo-common.sh && check_demo_prerequisites

# Test state display only  
source scripts/demo/lib/demo-state.sh && show_initial_state

# Test workflow dry-run only
source scripts/demo/lib/demo-workflow.sh && make_selective_change_dry_run
```

### Module Dependencies
```
run.sh
├── demo-common.sh
│   └── ../helm/lib/nexus-common.sh
├── demo-state.sh
│   └── demo-common.sh
├── demo-workflow.sh  
│   └── demo-common.sh
└── demo-cleanup.sh
    └── demo-common.sh
```

## 📝 Design Principles

1. **Single Responsibility**: Each module handles one aspect of the demo
2. **Self-Contained**: Modules can be used independently
3. **Consistent Interface**: All modules use the same logging and error handling
4. **Backward Compatible**: Original script interface is preserved
5. **Maintainable**: Code is easier to understand, modify, and debug

## 🔗 Integration

The modular demo integrates seamlessly with existing scripts:
- Uses `scripts/helm/lib/nexus-common.sh` for Nexus operations
- Calls `scripts/helm/helm-workflow.sh` for Helm operations
- Maintains compatibility with `vagrant-ssh` and `vagrant-scp` tools
- Preserves all original functionality and command-line options

This modular architecture makes the codebase much more maintainable while preserving the full functionality and user experience of the original demo script.
