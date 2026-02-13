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
TVNORM_FILE=/tmp/crt-tvnorm
COLOR_STATE_FILE=/tmp/crt-toolkit-color

MODE="$1"
COLOR="$2"

# Read current color state (default to ntsc if not set)
get_current_color() {
    if [[ -f "$COLOR_STATE_FILE" ]]; then
        cat "$COLOR_STATE_FILE"
    else
        echo "ntsc"
    fi
}

# Convert color name to TV norm value
color_to_norm() {
    case "$1" in
        ntsc|NTSC)   echo "0" ;;
        pal|PAL)     echo "3" ;;
        pal60|PAL60) echo "3" ;;
        *)           echo "0" ;;
    esac
}

# Mode mappings: DRM mode name, framebuffer height, and default TV norm
# TV mode values: NTSC=0, PAL=3
case "$MODE" in
    240p) DRM_MODE="720x240";  FB_HEIGHT=240; DEFAULT_NORM=0 ;;
    480i) DRM_MODE="720x480i"; FB_HEIGHT=480; DEFAULT_NORM=0 ;;
    288p) DRM_MODE="720x288";  FB_HEIGHT=288; DEFAULT_NORM=3 ;;
    576i) DRM_MODE="720x576i"; FB_HEIGHT=576; DEFAULT_NORM=3 ;;
    color)
        # Just change color, don't change mode
        case "$COLOR" in
            ntsc|NTSC)   echo "0" > "$TVNORM_FILE"; echo "ntsc" > "$COLOR_STATE_FILE" ;;
            pal|PAL)     echo "3" > "$TVNORM_FILE"; echo "pal" > "$COLOR_STATE_FILE" ;;
            pal60|PAL60) echo "3" > "$TVNORM_FILE"; echo "pal60" > "$COLOR_STATE_FILE" ;;
            *) echo "Usage: $0 color <ntsc|pal|pal60>"; exit 1 ;;
        esac
        # Signal daemon to reload
        if [[ -f "$PIDFILE" ]]; then
            kill -USR1 "$(cat "$PIDFILE")" 2>/dev/null
        fi
        echo "Color: $COLOR"
        exit 0
        ;;
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
        echo "Color: $(get_current_color)"
        fbset 2>/dev/null | head -3
        exit 0
        ;;
    *)
        echo "Usage: $0 <240p|480i|288p|576i|status> [ntsc|pal|pal60]"
        echo "       $0 color <ntsc|pal|pal60>"
        exit 1
        ;;
esac

# Find composite connector ID
CONN_ID=""
if [[ -f /sys/class/drm/card1-Composite-1/connector_id ]]; then
    CONN_ID=$(cat /sys/class/drm/card1-Composite-1/connector_id)
fi

if [[ -z "$CONN_ID" ]]; then
    CONN_ID=$(modetest -M vc4 -c 2>/dev/null | grep -i composite | awk '{print $1}' | head -1)
fi

if [[ -z "$CONN_ID" ]]; then
    echo "Error: Composite connector not found"
    exit 1
fi

# Check if framebuffer_height in config supports this mode
CONFIG_FILE="/boot/config.txt"
[[ -f "/boot/firmware/config.txt" ]] && CONFIG_FILE="/boot/firmware/config.txt"
CONFIG_FB_HEIGHT=$(grep -E "^framebuffer_height=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)

if [[ -n "$CONFIG_FB_HEIGHT" && "$FB_HEIGHT" -gt "$CONFIG_FB_HEIGHT" ]]; then
    echo "Error: Mode $MODE requires framebuffer_height >= $FB_HEIGHT"
    echo "Current config has framebuffer_height=$CONFIG_FB_HEIGHT"
    echo ""
    echo "To fix, edit $CONFIG_FILE and set:"
    echo "  framebuffer_height=576"
    echo "Then reboot."
    exit 1
fi

# Determine TV norm to use:
# 1. If color explicitly specified, use that
# 2. Else preserve current color state (for NTSC modes)
# 3. PAL modes always use PAL norm (required for mode to work)
if [[ -n "$COLOR" ]]; then
    # Explicit color override
    TV_NORM=$(color_to_norm "$COLOR")
    echo "$COLOR" > "$COLOR_STATE_FILE"
elif [[ "$DEFAULT_NORM" -eq 3 ]]; then
    # PAL modes must use PAL norm
    TV_NORM=3
else
    # NTSC modes: preserve current color
    CURRENT_COLOR=$(get_current_color)
    TV_NORM=$(color_to_norm "$CURRENT_COLOR")
fi

echo "Switching to $MODE ($DRM_MODE) [color: $(get_current_color)]"

# Kill existing mode daemon
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        # Wait for it to actually exit
        for i in 1 2 3 4 5; do
            kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 0.1
        done
        # Force kill if still running
        kill -9 "$OLD_PID" 2>/dev/null
        sleep 0.1
    fi
    rm -f "$PIDFILE"
fi

# Check setmode binary exists
if [[ ! -x "$SETMODE" ]]; then
    echo "Error: $SETMODE not found"
    echo "Run: sudo /opt/crt-toolkit/install.sh"
    exit 1
fi

# Start new mode daemon (it sets TV norm internally now)
$SETMODE "$CONN_ID" "$DRM_MODE" "$TV_NORM" daemon

# Wait for daemon to start and mode to apply
sleep 0.5

# Resize framebuffer to match
fbset -xres 720 -yres $FB_HEIGHT -vxres 720 -vyres $FB_HEIGHT 2>/dev/null

# Set console font based on resolution
if [[ $FB_HEIGHT -le 288 ]]; then
    setfont /usr/share/consolefonts/Lat15-VGA8.psf.gz 2>/dev/null
else
    setfont /usr/share/consolefonts/Lat15-VGA16.psf.gz 2>/dev/null
fi

# Force console refresh - do this more carefully
sleep 0.2
chvt 2 2>/dev/null
sleep 0.2
chvt 1 2>/dev/null

echo "Done! Mode: $MODE"
