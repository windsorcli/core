#!/bin/bash

# Script to collect talosctl diagnostics for support bundle
# This script will be run as part of the support bundle collection process

set -euo pipefail

# Handle script interruption gracefully
trap 'echo "Script interrupted, cleaning up..."; exit 130' INT TERM

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

# Function to run commands with timeout (fallback if timeout command not available)
run_with_timeout() {
    local timeout_seconds="$1"
    local cmd="$2"
    local output_file="$3"
    local description="$4"
    
    echo "Collecting: $description"
    echo "Command: $cmd"
    
    # Try to use timeout command if available
    if command -v timeout >/dev/null 2>&1; then
        if timeout "$timeout_seconds" bash -c "$cmd" > "$output_file" 2>&1; then
            echo "✓ Successfully collected: $description"
        else
            local exit_code=$?
            echo "⚠ Failed to collect: $description (exit code: $exit_code)"
            echo "Command failed: $cmd" > "$output_file"
            echo "Exit code: $exit_code" >> "$output_file"
        fi
    else
        # Fallback: run without timeout but with background process and kill
        echo "Warning: timeout command not available, using background process with kill"
        (
            eval "$cmd" > "$output_file" 2>&1 &
            local pid=$!
            sleep "$timeout_seconds"
            if kill -0 "$pid" 2>/dev/null; then
                echo "Command timed out, killing process"
                kill -TERM "$pid" 2>/dev/null
                sleep 2
                kill -KILL "$pid" 2>/dev/null
                echo "Command timed out after ${timeout_seconds}s" >> "$output_file"
                echo "⚠ Failed to collect: $description (timeout)"
            else
                wait "$pid"
                local wait_exit_code=$?
                if [ $wait_exit_code -eq 0 ]; then
                    echo "✓ Successfully collected: $description"
                else
                    echo "⚠ Failed to collect: $description (exit code: $wait_exit_code)"
                fi
            fi
        )
    fi
}

# Check if talosctl is available
if ! command -v talosctl &> /dev/null; then
    echo "talosctl not found, skipping talos diagnostics"
    exit 0
fi

# Determine node targeting strategy based on environment
NODE_ARGS=()
NODES=""

# Check if we're in a local Docker Desktop environment (has controlplane-1 node)
if talosctl get nodes 2>/dev/null | grep -q "controlplane-1"; then
    echo "Detected local Docker Desktop environment, using node names"
    NODE_ARGS=(-n controlplane-1)
    NODES="controlplane-1"
# Check if we have specific node IPs from kubectl (CI environment)
elif kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | grep -q .; then
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | tr ' ' ',')
    NODE_ARGS=(-n "$NODES")
    echo "Detected CI environment, using node IPs: $NODES"
# Fallback: try to get from talosctl config
elif talosctl config info 2>/dev/null | grep -q "endpoints:"; then
    NODES=$(talosctl config info 2>/dev/null | grep "endpoints:" | cut -d: -f2 | tr -d ' ' | tr ',' ' ')
    NODE_ARGS=(-n "$NODES")
    echo "Using endpoints from talosctl config: $NODES"
else
    echo "No nodes detected, will attempt commands without node targeting"
fi

echo "Collecting Talos diagnostics to: $TALOS_DIAGNOSTICS_DIR"
echo "Target nodes: ${NODES:-'auto-detect'}"

# Debug: Show talosctl version and available commands
echo "Talosctl version:"
talosctl version --client 2>/dev/null || echo "Failed to get version"
echo "Available talosctl commands:"
talosctl --help 2>/dev/null | grep -A 100 "Available Commands:" | head -20 || echo "Failed to get help"

# Test connectivity to nodes before proceeding
if [ -n "$NODES" ]; then
    echo "Testing connectivity to nodes..."
    for node in $(echo "$NODES" | tr ',' ' '); do
        echo "Testing node: $node"
        if timeout 10s talosctl version --nodes "$node" >/dev/null 2>&1; then
            echo "✓ Node $node is reachable"
        else
            echo "⚠ Node $node is not reachable or not responding"
        fi
    done
fi

# 1. Comprehensive support bundle (most important)
# This creates a complete tar.gz file with all diagnostics
echo "Collecting comprehensive Talos support bundle..."

# Change to the diagnostics directory to avoid conflicts with existing support.zip
cd "$TALOS_DIAGNOSTICS_DIR"

if [ ${#NODE_ARGS[@]} -gt 0 ]; then
    echo "Using node targeting: ${NODE_ARGS[*]}"
    echo "Running: talosctl support ${NODE_ARGS[*]} --output talos-support-bundle.tar.gz"
    if talosctl support "${NODE_ARGS[@]}" --output talos-support-bundle.tar.gz; then
        echo "✓ Successfully created talos-support-bundle.tar.gz"
    else
        exit_code=$?
        echo "⚠ Support bundle creation failed (exit code: $exit_code)"
        echo "Command failed: talosctl support ${NODE_ARGS[*]} --output talos-support-bundle.tar.gz" > support-bundle-output.txt
        echo "Exit code: $exit_code" >> support-bundle-output.txt
    fi
else
    echo "No node targeting available, attempting support bundle without targeting"
    echo "Running: talosctl support --output talos-support-bundle.tar.gz"
    if talosctl support --output talos-support-bundle.tar.gz; then
        echo "✓ Successfully created talos-support-bundle.tar.gz"
    else
        exit_code=$?
        echo "⚠ Support bundle creation failed (exit code: $exit_code)"
        echo "Command failed: talosctl support --output talos-support-bundle.tar.gz" > support-bundle-output.txt
        echo "Exit code: $exit_code" >> support-bundle-output.txt
    fi
fi

# Change back to original directory
cd - > /dev/null

# 2. Basic version info (always works)
if [ ${#NODE_ARGS[@]} -gt 0 ]; then
    run_talosctl "talosctl version ${NODE_ARGS[*]}" \
        "$TALOS_DIAGNOSTICS_DIR/talos-version.txt" \
        "Talos version information"
else
    run_talosctl "talosctl version" \
        "$TALOS_DIAGNOSTICS_DIR/talos-version.txt" \
        "Talos version information"
fi

echo "Talos diagnostics collection completed"
echo "Output directory: $TALOS_DIAGNOSTICS_DIR"
ls -la "$TALOS_DIAGNOSTICS_DIR"

# Create tar.gz archive in the parent directory (same pattern as Windsor state)
TAR_FILE="$(dirname "$TALOS_DIAGNOSTICS_DIR")/talos-diagnostics.tar.gz"
echo "Creating archive: $TAR_FILE"

# Include the talos support bundle if it was created
if [ -f "$TALOS_DIAGNOSTICS_DIR/talos-support-bundle.tar.gz" ]; then
    echo "Including talos support bundle in archive"
    cp "$TALOS_DIAGNOSTICS_DIR/talos-support-bundle.tar.gz" "$(dirname "$TALOS_DIAGNOSTICS_DIR")/"
    # Create archive with both the diagnostics directory and the support bundle
    tar -czf "$TAR_FILE" -C "$(dirname "$TALOS_DIAGNOSTICS_DIR")" "$(basename "$TALOS_DIAGNOSTICS_DIR")" "talos-support-bundle.tar.gz"
else
    # Create archive with just the diagnostics directory
    tar -czf "$TAR_FILE" -C "$(dirname "$TALOS_DIAGNOSTICS_DIR")" "$(basename "$TALOS_DIAGNOSTICS_DIR")"
fi

echo "✓ Talos diagnostics archived to: $TAR_FILE"
