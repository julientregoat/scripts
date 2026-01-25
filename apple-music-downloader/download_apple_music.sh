#!/usr/bin/env bash
# Download lossless audio (ALAC) from Apple Music URLs
# Requires: wrapper (decryption server) running, MP4Box installed
# Docs: See README.md in this directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"
WRAPPER_SCRIPT="$SCRIPT_DIR/wrapper.sh"
CHECK_FORMAT_SCRIPT="$SCRIPT_DIR/check_format.sh"

# Load .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Initialize variables for cleanup tracking
WRAPPER_STARTED_BY_SCRIPT=false
AUTO_WRAPPER=false

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ "$AUTO_WRAPPER" = true ] && [ "$WRAPPER_STARTED_BY_SCRIPT" = true ]; then
        echo ""
        echo "Cleaning up: stopping wrapper..."
        if [ -f "$WRAPPER_SCRIPT" ] && [ -x "$WRAPPER_SCRIPT" ]; then
            "$WRAPPER_SCRIPT" stop 2>/dev/null || true
        fi
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

WRAPPER_HOST="${APPLE_MUSIC_WRAPPER_HOST:-127.0.0.1}"
WRAPPER_PORT="${APPLE_MUSIC_WRAPPER_PORT:-10020}"

# Check for env var override
if [ "${APPLE_MUSIC_AUTO_WRAPPER:-false}" = "true" ]; then
    AUTO_WRAPPER=true
fi

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-wrapper)
            AUTO_WRAPPER=true
            shift
            ;;
        --help|-h)
            cat << EOF
usage: $0 [options] <apple-music-url>

Download lossless ALAC audio from Apple Music URLs.
Supports tracks, albums, playlists, and artists.

Options:
  --auto-wrapper    Automatically start wrapper if not running, and stop it
                    if this script started it (after download completes)
  -h, --help        Show this help message

Examples:
  $0 https://music.apple.com/us/album/album-name/1234567890
  $0 --auto-wrapper https://music.apple.com/us/song/song-name/1234567890

Environment variables:
  APPLE_MUSIC_WRAPPER_HOST  - Wrapper host (default: 127.0.0.1)
  APPLE_MUSIC_WRAPPER_PORT - Wrapper port (default: 10020)
  APPLE_MUSIC_OUTPUT_DIR   - Output directory (default: ~/Downloads)

Note: The wrapper is a long-lived service. For multiple downloads, start it once
with ./wrapper.sh start and leave it running. Use --auto-wrapper for convenience
when doing a single download.
EOF
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "error: Docker must be installed."
    exit 1
fi

# Check MP4Box
if ! command -v MP4Box &> /dev/null && ! command -v mp4box &> /dev/null; then
    echo "error: MP4Box must be installed (required by apple-music-downloader)."
    echo "Install with: brew install gpac (macOS) or sudo apt-get install gpac (Linux)"
    exit 1
fi

# Check if wrapper is accessible
check_wrapper() {
    if command -v timeout &> /dev/null; then
        timeout 1 bash -c "echo > /dev/tcp/$WRAPPER_HOST/$WRAPPER_PORT" 2>/dev/null
    elif command -v nc &> /dev/null; then
        nc -z "$WRAPPER_HOST" "$WRAPPER_PORT" 2>/dev/null
    else
        return 1
    fi
}

WRAPPER_RUNNING=false
if check_wrapper; then
    WRAPPER_RUNNING=true
fi

# Handle wrapper startup
if [ "$WRAPPER_RUNNING" = false ]; then
    if [ "$AUTO_WRAPPER" = true ]; then
        echo "Wrapper not running. Starting wrapper..."
        if [ -f "$WRAPPER_SCRIPT" ] && [ -x "$WRAPPER_SCRIPT" ]; then
            "$WRAPPER_SCRIPT" start
            WRAPPER_STARTED_BY_SCRIPT=true
            # Wait a moment for wrapper to be ready
            sleep 2
            if check_wrapper; then
                echo "✓ Wrapper started and ready"
            else
                echo "⚠️  Wrapper started but not yet accessible. Continuing anyway..."
            fi
        else
            echo "error: wrapper.sh not found or not executable"
            echo "Cannot auto-start wrapper. Please start manually: ./wrapper.sh start"
            exit 1
        fi
        echo ""
    else
        echo "error: Wrapper server not reachable at $WRAPPER_HOST:$WRAPPER_PORT"
        echo ""
        echo "The wrapper (decryption server) must be running before downloading."
        echo "Start it with: ./wrapper.sh start"
        echo "Or use --auto-wrapper flag to start it automatically"
        exit 1
    fi
fi

URL=$1
if [ -z "$URL" ]; then
    echo "usage: $0 [options] <apple-music-url>"
    echo ""
    echo "Download lossless ALAC audio from Apple Music URLs."
    echo "Supports tracks, albums, playlists, and artists."
    echo ""
    echo "Options:"
    echo "  --auto-wrapper    Automatically start wrapper if not running, and stop it"
    echo "                    if this script started it (after download completes)"
    echo "  -h, --help        Show detailed help"
    echo ""
    echo "Examples:"
    echo "  $0 https://music.apple.com/us/album/album-name/1234567890"
    echo "  $0 --auto-wrapper https://music.apple.com/us/song/song-name/1234567890"
    echo ""
    echo "See --help for more information."
    exit 1
fi

# Check if ALAC is available before downloading
check_alac_available() {
    echo "Checking if lossless ALAC format is available..."
    echo ""
    
    # Run debug mode to check formats
    local debug_output
    debug_output=$(docker run --rm --network host \
        "$DOWNLOADER_IMAGE" \
        --debug "$URL" 2>&1) || {
        echo "⚠️  Warning: Could not check available formats. Proceeding anyway..."
        return 0
    }
    
    # Check for ALAC in the output (case insensitive)
    if echo "$debug_output" | grep -qiE "(alac|audio-alac-stereo)"; then
        echo "✓ Lossless ALAC format is available"
        echo ""
        return 0
    else
        echo "✗ Error: Lossless ALAC format is NOT available for this track"
        echo ""
        echo "Available formats shown below:"
        echo "$debug_output" | grep -iE "(format|audio|codec|quality)" || echo "$debug_output"
        echo ""
        echo "This script only downloads lossless ALAC audio."
        echo "If you want to download other formats, use the downloader directly:"
        echo "  docker run --rm --network host -v ~/Downloads:/downloads \\"
        echo "    $DOWNLOADER_IMAGE <url>"
        return 1
    fi
}

# Check ALAC availability
if ! check_alac_available; then
    exit 1
fi

# Determine output directory (expand ~ if present)
OUTPUT_DIR="${APPLE_MUSIC_OUTPUT_DIR:-$HOME/Downloads}"
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
mkdir -p "$OUTPUT_DIR"

echo "Downloading from Apple Music..."
echo "URL: $URL"
echo "Output: $OUTPUT_DIR"
echo ""

# Run downloader in Docker
# --network host: allows access to localhost wrapper
# -v for output directory
# 
# Quality: ALAC (lossless) is the default and highest quality format.
# We've already checked that ALAC is available above, so this will download ALAC.
# The downloader automatically selects ALAC if available, but we error if it's not.
docker run --rm \
    --network host \
    -v "$OUTPUT_DIR:/downloads" \
    "$DOWNLOADER_IMAGE" \
    "$URL"

echo ""
echo "✓ Download complete!"
echo "Files saved to: $OUTPUT_DIR"

# Handle wrapper shutdown if we started it
if [ "$AUTO_WRAPPER" = true ] && [ "$WRAPPER_STARTED_BY_SCRIPT" = true ]; then
    echo ""
    echo "Stopping wrapper (started by this script)..."
    if [ -f "$WRAPPER_SCRIPT" ] && [ -x "$WRAPPER_SCRIPT" ]; then
        "$WRAPPER_SCRIPT" stop
    fi
fi
