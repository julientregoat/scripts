#!/usr/bin/env bash
# Manage the Apple Music wrapper (decryption server)
# Handles starting, stopping, and status checking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (includes architecture detection)
source "$SCRIPT_DIR/utils.sh"

# Load .env if it exists
load_env "$SCRIPT_DIR"

# Set default image name based on detected architecture
DEFAULT_WRAPPER_IMAGE="apple-music-wrapper-${SYSTEM_ARCH}"
WRAPPER_IMAGE="${APPLE_MUSIC_WRAPPER_IMAGE:-$DEFAULT_WRAPPER_IMAGE}"
WRAPPER_CONTAINER="${APPLE_MUSIC_WRAPPER_CONTAINER:-apple-music-wrapper}"
LOGIN_CONTAINER="${WRAPPER_CONTAINER}-login"
WRAPPER_DATA_DIR="$SCRIPT_DIR/data"

WRAPPER_HOST="${APPLE_MUSIC_WRAPPER_HOST:-127.0.0.1}"
WRAPPER_PORT="${APPLE_MUSIC_WRAPPER_PORT:-10020}"
WRAPPER_M3U8_PORT="${APPLE_MUSIC_WRAPPER_M3U8_PORT:-20020}"
WRAPPER_ACCOUNT_PORT="${APPLE_MUSIC_WRAPPER_ACCOUNT_PORT:-30020}"

# Build wrapper arguments
WRAPPER_ARGS="-H $WRAPPER_HOST"
if [ -n "$APPLE_MUSIC_USERNAME" ] && [ -n "$APPLE_MUSIC_PASSWORD" ]; then
    WRAPPER_ARGS="$WRAPPER_ARGS -L $APPLE_MUSIC_USERNAME:$APPLE_MUSIC_PASSWORD"
fi

start_wrapper() {
    if container_is_running "$WRAPPER_CONTAINER"; then
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

    # Check for credentials (required - wrapper requires credentials to function)
    if [ -z "$APPLE_MUSIC_USERNAME" ] || [ -z "$APPLE_MUSIC_PASSWORD" ]; then
        echo "error: Apple Music credentials are REQUIRED"
        echo ""
        echo "The wrapper requires login credentials to function."
        echo ""
        echo "To configure:"
        echo "  1. Copy .env.template to .env"
        echo "  2. Set APPLE_MUSIC_USERNAME and APPLE_MUSIC_PASSWORD"
        echo "  3. Run ./wrapper.sh start again"
        echo ""
        echo "First-time setup requires 2FA - see .env.template for instructions"
        exit 1
    fi

    # Create data directory and 2FA file directory
    mkdir -p "$WRAPPER_DATA_DIR"
    mkdir -p "$WRAPPER_DATA_DIR/data/com.apple.android.music/files"

    echo "Starting wrapper (Docker container)..."
    
    # Show architecture information
    if [[ "$SYSTEM_ARCH" == "arm64" ]]; then
        echo "System: arm64 (Apple Silicon) | Wrapper: arm64 (native)"
        echo "Note: Album/multi-track downloads may crash the wrapper; single-track downloads often work. See README → Decryption fails."
    else
        echo "System: x86_64 | Wrapper: $SYSTEM_ARCH"
    fi

    echo "Host: $WRAPPER_HOST"
    echo "Ports: $WRAPPER_PORT (decrypt), $WRAPPER_M3U8_PORT (m3u8), $WRAPPER_ACCOUNT_PORT (account)"
    if [ -n "$APPLE_MUSIC_USERNAME" ]; then
        echo "Using login credentials: $APPLE_MUSIC_USERNAME"
    else
        echo "Running without login credentials"
    fi
    echo ""

    # Check if session is already cached (accounts.sqlitedb exists with content)
    # Per wrapper docs: -L is ONLY for initial login; the long‑running server must use -H only.
    # Using -L on the server container causes re-auth on every Docker restart (e.g. after crash
    # during decryption), so we run a short-lived login container first, then the server.
    local SESSION_FILE="$WRAPPER_DATA_DIR/data/com.apple.android.music/files/accounts.sqlitedb"
    local NEED_LOGIN=false

    if [ ! -f "$SESSION_FILE" ] || [ ! -s "$SESSION_FILE" ]; then
        NEED_LOGIN=true
    fi
    if [ "${FORCE_LOGIN:-}" = "1" ]; then
        NEED_LOGIN=true
        echo "Forcing re-authentication..."
    fi

    # -------- Phase 1: Login (only when no cache or FORCE_LOGIN) --------
    if [ "$NEED_LOGIN" = true ] && [ -n "$APPLE_MUSIC_USERNAME" ] && [ -n "$APPLE_MUSIC_PASSWORD" ]; then
        echo "Session not cached - authenticating first..."
        cleanup_container "$LOGIN_CONTAINER"

        if ! docker run -d \
            --name "$LOGIN_CONTAINER" \
            -v "$WRAPPER_DATA_DIR:/app/rootfs/data" \
            -p "$WRAPPER_PORT:$WRAPPER_PORT" \
            -p "$WRAPPER_M3U8_PORT:$WRAPPER_M3U8_PORT" \
            -p "$WRAPPER_ACCOUNT_PORT:$WRAPPER_ACCOUNT_PORT" \
            -e "args=-L $APPLE_MUSIC_USERNAME:$APPLE_MUSIC_PASSWORD -F -H 0.0.0.0" \
            "$WRAPPER_IMAGE" 2>/dev/null; then
            echo "error: Failed to start login container"
            exit 1
        fi

        sleep 3
        local TWO_FA_FILE="$WRAPPER_DATA_DIR/data/com.apple.android.music/files/2fa.txt"

        if docker logs "$LOGIN_CONTAINER" 2>&1 | grep -q "Waiting for input"; then
            echo "⚠️  2FA Required"
            echo ""
            echo "The wrapper is waiting for your 2FA code (60 second timeout)."
            echo ""
            read -p "Enter your 2FA code: " TWO_FA_CODE

            if [ -n "$TWO_FA_CODE" ]; then
                echo -n "$TWO_FA_CODE" > "$TWO_FA_FILE"
                echo "✓ 2FA code submitted"
                echo "Waiting for authentication..."
                sleep 5
            else
                cleanup_container "$LOGIN_CONTAINER"
                echo "No code entered. Login aborted."
                exit 1
            fi
        fi

        # Wait for "listening" (auth success) or timeout
        local i=0
        while [ $i -lt 15 ]; do
            if docker logs "$LOGIN_CONTAINER" 2>&1 | grep -q "listening.*10020"; then
                echo "✓ Authentication successful"
                break
            fi
            if ! container_is_running "$LOGIN_CONTAINER"; then
                break
            fi
            sleep 1
            i=$((i + 1))
        done

        cleanup_container "$LOGIN_CONTAINER"

        if [ ! -f "$SESSION_FILE" ] || [ ! -s "$SESSION_FILE" ]; then
            echo "error: Authentication failed or session not cached. Check logs and try again."
            exit 1
        fi
        echo "Session cached. Starting server..."
        echo ""
    elif [ "$NEED_LOGIN" = true ]; then
        echo "error: No credentials and no cached session. Configure .env and run again."
        exit 1
    else
        echo "Using cached session (no re-authentication needed)"
    fi

    # -------- Phase 2: Server (always -H only; restarts use cached session) --------
    cleanup_container "$WRAPPER_CONTAINER"

    if ! docker run -d \
        --name "$WRAPPER_CONTAINER" \
        --restart unless-stopped \
        -v "$WRAPPER_DATA_DIR:/app/rootfs/data" \
        -p "$WRAPPER_PORT:$WRAPPER_PORT" \
        -p "$WRAPPER_M3U8_PORT:$WRAPPER_M3U8_PORT" \
        -p "$WRAPPER_ACCOUNT_PORT:$WRAPPER_ACCOUNT_PORT" \
        -e "args=-H 0.0.0.0" \
        "$WRAPPER_IMAGE" 2>/dev/null; then
        echo "error: Failed to start wrapper container"
        exit 1
    fi

    sleep 2
    if container_is_running "$WRAPPER_CONTAINER"; then
        echo "✓ Wrapper started (container: $WRAPPER_CONTAINER)"
        echo "View logs: docker logs $WRAPPER_CONTAINER"
    else
        echo "⚠️  Container started but is not running. Check logs:"
        docker logs "$WRAPPER_CONTAINER" 2>&1 | tail -15
        return 1
    fi
}

stop_wrapper() {
    if ! container_is_running "$WRAPPER_CONTAINER"; then
        echo "Wrapper is not running"
        # Clean up stopped containers if they exist
        for c in "$WRAPPER_CONTAINER" "$LOGIN_CONTAINER"; do
            if container_exists "$c"; then
                echo "Removing stopped container: $c"
                docker rm "$c" > /dev/null 2>&1 || true
            fi
        done
        return 0
    fi

    echo "Stopping wrapper (container: $WRAPPER_CONTAINER)..."
    cleanup_container "$WRAPPER_CONTAINER"
    cleanup_container "$LOGIN_CONTAINER"

    echo "✓ Wrapper stopped"
}

status_wrapper() {
    if container_is_running "$WRAPPER_CONTAINER"; then
        echo "Wrapper is running (container: $WRAPPER_CONTAINER)"
        echo "Host: $WRAPPER_HOST"
        echo "Ports: $WRAPPER_PORT (decrypt), $WRAPPER_M3U8_PORT (m3u8), $WRAPPER_ACCOUNT_PORT (account)"
        
        # Show container status
        docker ps --filter "name=$WRAPPER_CONTAINER" --format "Container: {{.Names}} ({{.Status}})"
        
        # Test connectivity
        if check_port "$WRAPPER_HOST" "$WRAPPER_PORT"; then
            echo "✓ Port $WRAPPER_PORT is accessible"
        else
            echo "⚠️  Port $WRAPPER_PORT is not accessible"
        fi
    else
        echo "Wrapper is not running"
        # Check if container exists but is stopped
        if container_exists "$WRAPPER_CONTAINER"; then
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
    login)
        # Force re-authentication (useful if session expired or credentials changed)
        stop_wrapper
        sleep 1
        FORCE_LOGIN=1 start_wrapper
        ;;
    status)
        status_wrapper
        ;;
    *)
        echo "usage: $0 {start|stop|restart|login|status}"
        echo ""
        echo "Manage the Apple Music wrapper (decryption server)"
        echo ""
        echo "Commands:"
        echo "  start   - Start the wrapper server (uses cached session if available)"
        echo "  stop    - Stop the wrapper server"
        echo "  restart - Restart the wrapper server"
        echo "  login   - Force re-authentication (if session expired or credentials changed)"
        echo "  status  - Check if wrapper is running"
        echo ""
        echo "Configuration:"
        echo "  Set APPLE_MUSIC_WRAPPER_IMAGE to specify Docker image (default: apple-music-wrapper)"
        echo "  Set APPLE_MUSIC_WRAPPER_CONTAINER to specify container name (default: apple-music-wrapper)"
        echo "  Use .env file for credentials (see .env.template)"
        exit 1
        ;;
esac
