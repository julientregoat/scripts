#!/usr/bin/env bash
# Check available audio formats for an Apple Music URL
# Shows what formats (ALAC, Dolby Atmos, AAC, etc.) are available without downloading

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"

# Load .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

WRAPPER_HOST="${APPLE_MUSIC_WRAPPER_HOST:-127.0.0.1}"
WRAPPER_PORT="${APPLE_MUSIC_WRAPPER_PORT:-10020}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "error: Docker must be installed."
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

if ! check_wrapper; then
    echo "error: Wrapper server not reachable at $WRAPPER_HOST:$WRAPPER_PORT"
    echo "Start it with: ./wrapper.sh start"
    exit 1
fi

URL=$1
if [ -z "$URL" ]; then
    echo "usage: $0 <apple-music-url>"
    echo ""
    echo "Check available audio formats for an Apple Music URL."
    echo "Shows what formats (ALAC, Dolby Atmos, AAC, etc.) are available."
    echo ""
    echo "Example:"
    echo "  $0 https://music.apple.com/us/album/album-name/1234567890"
    echo ""
    echo "Look for 'alac' or 'audio-alac-stereo' in the output to confirm"
    echo "lossless format is available."
    exit 1
fi

echo "Checking available formats for: $URL"
echo ""
echo "Looking for 'alac' or 'audio-alac-stereo' in the output below..."
echo "If not found, lossless ALAC is not available for this track."
echo ""

# Run downloader in debug mode
docker run --rm \
    --network host \
    "$DOWNLOADER_IMAGE" \
    --debug "$URL"
