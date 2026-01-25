#!/usr/bin/env bash
# Shared utility functions for architecture detection
# Can be sourced: source utils.sh

# ============================================================================
# Architecture Detection
# ============================================================================
# Detect system architecture
# Sets variable: SYSTEM_ARCH
#
# Supported architectures: x86_64, arm64

_detect_system_architecture() {
    # Detect architecture
    local ARCH=$(uname -m)

    if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
        SYSTEM_ARCH="arm64"
    elif [[ "$ARCH" == "x86_64" ]]; then
        SYSTEM_ARCH="x86_64"
    else
        echo "error: Unsupported architecture: $ARCH" >&2
        echo "   Supported: x86_64, arm64" >&2
        exit 1
    fi

    # Export variable for use by sourcing scripts
    export SYSTEM_ARCH
}

# Auto-detect architecture when script is sourced (unless already set)
if [[ -z "${SYSTEM_ARCH:-}" ]]; then
    _detect_system_architecture
fi

# ============================================================================
# Network Utilities
# ============================================================================
# Check if a TCP port is accessible
# Usage: check_port <host> <port>
# Returns 0 if accessible, 1 otherwise
check_port() {
    local host="$1"
    local port="$2"
    
    if command -v timeout &> /dev/null; then
        timeout 1 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
    elif command -v nc &> /dev/null; then
        nc -z "$host" "$port" 2>/dev/null
    else
        return 1
    fi
}

# ============================================================================
# Docker Container Utilities
# ============================================================================
# Check if a Docker container is running
# Usage: container_is_running <container_name>
# Returns 0 if running, 1 otherwise
container_is_running() {
    local container="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# Check if a Docker container exists (running or stopped)
# Usage: container_exists <container_name>
# Returns 0 if exists, 1 otherwise
container_exists() {
    local container="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# Stop and remove a container
# Usage: cleanup_container <container_name>
cleanup_container() {
    local container="$1"
    docker stop "$container" >/dev/null 2>&1 || true
    docker rm "$container" >/dev/null 2>&1 || true
}
