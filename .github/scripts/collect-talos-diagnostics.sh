#!/bin/bash

# Script to collect talosctl diagnostics for support bundle
# This script will be run as part of the support bundle collection process

set -euo pipefail

# Create output directory
TALOS_DIAGNOSTICS_DIR="${1:-/tmp/talos-diagnostics}"
mkdir -p "$TALOS_DIAGNOSTICS_DIR"

# Function to safely run talosctl commands
run_talosctl() {
    local cmd="$1"
    local output_file="$2"
    local description="$3"
    
    echo "Collecting: $description"
    echo "Command: $cmd"
    if eval "$cmd" > "$output_file" 2>&1; then
        echo "✓ Successfully collected: $description"
    else
        local exit_code=$?
        echo "⚠ Failed to collect: $description (exit code: $exit_code)"
        echo "Command failed: $cmd" > "$output_file"
        echo "Exit code: $exit_code" >> "$output_file"
        echo "Error output:" >> "$output_file"
        eval "$cmd" >> "$output_file" 2>&1 || true
    fi
}

# Check if talosctl is available
if ! command -v talosctl &> /dev/null; then
    echo "talosctl not found, skipping talos diagnostics"
    exit 0
fi

# Get cluster nodes (if available)
NODES=""
if kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | grep -q .; then
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | tr ' ' ',')
fi

# If no nodes found via kubectl, try to get from talosctl config
if [ -z "$NODES" ]; then
    if talosctl config info 2>/dev/null | grep -q "endpoints:"; then
        NODES=$(talosctl config info 2>/dev/null | grep "endpoints:" | cut -d: -f2 | tr -d ' ' | tr ',' ' ')
    fi
fi

# Set node flag if we have nodes
NODE_FLAG=""
if [ -n "$NODES" ]; then
    NODE_FLAG="--nodes $NODES"
fi

echo "Collecting Talos diagnostics to: $TALOS_DIAGNOSTICS_DIR"
echo "Target nodes: ${NODES:-'auto-detect'}"

# Debug: Show talosctl version and available commands
echo "Talosctl version:"
talosctl version --client 2>/dev/null || echo "Failed to get version"
echo "Available talosctl commands:"
talosctl --help 2>/dev/null | grep -A 100 "Available Commands:" | head -20 || echo "Failed to get help"

# 1. Comprehensive support bundle (most important)
# Note: talosctl support requires specific node targeting, so we'll try without --output first
run_talosctl "talosctl support $NODE_FLAG" \
    "$TALOS_DIAGNOSTICS_DIR/talos-support-bundle.txt" \
    "Complete Talos support bundle"

# 2. Cluster health check
run_talosctl "talosctl health $NODE_FLAG" \
    "$TALOS_DIAGNOSTICS_DIR/talos-health.txt" \
    "Cluster health status"

# 3. Version information
run_talosctl "talosctl version $NODE_FLAG" \
    "$TALOS_DIAGNOSTICS_DIR/talos-version.txt" \
    "Talos version information"

# 4. Node information (if we have specific nodes)
if [ -n "$NODES" ]; then
    for node in $(echo "$NODES" | tr ',' ' '); do
        node_dir="$TALOS_DIAGNOSTICS_DIR/node-$node"
        mkdir -p "$node_dir"
        
        # Kernel logs
        run_talosctl "talosctl dmesg --nodes $node" \
            "$node_dir/dmesg.txt" \
            "Kernel logs for node $node"
        
        # Running processes
        run_talosctl "talosctl processes --nodes $node" \
            "$node_dir/processes.txt" \
            "Running processes for node $node"
        
        # Memory usage
        run_talosctl "talosctl memory --nodes $node" \
            "$node_dir/memory.txt" \
            "Memory usage for node $node"
        
        # Network connections
        run_talosctl "talosctl netstat --nodes $node" \
            "$node_dir/netstat.txt" \
            "Network connections for node $node"
        
        # Disk usage (using df instead of usage which might not be available)
        run_talosctl "talosctl df --nodes $node" \
            "$node_dir/disk-usage.txt" \
            "Disk usage for node $node"
        
        # Running containers
        run_talosctl "talosctl containers --nodes $node" \
            "$node_dir/containers.txt" \
            "Running containers for node $node"
        
        # Service status
        run_talosctl "talosctl service --nodes $node" \
            "$node_dir/services.txt" \
            "Service status for node $node"
        
        # Mount information
        run_talosctl "talosctl mounts --nodes $node" \
            "$node_dir/mounts.txt" \
            "Mount information for node $node"
    done
fi

# 5. etcd status (control plane nodes)
run_talosctl "talosctl etcd status $NODE_FLAG" \
    "$TALOS_DIAGNOSTICS_DIR/etcd-status.txt" \
    "etcd cluster status"

# 6. Cluster configuration (try different approaches)
run_talosctl "talosctl get config $NODE_FLAG -o yaml" \
    "$TALOS_DIAGNOSTICS_DIR/talos-config.yaml" \
    "Talos cluster configuration"

# Alternative: try to get machine config
run_talosctl "talosctl get machineconfig $NODE_FLAG -o yaml" \
    "$TALOS_DIAGNOSTICS_DIR/talos-machine-config.yaml" \
    "Talos machine configuration"

# 7. Available resource definitions
run_talosctl "talosctl get rd $NODE_FLAG" \
    "$TALOS_DIAGNOSTICS_DIR/resource-definitions.txt" \
    "Available resource definitions"

# 8. COSI resources (if accessible)
run_talosctl "talosctl get machines $NODE_FLAG -o yaml" \
    "$TALOS_DIAGNOSTICS_DIR/machines.yaml" \
    "Machine resources"

# Alternative: try to get nodes
run_talosctl "talosctl get nodes $NODE_FLAG -o yaml" \
    "$TALOS_DIAGNOSTICS_DIR/nodes.yaml" \
    "Node resources"

# 9. Events (if accessible)
run_talosctl "talosctl events $NODE_FLAG --duration 1h" \
    "$TALOS_DIAGNOSTICS_DIR/talos-events.txt" \
    "Talos events (last hour)"

echo "Talos diagnostics collection completed"
echo "Output directory: $TALOS_DIAGNOSTICS_DIR"
ls -la "$TALOS_DIAGNOSTICS_DIR"

# Create tar.gz archive in the parent directory (same pattern as Windsor state)
TAR_FILE="$(dirname "$TALOS_DIAGNOSTICS_DIR")/talos-diagnostics.tar.gz"
echo "Creating archive: $TAR_FILE"
tar -czf "$TAR_FILE" -C "$(dirname "$TALOS_DIAGNOSTICS_DIR")" "$(basename "$TALOS_DIAGNOSTICS_DIR")"
echo "✓ Talos diagnostics archived to: $TAR_FILE"
