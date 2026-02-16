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

MODE="$1"
COLOR="$2"

# Mode mappings: DRM mode name and framebuffer height
case "$MODE" in
    240p) DRM_MODE="720x240";  FB_HEIGHT=240 ;;
    480i) DRM_MODE="720x480i"; FB_HEIGHT=480 ;;
    288p) DRM_MODE="720x288";  FB_HEIGHT=288 ;;
    576i) DRM_MODE="720x576i"; FB_HEIGHT=576 ;;
    release)
        echo "No daemon to release (setmode no longer runs as daemon)"
        echo "Mode changes are temporary and don't block DRM"
        exit 0
        ;;
    status)
        fbset | head -3
        exit 0
        ;;
    *)
        echo "Usage: $0 <240p|480i|288p|576i|release|status> [ntsc|pal|pal60]"
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

# Try to set DRM mode (won't persist, but may help KMS reconfigure)
$SETMODE $CONN_ID $DRM_MODE 2>/dev/null || true

# Wait a moment
sleep 0.3

# Resize framebuffer to match
fbset -xres 720 -yres $FB_HEIGHT -vxres 720 -vyres $FB_HEIGHT 2>/dev/null

# Force console refresh (switch VT and back)
chvt 2 2>/dev/null
sleep 0.1
chvt 1 2>/dev/null

# Always restore VEC color after mode change (defaults to PAL60)
# Mode switching can reset VEC to monochrome
TWEAKVEC="/opt/crt-toolkit/lib/tweakvec/tweakvec.py"
if [[ -f "$TWEAKVEC" ]]; then
    COLOR="${COLOR:-pal60}"
    python3 "$TWEAKVEC" --preset "${COLOR^^}" >/dev/null 2>&1
    echo "Restored color: $COLOR"
fi

echo "Done! Mode: $MODE"
