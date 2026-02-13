#!/bin/bash
#
# KMS Mode Switcher for Pi CRT Toolkit
# Runtime video mode switching on full KMS (Trixie/Bookworm)
#
# Usage: kms-switch <mode> [color]
# Modes: 240p, 480i, 288p, 576i
# Colors: ntsc, pal, pal60
#

SETMODE=/usr/local/bin/crt-setmode
PIDFILE=/tmp/crt-setmode.pid

MODE="$1"
COLOR="$2"

# Mode mappings: DRM mode name and framebuffer height
case "$MODE" in
    240p) DRM_MODE="720x240";  FB_HEIGHT=240 ;;
    480i) DRM_MODE="720x480i"; FB_HEIGHT=480 ;;
    288p) DRM_MODE="720x288";  FB_HEIGHT=288 ;;
    576i) DRM_MODE="720x576i"; FB_HEIGHT=576 ;;
    status)
        if [[ -f "$PIDFILE" ]]; then
            PID=$(cat "$PIDFILE")
            if kill -0 "$PID" 2>/dev/null; then
                echo "Mode daemon running (PID $PID)"
            else
                echo "Mode daemon not running (stale pidfile)"
            fi
        else
            echo "Mode daemon not running"
        fi
        fbset | head -3
        exit 0
        ;;
    *)
        echo "Usage: $0 <240p|480i|288p|576i|status> [ntsc|pal|pal60]"
        exit 1
        ;;
esac

# Find composite connector ID
CONN_ID=""
if [[ -f /sys/class/drm/card1-Composite-1/connector_id ]]; then
    CONN_ID=$(cat /sys/class/drm/card1-Composite-1/connector_id)
fi

if [[ -z "$CONN_ID" ]]; then
    # Fallback: parse from modetest
    CONN_ID=$(modetest -M vc4 -c 2>/dev/null | grep -i composite | awk '{print $1}' | head -1)
fi

if [[ -z "$CONN_ID" ]]; then
    echo "Error: Composite connector not found"
    exit 1
fi

echo "Switching to $MODE (DRM: $DRM_MODE, FB: 720x$FB_HEIGHT, Connector: $CONN_ID)"

# Kill existing mode daemon
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.3
        # Force kill if still running
        kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

# Check setmode binary exists
if [[ ! -x "$SETMODE" ]]; then
    echo "Error: $SETMODE not found"
    echo "Run: sudo /opt/crt-toolkit/install.sh"
    exit 1
fi

# Start new mode daemon
$SETMODE $CONN_ID $DRM_MODE daemon &
NEW_PID=$!
echo $NEW_PID > "$PIDFILE"

# Wait for mode to apply
sleep 0.3

# Resize framebuffer to match
fbset -xres 720 -yres $FB_HEIGHT -vxres 720 -vyres $FB_HEIGHT 2>/dev/null

# Force console refresh (switch VT and back)
chvt 2 2>/dev/null
sleep 0.1
chvt 1 2>/dev/null

# Apply color mode if specified
if [[ -n "$COLOR" ]]; then
    case "$COLOR" in
        ntsc)  TV_MODE=0 ;;
        pal)   TV_MODE=3 ;;
        pal60) TV_MODE=3 ;;  # PAL color = PAL60 on NTSC timing
        *)
            echo "Warning: Unknown color '$COLOR', ignoring"
            COLOR=""
            ;;
    esac
    
    if [[ -n "$COLOR" ]]; then
        modetest -M vc4 -w "$CONN_ID:TV mode:$TV_MODE" 2>/dev/null &
        echo "Color: $COLOR"
    fi
fi

echo "Done! Mode: $MODE"
