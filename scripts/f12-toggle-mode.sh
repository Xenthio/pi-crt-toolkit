#!/bin/bash
#
# F12 Toggle - Switch between 240p and 480i (full mode)
#
# This toggles:
# - Framebuffer resolution (fbset)
# - VEC scan mode (progressive <-> interlaced)
#
# Both must be done together for proper display!
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries
source "$TOOLKIT_DIR/lib/platform.sh"
source "$TOOLKIT_DIR/lib/video.sh"

# Detect current framebuffer resolution
get_fb_resolution() {
    fbset -s 2>/dev/null | grep "mode " | awk '{print $2, $4}' | head -1 || echo "unknown unknown"
}

get_current_mode() {
    local res=$(get_fb_resolution)
    local width=$(echo "$res" | awk '{print $1}')
    
    if [[ "$width" == "720" ]]; then
        local height=$(echo "$res" | awk '{print $2}')
        if [[ "$height" == "240" ]]; then
            echo "240p"
        elif [[ "$height" == "480" ]]; then
            echo "480i"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

toggle_mode() {
    local current=$(get_current_mode)
    
    case "$current" in
        240p)
            echo "Switching to 480i (720x480 + interlaced)..."
            # Set framebuffer to 480i
            fbset -g 720 480 720 480 16 > /dev/null 2>&1 || \
                fbset -g 720 480 720 480 > /dev/null 2>&1
            # Set interlaced scan
            set_interlaced >/dev/null 2>&1 || true
            echo "✓ Switched to 480i"
            ;;
        480i)
            echo "Switching to 240p (720x240 + progressive)..."
            # Set framebuffer to 240p
            fbset -g 720 240 720 240 16 > /dev/null 2>&1 || \
                fbset -g 720 240 720 240 > /dev/null 2>&1
            # Set progressive scan
            set_progressive >/dev/null 2>&1 || true
            echo "✓ Switched to 240p"
            ;;
        *)
            echo "Error: Unknown current mode ($current)"
            echo "Manual toggle failed - check fbset and VEC status"
            exit 1
            ;;
    esac
}

# Run toggle
toggle_mode
