#!/usr/bin/env bash
# Detect system architecture for wrapper binary/image selection
# This script sets variables used by setup.sh and wrapper.sh
# Can be sourced: source detect_wrapper_architecture.sh

# Detect architecture
ARCH=$(uname -m)

if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    WRAPPER_ARCH="arm64"
    BINARY_PATTERN="Wrapper.arm64"
    FALLBACK_ARCH="x86_64"
    FALLBACK_PATTERN="Wrapper.x86_64"
    DOCKER_PLATFORM="linux/arm64"
    WRAPPER_IMAGE_SUFFIX="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    WRAPPER_ARCH="x86_64"
    BINARY_PATTERN="Wrapper.x86_64"
    FALLBACK_ARCH=""
    FALLBACK_PATTERN=""
    DOCKER_PLATFORM="linux/amd64"
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
export DOCKER_PLATFORM
export WRAPPER_IMAGE_SUFFIX
