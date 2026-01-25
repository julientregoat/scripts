#!/usr/bin/env bash
# Setup script for Apple Music lossless downloader
# Sets up the wrapper (decryption server) and verifies dependencies

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared wrapper utilities (includes architecture detection)
source "$SCRIPT_DIR/wrapper_utils.sh"

DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"
# WRAPPER_IMAGE will be set based on architecture (includes platform suffix)
WRAPPER_IMAGE_BASE="apple-music-wrapper"
WRAPPER_REPO_URL="https://github.com/WorldObservationLog/wrapper"
WRAPPER_RELEASES_URL="https://api.github.com/repos/WorldObservationLog/wrapper/releases/latest"
WRAPPER_REPO_DIR="$SCRIPT_DIR/wrapper-repo"
DATA_DIR="$SCRIPT_DIR/data"

echo "Apple Music Downloader Setup"
echo "============================"
echo ""

# Note about Apple Silicon requirements
if [[ "$WRAPPER_ARCH" == "arm64" ]]; then
    echo "ℹ️  Apple Silicon detected: Using native arm64 binary"
    echo ""
    echo "   IMPORTANT: Credentials are REQUIRED on Apple Silicon."
    echo "   The wrapper exits immediately without login credentials."
    echo ""
    echo "   After setup, configure credentials in .env before starting the wrapper."
    echo "   First-time login requires 2FA - see README for instructions."
    echo ""
fi

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
WRAPPER_IMAGE="${WRAPPER_IMAGE_BASE}-${WRAPPER_IMAGE_SUFFIX}"

# Show clear architecture information
if [[ "$WRAPPER_ARCH" == "arm64" ]]; then
    echo "System architecture: arm64 (Apple Silicon)"
    echo "Using wrapper: arm64 (native)"
    echo "Wrapper image: $WRAPPER_IMAGE"
else
    echo "System architecture: x86_64"
    echo "Using wrapper: $WRAPPER_ARCH"
    echo "Wrapper image: $WRAPPER_IMAGE"
fi

# Get latest release download URL
if ! command -v curl &> /dev/null; then
    echo "error: curl required to download binary."
    echo "   Install curl: brew install curl (macOS) or sudo apt-get install curl (Linux)"
    exit 1
fi

# Fetch release info and find binary URL
# For arm64, check the arm64.latest release tag first (arm64 binaries are in separate releases)
BINARY_URL=""

if [[ "$WRAPPER_ARCH" == "arm64" ]]; then
    # Check for arm64.latest release tag (arm64 binaries are in separate releases)
    ARM64_RELEASE_INFO=$(curl -s "https://api.github.com/repos/WorldObservationLog/wrapper/releases/tags/Wrapper.arm64.latest" 2>/dev/null || echo "")
    if [ -n "$ARM64_RELEASE_INFO" ]; then
        BINARY_URL=$(echo "$ARM64_RELEASE_INFO" | \
            grep -o "\"browser_download_url\": \"[^\"]*${BINARY_PATTERN}[^\"]*\.zip[^\"]*\"" | \
            head -1 | \
            cut -d '"' -f 4) || true
    fi
fi

# If arm64-specific check didn't work, or we're on x86_64, check main releases
if [ -z "$BINARY_URL" ]; then
    RELEASE_INFO=$(curl -s "$WRAPPER_RELEASES_URL")
    # Try to find zip file for preferred architecture
    BINARY_URL=$(echo "$RELEASE_INFO" | \
        grep -o "\"browser_download_url\": \"[^\"]*${BINARY_PATTERN}[^\"]*\.zip[^\"]*\"" | \
        head -1 | \
        cut -d '"' -f 4) || true
fi

# If not found and we have a fallback, try fallback architecture
if [ -z "$BINARY_URL" ] && [ -n "$FALLBACK_PATTERN" ]; then
    echo "⚠️  $WRAPPER_ARCH binary not available, falling back to $FALLBACK_ARCH (Docker will use Rosetta 2)"
    RELEASE_INFO=$(curl -s "$WRAPPER_RELEASES_URL")
    BINARY_URL=$(echo "$RELEASE_INFO" | \
        grep -o "\"browser_download_url\": \"[^\"]*${FALLBACK_PATTERN}[^\"]*\.zip[^\"]*\"" | \
        head -1 | \
        cut -d '"' -f 4) || true
    if [ -n "$BINARY_URL" ]; then
        WRAPPER_ARCH="$FALLBACK_ARCH"
        BINARY_PATTERN="$FALLBACK_PATTERN"
    fi
fi

# If still not found, try without .zip extension (direct binary)
if [ -z "$BINARY_URL" ]; then
    BINARY_URL=$(echo "$RELEASE_INFO" | \
        grep -o "\"browser_download_url\": \"[^\"]*${BINARY_PATTERN}[^\"]*\"" | \
        grep -v "\.zip" | \
        head -1 | \
        cut -d '"' -f 4) || true
fi

if [ -z "$BINARY_URL" ]; then
    echo "error: Could not find download URL for $WRAPPER_ARCH binary"
    echo "   Check releases manually: https://github.com/WorldObservationLog/wrapper/releases"
    exit 1
fi

# Clean up any old binary files and zip files
echo "Cleaning up old files..."
find "$WRAPPER_REPO_DIR" -maxdepth 1 -type f \( -name "Wrapper.*" -o -name "wrapper.*" -o -name "*.zip" \) ! -name "wrapper" -exec rm -f {} \; 2>/dev/null || true

# Download binary/zip
echo "Downloading latest binary for $WRAPPER_ARCH..."
ZIP_PATH="$WRAPPER_REPO_DIR/wrapper.zip"
BINARY_PATH="$WRAPPER_REPO_DIR/wrapper"

if curl -L -o "$ZIP_PATH" "$BINARY_URL"; then
    # Check if it's a zip file
    if file "$ZIP_PATH" | grep -q "Zip archive"; then
        echo "Extracting binary from zip..."
        cd "$WRAPPER_REPO_DIR"
        unzip -q -o "$ZIP_PATH" 2>/dev/null || {
            echo "error: Failed to extract zip file"
            exit 1
        }
        rm -f "$ZIP_PATH"
        
        # Find the extracted binary (try both uppercase Wrapper.* and lowercase wrapper)
        EXTRACTED_BINARY=$(find "$WRAPPER_REPO_DIR" -maxdepth 1 -type f \( -name "Wrapper.*" -o -name "wrapper" \) ! -name "*.zip" | head -1)
        if [ -n "$EXTRACTED_BINARY" ] && [ -f "$EXTRACTED_BINARY" ]; then
            if [ "$EXTRACTED_BINARY" != "$BINARY_PATH" ]; then
                mv "$EXTRACTED_BINARY" "$BINARY_PATH"
            fi
            chmod +x "$BINARY_PATH"
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
        # Not a zip, treat as direct binary
        mv "$ZIP_PATH" "$BINARY_PATH"
        chmod +x "$BINARY_PATH"
        echo "✓ Binary downloaded"
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
if [[ "$WRAPPER_ARCH" == "arm64" ]]; then
    # On Apple Silicon, pull with platform flag (image will use Rosetta 2)
    echo "System: arm64 (Apple Silicon) | Downloader: x86_64 (no arm64 build available - using Rosetta 2)"
    if docker pull --platform linux/amd64 "$DOWNLOADER_IMAGE" 2>/dev/null; then
        echo "✓ Downloader image ready: $DOWNLOADER_IMAGE"
    else
        echo "⚠️  Could not pull downloader image: $DOWNLOADER_IMAGE"
        echo ""
        echo "The downloader image will be pulled automatically when you run the download script."
        echo "This is not a critical error - setup can continue."
        echo ""
    fi
else
    # On x86_64, try normal pull
    echo "System: x86_64 | Downloader: x86_64"
    if docker pull "$DOWNLOADER_IMAGE" 2>/dev/null; then
        echo "✓ Downloader image ready: $DOWNLOADER_IMAGE"
    else
        echo "⚠️  Could not pull downloader image: $DOWNLOADER_IMAGE"
        echo ""
        echo "The downloader image will be pulled automatically when you run the download script."
        echo "This is not a critical error - setup can continue."
        echo ""
    fi
fi

echo ""
echo "Setup complete!"
echo ""

if [[ "$WRAPPER_ARCH" == "arm64" ]]; then
    echo "Next steps (Apple Silicon):"
    echo "1. Configure credentials: cp .env.template .env && edit .env"
    echo "   (REQUIRED - wrapper exits without credentials on Apple Silicon)"
    echo "2. Start wrapper: ./wrapper.sh start"
    echo "   (First time will require 2FA - see README for instructions)"
    echo "3. Download music: ./download_apple_music.sh <apple-music-url>"
else
    echo "Next steps:"
    echo "1. (Optional) Configure credentials: cp .env.template .env"
    echo "2. Start wrapper: ./wrapper.sh start"
    echo "3. Download music: ./download_apple_music.sh <apple-music-url>"
fi
echo ""
echo "See README.md for detailed usage instructions"
