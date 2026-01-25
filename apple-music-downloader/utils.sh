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
