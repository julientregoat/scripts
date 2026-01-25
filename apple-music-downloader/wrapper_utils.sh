#!/usr/bin/env bash
# Shared utility functions and configuration for wrapper-related scripts
# Can be sourced: source wrapper_utils.sh

# ============================================================================
# Architecture Detection
# ============================================================================
# Detect system architecture for wrapper binary/image selection
# Sets variables: WRAPPER_ARCH, BINARY_PATTERN, FALLBACK_ARCH, FALLBACK_PATTERN,
#                 WRAPPER_IMAGE_SUFFIX
#
# Note: The wrapper binary is compiled with Android NDK and links against Android
# Apple Music app libraries. This is by design - it's how the decryption works.
#
# Apple Silicon: Must use arm64 binary (x86_64 crashes with QEMU segfaults)
# x86_64: Uses native x86_64 binary

_detect_wrapper_architecture() {
    # Detect architecture
    local ARCH=$(uname -m)

    if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
        # Apple Silicon: Must use arm64 binary
        # x86_64 binary requires QEMU emulation which crashes with segfaults
        WRAPPER_ARCH="arm64"
        BINARY_PATTERN="Wrapper.arm64"
        FALLBACK_ARCH=""
        FALLBACK_PATTERN=""
        WRAPPER_IMAGE_SUFFIX="arm64"
    elif [[ "$ARCH" == "x86_64" ]]; then
        WRAPPER_ARCH="x86_64"
        BINARY_PATTERN="Wrapper.x86_64"
        FALLBACK_ARCH=""
        FALLBACK_PATTERN=""
        WRAPPER_IMAGE_SUFFIX="x86_64"
    else
        echo "error: Unsupported architecture: $ARCH" >&2
        echo "   Supported: x86_64, arm64" >&2
        exit 1
    fi

    # Export variables for use by sourcing scripts
    export WRAPPER_ARCH
    export BINARY_PATTERN
    export FALLBACK_ARCH
    export FALLBACK_PATTERN
    export WRAPPER_IMAGE_SUFFIX
}

# Auto-detect architecture when script is sourced (unless already set)
if [[ -z "${WRAPPER_ARCH:-}" ]]; then
    _detect_wrapper_architecture
fi