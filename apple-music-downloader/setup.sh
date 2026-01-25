#!/usr/bin/env bash
# Setup script for Apple Music lossless downloader
# Sets up the wrapper (decryption server) and verifies dependencies

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (includes architecture detection, DOWNLOADER_IMAGE)
source "$SCRIPT_DIR/utils.sh"

# WRAPPER_IMAGE will be set based on architecture (includes platform suffix)
WRAPPER_IMAGE_BASE="apple-music-wrapper"
WRAPPER_REPO_URL="https://github.com/WorldObservationLog/wrapper"
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
# Always use main branch - it has a simple Dockerfile that uses prebuilt binaries
# The arm64 branch's Dockerfile tries to build from source (broken for public use)
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

# Set image name with platform suffix for clarity
WRAPPER_IMAGE="${WRAPPER_IMAGE_BASE}-${SYSTEM_ARCH}"

# Show architecture information
echo "System architecture: $SYSTEM_ARCH"
echo "Wrapper image: $WRAPPER_IMAGE"

# Get latest release download URL
# Fetch release info and find binary URL

# Set release URL based on architecture
# For arm64, check the arch-specific release tag (arm64 binaries are in separate releases)
# For x86_64, check main releases
if [[ "$SYSTEM_ARCH" == "arm64" ]]; then
    WRAPPER_RELEASE_URL="https://api.github.com/repos/WorldObservationLog/wrapper/releases/tags/Wrapper.${SYSTEM_ARCH}.latest"
elif [[ "$SYSTEM_ARCH" == "x86_64" ]]; then
    WRAPPER_RELEASE_URL="https://api.github.com/repos/WorldObservationLog/wrapper/releases/latest"
fi

# Fetch release info and extract binary URL
if ! command -v curl &> /dev/null; then
    echo "error: curl required to download binary."
    echo "   Install curl: brew install curl (macOS) or sudo apt-get install curl (Linux)"
    exit 1
fi

WRAPPER_BINARY_PATTERN="Wrapper.${SYSTEM_ARCH}"
WRAPPER_RELEASE_INFO=$(curl -s "$WRAPPER_RELEASE_URL" 2>/dev/null || echo "")
WRAPPER_BINARY_URL=$(echo "$WRAPPER_RELEASE_INFO" | \
    grep -o "\"browser_download_url\": \"[^\"]*${WRAPPER_BINARY_PATTERN}[^\"]*\.zip[^\"]*\"" | \
    head -1 | \
    cut -d '"' -f 4) || true

if [ -z "$WRAPPER_BINARY_URL" ]; then
    echo "error: Could not find download URL for $SYSTEM_ARCH binary"
    echo "   Check releases manually: https://github.com/WorldObservationLog/wrapper/releases"
    exit 1
fi

# Clean up any old binary files and zip files
echo "Cleaning up old files..."
find "$WRAPPER_REPO_DIR" -maxdepth 1 -type f \( -name "Wrapper.*" -o -name "wrapper.*" -o -name "*.zip" \) ! -name "wrapper" -exec rm -f {} \; 2>/dev/null || true

# Download binary/zip
echo "Downloading latest binary for $SYSTEM_ARCH..."
WRAPPER_ZIP_PATH="$WRAPPER_REPO_DIR/wrapper.zip"
WRAPPER_BINARY_PATH="$WRAPPER_REPO_DIR/wrapper"

if curl -L -o "$WRAPPER_ZIP_PATH" "$WRAPPER_BINARY_URL"; then
    echo "Extracting binary from zip..."
    cd "$WRAPPER_REPO_DIR"
    unzip -q -o "$WRAPPER_ZIP_PATH" 2>/dev/null || {
        echo "error: Failed to extract zip file"
        exit 1
    }
    rm -f "$WRAPPER_ZIP_PATH"
    
    # Find the extracted binary (try both uppercase Wrapper.* and lowercase wrapper)
    WRAPPER_EXTRACTED_BINARY=$(find "$WRAPPER_REPO_DIR" -maxdepth 1 -type f \( -name "Wrapper.*" -o -name "wrapper" \) ! -name "*.zip" | head -1)
    if [ -n "$WRAPPER_EXTRACTED_BINARY" ] && [ -f "$WRAPPER_EXTRACTED_BINARY" ]; then
        if [ "$WRAPPER_EXTRACTED_BINARY" != "$WRAPPER_BINARY_PATH" ]; then
            mv "$WRAPPER_EXTRACTED_BINARY" "$WRAPPER_BINARY_PATH"
        fi
        chmod +x "$WRAPPER_BINARY_PATH"
        echo "✓ Binary extracted and ready"
        
        # Restore only the Dockerfile from main branch
        # Release zips include their branch's Dockerfile (complex build-from-source)
        # but we need the main branch's simple Dockerfile that uses prebuilt binaries
        # NOTE: We keep the rootfs/ from the release because the arm64 binary needs
        # arm64 shared libraries (.so files) - using x86_64 libs causes "corrupted shared library" errors
        git checkout -- Dockerfile 2>/dev/null || true
    else
        echo "error: Could not find binary in extracted zip"
        exit 1
    fi
else
    echo "error: Failed to download binary"
    exit 1
fi

# Clean up old wrapper images (any platform) before building new one
# Remove images that match the base name but not the current platform-specific name
echo "Cleaning up old wrapper images..."
docker images --format '{{.Repository}}:{{.Tag}}' | grep "^${WRAPPER_IMAGE_BASE}" | grep -v "^${WRAPPER_IMAGE}:latest$" | while read old_image; do
    if [ -n "$old_image" ]; then
        echo "  Removing old image: $old_image"
        docker rmi "$old_image" 2>/dev/null || true
    fi
done

# Build Docker image using the repo's Dockerfile
echo "Building wrapper Docker image..."
cd "$WRAPPER_REPO_DIR"
if docker build -t "$WRAPPER_IMAGE" .; then
    echo "✓ Wrapper Docker image ready: $WRAPPER_IMAGE:latest"
else
    echo "error: Failed to build wrapper Docker image"
    exit 1
fi

# Pull downloader image
# Note: The downloader image only has x86_64 builds, so on arm64 we need to use --platform
echo "Pulling downloader image..."
if [[ "$SYSTEM_ARCH" == "arm64" ]]; then
    DOWNLOADER_PLATFORM_FLAG="--platform linux/amd64"
    echo "System: arm64 (Apple Silicon) | Downloader: x86_64 (no arm64 build available - using Rosetta 2)"
else
    DOWNLOADER_PLATFORM_FLAG=""
    echo "System: x86_64 | Downloader: x86_64"
fi

if docker pull $DOWNLOADER_PLATFORM_FLAG "$DOWNLOADER_IMAGE" 2>/dev/null; then
    echo "✓ Downloader image ready: $DOWNLOADER_IMAGE"
else
    echo "⚠️  Could not pull downloader image: $DOWNLOADER_IMAGE"
    echo ""
    echo "The downloader image will be pulled automatically when you run the download script."
    echo "This is not a critical error - setup can continue."
    echo ""
fi

echo ""
echo "Setup complete!"
echo ""

echo "Next steps:"
echo "1. Configure credentials: cp .env.template .env && edit .env"
echo "   (REQUIRED - wrapper requires credentials to function)"
echo "2. Start wrapper: ./wrapper.sh start"
echo "   (First time will require 2FA - see README for instructions)"
echo "3. Download music: ./download_apple_music.sh <apple-music-url>"
echo ""
echo "See README.md for detailed usage instructions"
