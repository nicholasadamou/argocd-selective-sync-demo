#!/bin/bash

# fix-vagrant-lock.sh
# Helper script to resolve Vagrant lock issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_vagrant_lock() {
    log "Checking Vagrant lock status..."
    
    # Determine Vagrant directory - look for common locations
    local vagrant_dirs=(
        "$HOME/code/gitlab/beast/operational/repo/vagrant"
    )
    
    local vagrant_dir=""
    for dir in "${vagrant_dirs[@]}"; do
        if [ -f "$dir/Vagrantfile" ]; then
            vagrant_dir="$dir"
            log "Found Vagrant directory: $vagrant_dir"
            break
        fi
    done
    
    if [ -z "$vagrant_dir" ]; then
        warn "Could not find Vagrant directory with Vagrantfile"
        return 1
    fi
    
    # Change to Vagrant directory and check status
    local current_dir="$(pwd)"
    cd "$vagrant_dir" || {
        error "Failed to change to Vagrant directory: $vagrant_dir"
        return 1
    }
    
    local vagrant_output
    vagrant_output=$(vagrant status 2>&1 || true)
    
    # Return to original directory
    cd "$current_dir"
    
    if echo "$vagrant_output" | grep -q "locked"; then
        return 1  # Locked
    else
        return 0  # Not locked
    fi
}

show_vagrant_processes() {
    log "Checking for running Vagrant processes..."
    
    local vagrant_processes
    vagrant_processes=$(ps aux | grep -i vagrant | grep -v grep | grep -v "$0" || true)
    
    if [ -n "$vagrant_processes" ]; then
        warn "Found running Vagrant processes:"
        echo "$vagrant_processes"
        return 1
    else
        log "No running Vagrant processes found"
        return 0
    fi
}

kill_vagrant_processes() {
    warn "Attempting to kill stuck Vagrant processes..."
    
    local pids
    pids=$(ps aux | grep -i vagrant | grep -v grep | grep -v "$0" | awk '{print $2}' || true)
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            log "Killing process $pid..."
            if kill "$pid" 2>/dev/null; then
                success "Process $pid killed"
            else
                warn "Could not kill process $pid (may not exist or require sudo)"
            fi
        done
        
        # Wait a moment for processes to die
        sleep 3
        
        # Check if any are still running
        local remaining_pids
        remaining_pids=$(ps aux | grep -i vagrant | grep -v grep | grep -v "$0" | awk '{print $2}' || true)
        
        if [ -n "$remaining_pids" ]; then
            warn "Some processes still running, trying SIGKILL..."
            for pid in $remaining_pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
    else
        log "No Vagrant processes to kill"
    fi
}

remove_lock_files() {
    warn "Attempting to remove Vagrant lock files..."
    
    # Common lock file locations
    local lock_locations=(
        "$HOME/.vagrant.d"
        ".vagrant"
    )
    
    for location in "${lock_locations[@]}"; do
        if [ -d "$location" ]; then
            log "Checking for lock files in: $location"
            local lock_files
            lock_files=$(find "$location" -name "*.lock" 2>/dev/null || true)
            
            if [ -n "$lock_files" ]; then
                warn "Found lock files:"
                echo "$lock_files"
                
                read -p "Remove these lock files? (y/N): " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "$lock_files" | xargs rm -f
                    success "Lock files removed"
                else
                    log "Skipping lock file removal"
                fi
            else
                log "No lock files found in $location"
            fi
        fi
    done
}

reload_vagrant() {
    warn "Attempting to reload Vagrant machine..."
    
    # Find Vagrant directory (same logic as check_vagrant_lock)
    local vagrant_dirs=(
        "$HOME/code/gitlab/beast/operational/repo/vagrant"
    )
    
    local vagrant_dir=""
    for dir in "${vagrant_dirs[@]}"; do
        if [ -f "$dir/Vagrantfile" ]; then
            vagrant_dir="$dir"
            break
        fi
    done
    
    if [ -z "$vagrant_dir" ]; then
        error "Could not find Vagrant directory with Vagrantfile"
        return 1
    fi
    
    log "Using Vagrant directory: $vagrant_dir"
    
    # Change to Vagrant directory and reload
    local current_dir="$(pwd)"
    cd "$vagrant_dir" || {
        error "Failed to change to Vagrant directory: $vagrant_dir"
        return 1
    }
    
    if vagrant reload; then
        success "Vagrant machine reloaded successfully"
        cd "$current_dir"
        return 0
    else
        error "Failed to reload Vagrant machine"
        cd "$current_dir"
        return 1
    fi
}

main() {
    echo
    log "Vagrant Lock Resolution Helper"
    log "=============================="
    echo
    
    # Check if already unlocked
    if check_vagrant_lock; then
        success "✅ Vagrant is not locked - no action needed"
        exit 0
    fi
    
    warn "🔒 Vagrant lock detected"
    echo
    
    # Show available options
    log "Available fix options:"
    echo "1. Kill stuck Vagrant processes"
    echo "2. Remove lock files manually"
    echo "3. Reload Vagrant machine"
    echo "4. All of the above (recommended)"
    echo "5. Just check status and exit"
    echo
    
    read -p "Choose option [1-5]: " -r choice
    
    case $choice in
        1)
            show_vagrant_processes
            kill_vagrant_processes
            ;;
        2)
            remove_lock_files
            ;;
        3)
            reload_vagrant
            ;;
        4)
            log "Running comprehensive fix..."
            show_vagrant_processes
            kill_vagrant_processes
            sleep 2
            remove_lock_files
            sleep 2
            reload_vagrant
            ;;
        5)
            log "Status check only:"
            show_vagrant_processes
            exit 0
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo
    log "Checking final status..."
    
    if check_vagrant_lock; then
        success "🎉 Vagrant lock resolved successfully!"
        log "You can now run your demo or Helm scripts"
    else
        error "❌ Vagrant is still locked"
        warn "You may need to:"
        warn "  • Restart your terminal/shell session"
        warn "  • Reboot your system if locks persist"
        warn "  • Check for VirtualBox GUI processes that may be holding locks"
        warn "  • Contact system administrator if in a managed environment"
    fi
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
