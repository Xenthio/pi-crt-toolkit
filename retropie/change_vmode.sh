#!/bin/bash
#
# Pi CRT Toolkit - Dynamic Video Mode Switcher
# Monitors RetroArch and switches between 240p/480i based on game resolution
#
# Uses the toolkit's abstraction layer for driver-agnostic mode switching.
# Run in background from runcommand-onstart.sh
#
# Based on Sakitoshi's retropie-crt-tvout scripts
#

TOOLKIT_DIR="/opt/crt-toolkit"

# Source toolkit if available, otherwise use direct tvservice
if [[ -f "$TOOLKIT_DIR/lib/video.sh" ]]; then
    source "$TOOLKIT_DIR/lib/platform.sh"
    source "$TOOLKIT_DIR/lib/video.sh"
    USE_TOOLKIT=true
else
    USE_TOOLKIT=false
fi

# Driver-agnostic mode switch
switch_mode() {
    local mode="$1"
    
    if [[ "$USE_TOOLKIT" == "true" ]]; then
        set_video_mode "$mode" 2>/dev/null
    else
        # Fallback to direct tvservice
        case "$mode" in
            240p) tvservice -c "NTSC 4:3 P" 2>/dev/null ;;
            480i) tvservice -c "NTSC 4:3" 2>/dev/null ;;
            288p) tvservice -c "PAL 4:3 P" 2>/dev/null ;;
            576i) tvservice -c "PAL 4:3" 2>/dev/null ;;
        esac
    fi
}

# Get current mode
get_current_mode() {
    if [[ "$USE_TOOLKIT" == "true" ]]; then
        get_video_mode 2>/dev/null
    else
        local status=$(tvservice -s 2>/dev/null)
        if echo "$status" | grep -qiE "progressive"; then
            if echo "$status" | grep -qi "NTSC"; then
                echo "240p"
            else
                echo "288p"
            fi
        else
            if echo "$status" | grep -qi "NTSC"; then
                echo "480i"
            else
                echo "576i"
            fi
        fi
    fi
}

# Wait for RetroArch to start
until pidof retroarch >/dev/null 2>&1; do
    sleep 0.1
done
sleep 0.5

# Wait for video driver initialization
RETROARCH_LOG="/tmp/retroarch/retroarch.log"
while pidof retroarch >/dev/null 2>&1; do
    sleep 0.1
    if grep -q "Found display driver:" "$RETROARCH_LOG" 2>/dev/null; then
        break
    fi
done
sleep 0.5

# Read saved target mode (set by runcommand-onstart.sh)
TARGET_MODE=$(cat /tmp/crt-target-mode 2>/dev/null || echo "240p")

# Determine if we're using NTSC or PAL base
if [[ "$TARGET_MODE" == "288p" ]] || [[ "$TARGET_MODE" == "576i" ]]; then
    BASE_PROGRESSIVE="288p"
    BASE_INTERLACED="576i"
else
    BASE_PROGRESSIVE="240p"
    BASE_INTERLACED="480i"
fi

# Main monitoring loop
while pidof retroarch >/dev/null 2>&1; do
    CURRENT_MODE=$(get_current_mode)
    
    # Read vertical resolution from RetroArch log
    # Look for SET_GEOMETRY lines which report the game's native resolution
    VRES=$(awk '/SET_GEOMETRY:/ {t=$0}END{print t}' "$RETROARCH_LOG" 2>/dev/null)
    VRES=${VRES##*x}      # Get everything after 'x'
    VRES=${VRES%,*}       # Remove everything after comma
    
    # Determine desired mode based on resolution
    if [[ -n "$VRES" ]] && [[ "$VRES" =~ ^[0-9]+$ ]]; then
        # Resolution detected - switch based on vertical res
        if [[ "$VRES" -le 300 ]]; then
            DESIRED_MODE="$BASE_PROGRESSIVE"
        else
            DESIRED_MODE="$BASE_INTERLACED"
        fi
    else
        # No resolution detected - use saved target mode
        DESIRED_MODE="$TARGET_MODE"
    fi
    
    # Switch if different from current
    if [[ "$CURRENT_MODE" != "$DESIRED_MODE" ]]; then
        switch_mode "$DESIRED_MODE"
    fi
    
    # Small delay to avoid hammering
    sleep 0.03
done
