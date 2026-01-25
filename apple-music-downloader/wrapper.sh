#!/usr/bin/env bash
# Manage the Apple Music wrapper (decryption server)
# Handles starting, stopping, and status checking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect architecture to determine image name
# Source shared architecture detection script
source "$SCRIPT_DIR/detect_wrapper_architecture.sh"

# Set default image name based on detected architecture
DEFAULT_WRAPPER_IMAGE="apple-music-wrapper-${WRAPPER_IMAGE_SUFFIX}"
WRAPPER_IMAGE="${APPLE_MUSIC_WRAPPER_IMAGE:-$DEFAULT_WRAPPER_IMAGE}"
WRAPPER_CONTAINER="${APPLE_MUSIC_WRAPPER_CONTAINER:-apple-music-wrapper}"
WRAPPER_DATA_DIR="$SCRIPT_DIR/data"

# Load .env if it exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

WRAPPER_HOST="${APPLE_MUSIC_WRAPPER_HOST:-127.0.0.1}"
WRAPPER_PORT="${APPLE_MUSIC_WRAPPER_PORT:-10020}"
WRAPPER_M3U8_PORT="${APPLE_MUSIC_WRAPPER_M3U8_PORT:-20020}"
WRAPPER_ACCOUNT_PORT="${APPLE_MUSIC_WRAPPER_ACCOUNT_PORT:-30020}"

# Build wrapper arguments
WRAPPER_ARGS="-H $WRAPPER_HOST"
if [ -n "$APPLE_MUSIC_USERNAME" ] && [ -n "$APPLE_MUSIC_PASSWORD" ]; then
    WRAPPER_ARGS="$WRAPPER_ARGS -L $APPLE_MUSIC_USERNAME:$APPLE_MUSIC_PASSWORD"
fi

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^${WRAPPER_CONTAINER}$" 2>/dev/null
}

start_wrapper() {
    if is_running; then
        echo "Wrapper is already running (container: $WRAPPER_CONTAINER)"
        return 0
    fi

    # Check if Docker image exists
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${WRAPPER_IMAGE}:latest$"; then
        echo "error: Wrapper Docker image not found: $WRAPPER_IMAGE"
        echo ""
        echo "Run ./setup.sh to build the wrapper Docker image"
        exit 1
    fi

    # Create data directory if it doesn't exist
    mkdir -p "$WRAPPER_DATA_DIR"

    echo "Starting wrapper (Docker container)..."
    echo "Host: $WRAPPER_HOST"
    echo "Ports: $WRAPPER_PORT (decrypt), $WRAPPER_M3U8_PORT (m3u8), $WRAPPER_ACCOUNT_PORT (account)"
    if [ -n "$APPLE_MUSIC_USERNAME" ]; then
        echo "Using login credentials"
    else
        echo "Running without login (credentials not set)"
    fi
    echo ""

    # Use the detected platform from architecture detection
    local docker_platform="$DOCKER_PLATFORM"

    # Build Docker run command
    local docker_args=(
        -d
        --platform "$docker_platform"
        --name "$WRAPPER_CONTAINER"
        --restart unless-stopped
        -v "$WRAPPER_DATA_DIR:/app/rootfs/data"
        -p "$WRAPPER_PORT:$WRAPPER_PORT"
        -p "$WRAPPER_M3U8_PORT:$WRAPPER_M3U8_PORT"
        -p "$WRAPPER_ACCOUNT_PORT:$WRAPPER_ACCOUNT_PORT"
    )

    # Add login credentials if provided
    if [ -n "$APPLE_MUSIC_USERNAME" ] && [ -n "$APPLE_MUSIC_PASSWORD" ]; then
        docker_args+=(-e "args=-L $APPLE_MUSIC_USERNAME:$APPLE_MUSIC_PASSWORD -H 0.0.0.0")
    else
        docker_args+=(-e "args=-H 0.0.0.0")
    fi

    docker_args+=("$WRAPPER_IMAGE")

    # Start container
    if docker run "${docker_args[@]}" 2>&1; then
        # Wait a moment for container to start
        sleep 2
        if is_running; then
            echo "✓ Wrapper started (container: $WRAPPER_CONTAINER)"
            echo "View logs: docker logs $WRAPPER_CONTAINER"
        else
            echo "⚠️  Container started but may have exited. Check logs:"
            echo "   docker logs $WRAPPER_CONTAINER"
        fi
    else
        echo "error: Failed to start wrapper container"
        echo "Check Docker is running and try again"
        exit 1
    fi
}

stop_wrapper() {
    if ! is_running; then
        echo "Wrapper is not running"
        # Clean up stopped container if it exists
        if docker ps -a --format '{{.Names}}' | grep -q "^${WRAPPER_CONTAINER}$"; then
            echo "Removing stopped container..."
            docker rm "$WRAPPER_CONTAINER" > /dev/null 2>&1 || true
        fi
        return 0
    fi

    echo "Stopping wrapper (container: $WRAPPER_CONTAINER)..."
    docker stop "$WRAPPER_CONTAINER" > /dev/null 2>&1 || true
    
    # Wait a moment, then remove container
    sleep 1
    docker rm "$WRAPPER_CONTAINER" > /dev/null 2>&1 || true
    
    echo "✓ Wrapper stopped"
}

status_wrapper() {
    if is_running; then
        echo "Wrapper is running (container: $WRAPPER_CONTAINER)"
        echo "Host: $WRAPPER_HOST"
        echo "Ports: $WRAPPER_PORT (decrypt), $WRAPPER_M3U8_PORT (m3u8), $WRAPPER_ACCOUNT_PORT (account)"
        
        # Show container status
        docker ps --filter "name=$WRAPPER_CONTAINER" --format "Container: {{.Names}} ({{.Status}})"
        
        # Test connectivity
        if command -v timeout &> /dev/null; then
            if timeout 1 bash -c "echo > /dev/tcp/$WRAPPER_HOST/$WRAPPER_PORT" 2>/dev/null; then
                echo "✓ Port $WRAPPER_PORT is accessible"
            else
                echo "⚠️  Port $WRAPPER_PORT is not accessible"
            fi
        fi
    else
        echo "Wrapper is not running"
        # Check if container exists but is stopped
        if docker ps -a --format '{{.Names}}' | grep -q "^${WRAPPER_CONTAINER}$"; then
            echo "Container exists but is stopped. Start with: ./wrapper.sh start"
        fi
        return 1
    fi
}

case "${1:-}" in
    start)
        start_wrapper
        ;;
    stop)
        stop_wrapper
        ;;
    restart)
        stop_wrapper
        sleep 1
        start_wrapper
        ;;
    status)
        status_wrapper
        ;;
    *)
        echo "usage: $0 {start|stop|restart|status}"
        echo ""
        echo "Manage the Apple Music wrapper (decryption server)"
        echo ""
        echo "Commands:"
        echo "  start   - Start the wrapper server"
        echo "  stop    - Stop the wrapper server"
        echo "  restart - Restart the wrapper server"
        echo "  status  - Check if wrapper is running"
        echo ""
        echo "Configuration:"
        echo "  Set APPLE_MUSIC_WRAPPER_IMAGE to specify Docker image (default: apple-music-wrapper)"
        echo "  Set APPLE_MUSIC_WRAPPER_CONTAINER to specify container name (default: apple-music-wrapper)"
        echo "  Use .env file for credentials (see .env.template)"
        exit 1
        ;;
esac
