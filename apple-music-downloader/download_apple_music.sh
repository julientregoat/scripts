#!/usr/bin/env bash
# Download lossless audio (ALAC) from Apple Music URLs
# Requires: wrapper (decryption server) running, MP4Box installed
# Docs: See README.md in this directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADER_IMAGE="ghcr.io/zhaarey/apple-music-downloader"
DOWNLOADER_CONTAINER="${APPLE_MUSIC_DOWNLOADER_CONTAINER:-apple-music-downloader}"
WRAPPER_SCRIPT="$SCRIPT_DIR/wrapper.sh"
CHECK_FORMAT_SCRIPT="$SCRIPT_DIR/check_format.sh"

# Load .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Source shared wrapper utilities (architecture detection)
source "$SCRIPT_DIR/wrapper_utils.sh"

# Initialize variables for cleanup tracking
WRAPPER_STARTED_BY_SCRIPT=false
AUTO_WRAPPER=false
OUTPUT_DIR=""
ALAC_MAX=""

# Reorganize downloaded files function (defined early so cleanup can use it)
# This function is idempotent - safe to call multiple times
reorganize_files() {
    # Use OUTPUT_DIR if set, otherwise default to ~/Downloads
    local alac_dir="${OUTPUT_DIR:-$HOME/Downloads}/ALAC"
    local target_dir="${OUTPUT_DIR:-$HOME/Downloads}/Apple Music Downloads"
    
    if [ ! -d "$alac_dir" ]; then
        return 0
    fi
    
    echo "Reorganizing files..."
    mkdir -p "$target_dir"
    
    # Process each artist directory
    for artist_dir in "$alac_dir"/*; do
        if [ ! -d "$artist_dir" ]; then
            continue
        fi
        
        local artist_name=$(basename "$artist_dir")
        
        # Process each release in the artist directory
        for release_dir in "$artist_dir"/*; do
            if [ ! -d "$release_dir" ]; then
                continue
            fi
            
            local release_name=$(basename "$release_dir")
            local new_dir_name="${artist_name} - ${release_name}"
            local new_dir_path="$target_dir/$new_dir_name"
            
            # Move the release directory to the new location
            if [ -d "$new_dir_path" ]; then
                # If target already exists, merge contents
                echo "  Merging into existing: $new_dir_name"
                cp -r "$release_dir"/* "$new_dir_path/" 2>/dev/null || true
                rm -rf "$release_dir"
            else
                echo "  Moving: $new_dir_name"
                mv "$release_dir" "$new_dir_path" 2>/dev/null || {
                    echo "  ⚠️  Could not move $new_dir_name (may be in use)"
                }
            fi
        done
        
        # Remove artist directory if empty
        if [ -d "$artist_dir" ] && [ -z "$(ls -A "$artist_dir")" ]; then
            rmdir "$artist_dir" 2>/dev/null || true
        fi
    done
    
    # Remove ALAC directory if empty
    if [ -d "$alac_dir" ] && [ -z "$(ls -A "$alac_dir")" ]; then
        rmdir "$alac_dir" 2>/dev/null || true
    fi
    
    echo "✓ Files reorganized to: $target_dir"
}

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    
    # Always try to reorganize files, even on error/timeout
    if [ -n "$OUTPUT_DIR" ]; then
        reorganize_files 2>/dev/null || true
    fi
    
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
        --output-dir)
            if [ -z "$2" ]; then
                echo "error: --output-dir requires a directory path"
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --max-sample-rate)
            if [ -z "$2" ]; then
                echo "error: --max-sample-rate requires a sample rate value (e.g., 44100, 48000, 96000, 192000)"
                exit 1
            fi
            ALAC_MAX="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
usage: $0 [options] <apple-music-url> [url2] [url3] ...

Download lossless ALAC audio from Apple Music URLs.
Supports tracks, albums, playlists, and artists.
Can download multiple URLs in a single run (more efficient).

Options:
  --auto-wrapper    Automatically start wrapper if not running, and stop it
                    if this script started it (after download completes)
  --output-dir DIR  Output directory for downloads (default: ~/Downloads)
  --max-sample-rate RATE   Maximum sample rate in Hz (default: auto-detect based on bit depth)
                            44100 for 16-bit, 48000 for 24-bit
                            Override: 44100, 48000, 96000, 192000
  -h, --help        Show this help message

Examples:
  $0 https://music.apple.com/us/album/album-name/1234567890
  $0 --auto-wrapper https://music.apple.com/us/song/song-name/1234567890
  $0 --output-dir ~/Music https://music.apple.com/us/album/album-name/1234567890
  $0 --max-sample-rate 44100 https://music.apple.com/us/album/album-name/1234567890
  $0 https://music.apple.com/us/album/album1/123 https://music.apple.com/us/album/album2/456

Environment variables:
  APPLE_MUSIC_WRAPPER_HOST  - Wrapper host (default: 127.0.0.1)
  APPLE_MUSIC_WRAPPER_PORT - Wrapper port (default: 10020)

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

# Collect all URLs (everything remaining after flags)
URLS=("$@")
if [ ${#URLS[@]} -eq 0 ]; then
    echo "usage: $0 [options] <apple-music-url> [url2] [url3] ..."
    echo ""
    echo "Download lossless ALAC audio from Apple Music URLs."
    echo "Supports tracks, albums, playlists, and artists."
    echo "Can download multiple URLs in a single run (more efficient)."
    echo ""
    echo "Options:"
    echo "  --auto-wrapper    Automatically start wrapper if not running, and stop it"
    echo "                    if this script started it (after download completes)"
    echo "  --output-dir DIR  Output directory for downloads (default: ~/Downloads)"
    echo "  --max-sample-rate RATE   Maximum sample rate in Hz (default: auto-detect)"
    echo "  -h, --help        Show detailed help"
    echo ""
    echo "Examples:"
    echo "  $0 https://music.apple.com/us/album/album-name/1234567890"
    echo "  $0 --auto-wrapper https://music.apple.com/us/song/song-name/1234567890"
    echo "  $0 --output-dir ~/Music https://music.apple.com/us/album/album-name/1234567890"
    echo "  $0 https://music.apple.com/us/album/album1/123 https://music.apple.com/us/album/album2/456"
    echo ""
    echo "See --help for more information."
    exit 1
fi

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

# Source check_format.sh to use its format checking function
source "$CHECK_FORMAT_SCRIPT"

# Check ALAC availability for all URLs
# This will set ALAC_MAX based on detected bit depth
if ! check_alac_formats "${URLS[@]}"; then
    exit 1
fi

# Determine output directory (expand ~ if present)
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$HOME/Downloads"
fi
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
mkdir -p "$OUTPUT_DIR"

# Reorganize any existing ALAC files before starting new download
# This handles cases where a previous download was interrupted
reorganize_files 2>/dev/null || true

echo "Downloading from Apple Music..."

# Show architecture information
ARCH=${ARCH:-$(uname -m)}
if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    echo "System: $ARCH (Apple Silicon) | Downloader: x86_64 (no arm64 build available - using Rosetta 2)"
else
    echo "System: $ARCH | Downloader: x86_64"
fi

if [ ${#URLS[@]} -eq 1 ]; then
    echo "URL: ${URLS[0]}"
else
    echo "URLs: ${#URLS[@]} URLs"
    for url in "${URLS[@]}"; do
        echo "  - $url"
    done
fi
echo "Output: $OUTPUT_DIR"
echo ""

# Warn on Apple Silicon (arm64): local wrapper can crash with albums/multiple tracks
if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    echo "⚠️  Apple Silicon: The local wrapper may crash during decryption when downloading albums or multiple tracks. Single-track (song) downloads often work. See README → Troubleshooting → Decryption fails."
    echo ""
fi

# Run downloader in Docker
# --network host: allows access to localhost wrapper
# -v for output directory
# --alac-max (passed to downloader): limit sample rate based on bit depth (or user override)
# 
# Quality: ALAC (lossless) is the default and highest quality format.
# We've already checked that ALAC is available above, so this will download ALAC.
# The downloader automatically selects ALAC if available, but we error if it's not.
# Pass all URLs at once for efficient batch downloading
docker_args=(
    --rm
    --name "$DOWNLOADER_CONTAINER"
    --platform linux/amd64
    --network host
    -v "$OUTPUT_DIR:/downloads"
)

docker_args+=("$DOWNLOADER_IMAGE")

# Add --alac-max flag to downloader if specified (internal flag name)
if [ -n "$ALAC_MAX" ]; then
    docker_args+=(--alac-max "$ALAC_MAX")
fi

# Add URLs
docker_args+=("${URLS[@]}")

# Check if a download container is already running
if docker ps --format '{{.Names}}' | grep -q "^${DOWNLOADER_CONTAINER}$" 2>/dev/null; then
    echo "⚠️  Warning: A download container is already running: $DOWNLOADER_CONTAINER"
    echo ""
    echo "Please wait for the current download to finish, or stop it with:"
    echo "  docker stop $DOWNLOADER_CONTAINER"
    echo ""
    echo "If you're sure the previous download is stuck, you can stop it and rerun this script."
    exit 1
fi

# Clean up any stopped container with the same name (from --rm, should be rare)
if docker ps -a --format '{{.Names}}' | grep -q "^${DOWNLOADER_CONTAINER}$" 2>/dev/null; then
    docker rm "$DOWNLOADER_CONTAINER" >/dev/null 2>&1 || true
fi

# Run download - this may take a while for large albums
# Note: docker run blocks until completion. For very large downloads, if the script
# is interrupted (e.g., by tool timeouts), the container will continue running.
# When it finishes, it will exit and be automatically removed (--rm flag).
# Files will be in OUTPUT_DIR/ALAC/ and can be reorganized by re-running the script.
echo "Starting download (this may take several minutes for large albums)..."
if ! docker run "${docker_args[@]}"; then
    echo ""
    echo "⚠️  Warning: Download command exited with an error"
    echo "Check if files were partially downloaded in: $OUTPUT_DIR/ALAC"
    echo "You can manually reorganize files or re-run the script"
    # Still try to reorganize any files that were downloaded
    reorganize_files 2>/dev/null || true
    exit 1
fi

echo ""
echo "✓ Download complete!"

# Reorganize downloaded files
reorganize_files

echo "Files saved to: $OUTPUT_DIR/Apple Music Downloads"

# Handle wrapper shutdown if we started it
if [ "$AUTO_WRAPPER" = true ] && [ "$WRAPPER_STARTED_BY_SCRIPT" = true ]; then
    echo ""
    echo "Stopping wrapper (started by this script)..."
    if [ -f "$WRAPPER_SCRIPT" ] && [ -x "$WRAPPER_SCRIPT" ]; then
        "$WRAPPER_SCRIPT" stop
    fi
fi
