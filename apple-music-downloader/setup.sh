#!/usr/bin/env bash
# Setup script for Apple Music lossless downloader
# Sets up the wrapper (decryption server) and verifies dependencies

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"
WRAPPER_IMAGE="apple-music-wrapper"
WRAPPER_REPO_URL="https://github.com/WorldObservationLog/wrapper"
WRAPPER_RELEASES_URL="https://api.github.com/repos/WorldObservationLog/wrapper/releases/latest"
WRAPPER_REPO_DIR="$SCRIPT_DIR/wrapper-repo"
DATA_DIR="$SCRIPT_DIR/data"

echo "Apple Music Downloader Setup"
echo "============================"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "error: Docker must be installed."
    echo "Install from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

echo "✓ Docker found: $(docker --version)"

# Check and install MP4Box (required by apple-music-downloader)
if ! command -v MP4Box &> /dev/null && ! command -v mp4box &> /dev/null; then
    echo "MP4Box not found. Installing..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            echo "Installing MP4Box via Homebrew..."
            brew install gpac
            echo "✓ MP4Box installed"
        else
            echo "error: Homebrew not found. Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo ""
            echo "Or install MP4Box manually: brew install gpac"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "Installing MP4Box via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y gpac
        elif command -v yum &> /dev/null; then
            sudo yum install -y gpac
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm gpac
        else
            echo "error: Unsupported package manager. Please install gpac manually."
            exit 1
        fi
        echo "✓ MP4Box installed"
    else
        echo "error: Unsupported OS. Please install MP4Box manually."
        echo "  macOS: brew install gpac"
        echo "  Linux: sudo apt-get install gpac (or equivalent)"
        exit 1
    fi
else
    echo "✓ MP4Box found"
fi

# Create data directory for wrapper persistence
mkdir -p "$DATA_DIR"

echo ""
echo "Setting up wrapper (decryption server) with Docker..."
echo ""

# Clone or update wrapper repository
if [ -d "$WRAPPER_REPO_DIR" ]; then
    echo "Updating wrapper repository..."
    cd "$WRAPPER_REPO_DIR"
    git pull || {
        echo "⚠️  Failed to update repository. Continuing with existing code..."
    }
else
    echo "Cloning wrapper repository..."
    if ! command -v git &> /dev/null; then
        echo "error: git not found. Cannot clone wrapper repository."
        echo "   Please install git or clone manually: git clone $WRAPPER_REPO_URL"
        exit 1
    fi
    
    git clone "$WRAPPER_REPO_URL" "$WRAPPER_REPO_DIR" || {
        echo "error: Failed to clone wrapper repository."
        exit 1
    }
    echo "✓ Repository cloned"
fi

cd "$WRAPPER_REPO_DIR"

# Detect architecture and download latest binary
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    WRAPPER_ARCH="arm64"
    BINARY_PATTERN="Wrapper.arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    WRAPPER_ARCH="x86_64"
    BINARY_PATTERN="Wrapper.x86_64"
else
    echo "error: Unsupported architecture: $ARCH"
    echo "   Supported: x86_64, arm64"
    exit 1
fi

echo "Detected architecture: $WRAPPER_ARCH"
echo "Downloading latest prebuilt binary..."

# Get latest release download URL
if ! command -v curl &> /dev/null && ! command -v jq &> /dev/null; then
    echo "error: curl or jq required to download binary."
    echo "   Install curl: brew install curl (macOS) or sudo apt-get install curl (Linux)"
    exit 1
fi

# Fetch release info and find binary URL
BINARY_URL=$(curl -s "$WRAPPER_RELEASES_URL" | \
    grep -o "\"browser_download_url\": \"[^\"]*${BINARY_PATTERN}[^\"]*\"" | \
    head -1 | \
    cut -d '"' -f 4) || true

if [ -z "$BINARY_URL" ]; then
    echo "error: Could not find download URL for $WRAPPER_ARCH binary"
    echo "   Check releases manually: https://github.com/WorldObservationLog/wrapper/releases"
    exit 1
fi

# Clean up any old binary files with different names (e.g., Wrapper.x86_64.*, Wrapper.arm64.*)
echo "Cleaning up old binary files..."
find "$WRAPPER_REPO_DIR" -maxdepth 1 -type f \( -name "Wrapper.*" -o -name "wrapper.*" \) ! -name "wrapper" -exec rm -f {} \; 2>/dev/null || true

# Download latest binary (always downloads to ensure we have latest)
# Docker's build cache will automatically detect if the file changed and only rebuild if necessary
BINARY_PATH="$WRAPPER_REPO_DIR/wrapper"
echo "Downloading latest binary..."
if curl -L -o "$BINARY_PATH" "$BINARY_URL"; then
    chmod +x "$BINARY_PATH"
    echo "✓ Binary downloaded"
else
    echo "error: Failed to download binary"
    exit 1
fi

# Build Docker image
# Docker's build cache will automatically detect if the binary file changed
# and only rebuild if necessary (based on file checksums)
echo "Building wrapper Docker image..."
if docker build -t "$WRAPPER_IMAGE" .; then
    echo "✓ Wrapper Docker image ready: $WRAPPER_IMAGE:latest"
else
    echo "error: Failed to build wrapper Docker image"
    exit 1
fi

# Pull downloader image
echo "Pulling downloader image..."
if docker pull "$DOWNLOADER_IMAGE" 2>/dev/null; then
    echo "✓ Downloader image ready: $DOWNLOADER_IMAGE"
else
    echo "error: Could not pull downloader image: $DOWNLOADER_IMAGE"
    echo ""
    echo "The downloader Docker image may not be available or there may be a network issue."
    echo ""
    echo "Repository: https://github.com/zhaarey/apple-music-downloader"
    echo "Check available images and build instructions:"
    echo "  https://github.com/zhaarey/apple-music-downloader#readme"
    echo ""
    exit 1
fi

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Start wrapper: ./wrapper.sh start"
echo "   Or use --auto-wrapper flag: ./download_apple_music.sh --auto-wrapper <url>"
echo "2. Download music: ./download_apple_music.sh <apple-music-url>"
echo "3. See README.md for detailed usage instructions"
