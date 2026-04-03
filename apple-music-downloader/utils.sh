#!/usr/bin/env bash
# Shared utility functions for apple-music-downloader scripts
# Can be sourced: source utils.sh

# Shared Constants
export DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"

# Environment Loading
# load_env <directory> - Load .env file from directory
load_env() {
    local dir="$1"
    if [ -f "$dir/.env" ]; then
        set -a
        source "$dir/.env"
        set +a
    fi
}

# Dependency Checks
require_docker() {
    if ! command -v docker &> /dev/null; then
        echo "error: Docker must be installed."
        exit 1
    fi
}

# Architecture Detection (sets SYSTEM_ARCH: x86_64 or arm64)

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

# Network Utilities
# check_port <host> <port> - Returns 0 if TCP port is accessible
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

# Docker Container Utilities
# container_is_running <name> - Returns 0 if container is running
container_is_running() {
    local container="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# container_exists <name> - Returns 0 if container exists (running or stopped)
container_exists() {
    local container="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${container}$" 2>/dev/null
}

# cleanup_container <name> - Stop and remove container
cleanup_container() {
    local container="$1"
    docker stop "$container" >/dev/null 2>&1 || true
    docker rm "$container" >/dev/null 2>&1 || true
}
