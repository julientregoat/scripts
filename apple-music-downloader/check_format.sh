#!/usr/bin/env bash
# Check available audio formats for Apple Music URLs
# Can be used as a standalone script or sourced for its functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (provides DOWNLOADER_IMAGE, load_env, require_docker)
source "$SCRIPT_DIR/utils.sh"

# Load .env if it exists
load_env "$SCRIPT_DIR"

# Note: Format checking with --debug doesn't require the wrapper (only queries metadata)

# Check ALAC availability and validate formats
# Usage: check_alac_formats <url1> [url2] [url3] ...
# Sets global variables: ALAC_MAX, detected_bit_depth, detected_sample_rate
# Returns 0 if all formats meet requirements, 1 otherwise
check_alac_formats() {
    local urls=("$@")
    local url_count=${#urls[@]}
    
    if [ $url_count -eq 0 ]; then
        echo "error: No URLs provided to check_alac_formats"
        return 1
    fi
    
    if [ $url_count -eq 1 ]; then
        echo "Checking if lossless ALAC format is available..."
    else
        echo "Checking if lossless ALAC format is available for $url_count URLs..."
    fi
    echo ""
    
    # Run debug mode to check formats for all URLs at once
    local debug_output
    debug_output=$(docker run --rm --platform linux/amd64 --network host \
        "$DOWNLOADER_IMAGE" \
        --debug "${urls[@]}" 2>&1) || {
        echo "⚠️  Warning: Could not check available formats. Proceeding anyway..."
        return 0
    }
    
    # Check for ALAC in the output (case insensitive)
    if echo "$debug_output" | grep -qiE "(alac|audio-alac-stereo)"; then
        if [ $url_count -eq 1 ]; then
            echo "✓ Lossless ALAC format is available"
        else
            echo "✓ Lossless ALAC format is available for all URLs"
        fi
        echo ""
        
        # Parse format information for each track/URL
        # Extract all ALAC format lines (e.g., "audio-alac-stereo-44100-24")
        local alac_formats=$(echo "$debug_output" | grep -iE "audio-alac-stereo-[0-9]+-[0-9]+")
        
        if [ -z "$alac_formats" ]; then
            # Try alternative format (e.g., "24-bit/44 kHz")
            local alt_formats=$(echo "$debug_output" | grep -iE "[0-9]+-bit/[0-9]+.*kHz")
            if [ -n "$alt_formats" ]; then
                alac_formats="$alt_formats"
            fi
        fi
        
        # Track detected formats for validation
        local detected_sample_rate=""
        local detected_bit_depth=""
        local max_sample_rate=0
        local validation_errors=()
        
        # Parse each format line
        echo "Format details:"
        while IFS= read -r format_line; do
            if [ -z "$format_line" ]; then
                continue
            fi
            
            local sample_rate=""
            local bit_depth=""
            
            # Try to extract from format string (e.g., "audio-alac-stereo-44100-24")
            if echo "$format_line" | grep -qiE "audio-alac-stereo-[0-9]+-[0-9]+"; then
                sample_rate=$(echo "$format_line" | grep -oE "audio-alac-stereo-([0-9]+)-[0-9]+" | sed 's/audio-alac-stereo-\([0-9]*\)-.*/\1/' | head -1)
                bit_depth=$(echo "$format_line" | grep -oE "audio-alac-stereo-[0-9]+-([0-9]+)" | sed 's/audio-alac-stereo-[0-9]*-\(.*\)/\1/' | head -1)
            # Try alternative format (e.g., "24-bit/44 kHz")
            elif echo "$format_line" | grep -qiE "[0-9]+-bit/[0-9]+.*kHz"; then
                bit_depth=$(echo "$format_line" | grep -oE "([0-9]+)-bit" | grep -oE "[0-9]+" | head -1)
                local sample_rate_khz=$(echo "$format_line" | grep -oE "([0-9]+).*kHz" | grep -oE "[0-9]+" | head -1)
                if [ -n "$sample_rate_khz" ]; then
                    sample_rate=$((sample_rate_khz * 1000))
                fi
            fi
            
            if [ -n "$sample_rate" ] && [ -n "$bit_depth" ]; then
                # Track max sample rate found
                if [ "$sample_rate" -gt "$max_sample_rate" ]; then
                    max_sample_rate=$sample_rate
                fi
                
                # Use first detected format for setting defaults
                if [ -z "$detected_sample_rate" ]; then
                    detected_sample_rate=$sample_rate
                    detected_bit_depth=$bit_depth
                fi
                
                # Validate this format against minimum requirements
                # Minimum: 16-bit depth, 44.1 kHz sample rate
                local min_bit_depth=16
                local min_sample_rate=44100
                
                if [ "$bit_depth" -lt "$min_bit_depth" ]; then
                    local sample_rate_khz=$((sample_rate / 1000))
                    validation_errors+=("${bit_depth}-bit / ${sample_rate_khz} kHz (${sample_rate} Hz) - bit depth below minimum ${min_bit_depth}-bit")
                fi
                
                if [ "$sample_rate" -lt "$min_sample_rate" ]; then
                    local sample_rate_khz=$((sample_rate / 1000))
                    validation_errors+=("${bit_depth}-bit / ${sample_rate_khz} kHz (${sample_rate} Hz) - sample rate below minimum ${min_sample_rate} Hz (44.1 kHz)")
                fi
                
                # Display format info
                local sample_rate_khz=$((sample_rate / 1000))
                echo "  ${bit_depth}-bit / ${sample_rate_khz} kHz (${sample_rate} Hz)"
            fi
        done <<< "$alac_formats"
        
        # Show max sample rate available
        if [ "$max_sample_rate" -gt 0 ]; then
            local max_khz=$((max_sample_rate / 1000))
            echo "  Max sample rate available: ${max_khz} kHz (${max_sample_rate} Hz)"
        fi
        
        # Report validation errors if any
        if [ ${#validation_errors[@]} -gt 0 ]; then
            echo ""
            echo "✗ Error: Some formats do not meet minimum quality requirements"
            echo ""
            echo "Formats below minimum:"
            for error in "${validation_errors[@]}"; do
                echo "  - $error"
            done
            echo ""
            echo "This script requires:"
            echo "  - Minimum bit depth: 16-bit"
            echo "  - Minimum sample rate: 44.1 kHz (44100 Hz)"
            return 1
        fi
        
        # Set global variables for use by calling script
        if [ -z "$ALAC_MAX" ]; then
            if [ "$detected_bit_depth" = "24" ]; then
                ALAC_MAX=48000
                echo ""
                echo "Setting max sample rate to 48 kHz (for 24-bit audio)"
            elif [ "$detected_bit_depth" = "16" ]; then
                ALAC_MAX=44100
                echo ""
                echo "Setting max sample rate to 44.1 kHz (for 16-bit audio)"
            else
                # Default to 48 kHz if we can't detect (safer for high quality)
                ALAC_MAX=48000
                echo ""
                echo "Could not detect bit depth, defaulting to 48 kHz"
            fi
        else
            echo ""
            echo "Using specified max sample rate: ${ALAC_MAX} Hz"
        fi
        echo ""
        return 0
    else
        echo "✗ Error: Lossless ALAC format is NOT available"
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

# If script is run directly (not sourced), execute as standalone format checker
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check Docker
    require_docker
    
    # Note: Format checking with --debug doesn't require the wrapper
    # The wrapper is only needed for actual downloading/decryption
    # So we skip wrapper checks here to make format checks faster
    
    URL=$1
    if [ -z "$URL" ]; then
        echo "usage: $0 <apple-music-url> [url2] [url3] ..."
        echo ""
        echo "Check available audio formats for Apple Music URLs."
        echo "Shows what formats (ALAC, Dolby Atmos, AAC, etc.) are available."
        echo "Validates that ALAC formats meet minimum quality requirements."
        echo ""
        echo "Example:"
        echo "  $0 https://music.apple.com/us/album/album-name/1234567890"
        echo ""
        echo "Look for 'alac' or 'audio-alac-stereo' in the output to confirm"
        echo "lossless format is available."
        exit 1
    fi
    
    # Collect all URLs
    shift
    urls=("$URL" "$@")
    
    # Run format check
    if check_alac_formats "${urls[@]}"; then
        exit 0
    else
        exit 1
    fi
fi
