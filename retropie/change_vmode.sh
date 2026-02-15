#!/bin/bash
#
# Pi CRT Toolkit - Dynamic Video Mode Switcher
# Monitors RetroArch and switches between 240p/480i based on game resolution
#
# This is the main workhorse for automatic mode switching.
# Run in background from runcommand-onstart.sh
#
# Based on Sakitoshi's retropie-crt-tvout scripts
#

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
SVMODE=$(cat /tmp/crt-target-mode 2>/dev/null || echo "240p")

# Convert to tvservice format
case "$SVMODE" in
    240p) SVMODE_TV="NTSC 4:3 P" ;;
    480i) SVMODE_TV="NTSC 4:3" ;;
    288p) SVMODE_TV="PAL 4:3 P" ;;
    576i) SVMODE_TV="PAL 4:3" ;;
    *)    SVMODE_TV="NTSC 4:3 P" ;;
esac

# Main monitoring loop
while pidof retroarch >/dev/null 2>&1; do
    # Get current mode from tvservice
    CVMODE_RAW=$(tvservice -s 2>/dev/null)
    CVMODE_TYPE=${CVMODE_RAW##*[}
    CVMODE_TYPE=${CVMODE_TYPE%]*}
    CVMODE_SCAN=${CVMODE_RAW##*,}
    
    # Determine current mode string
    if [[ "$CVMODE_SCAN" == *"progressive"* ]]; then
        CVMODE="$CVMODE_TYPE P"
    else
        CVMODE="$CVMODE_TYPE"
    fi
    
    # Read vertical resolution from RetroArch log
    # Look for SET_GEOMETRY lines which report the game's native resolution
    VRES=$(awk '/SET_GEOMETRY:/ {t=$0}END{print t}' "$RETROARCH_LOG" 2>/dev/null)
    VRES=${VRES##*x}      # Get everything after 'x'
    VRES=${VRES%,*}       # Remove everything after comma
    
    # Determine desired mode based on resolution
    if [[ -n "$VRES" ]] && [[ "$VRES" =~ ^[0-9]+$ ]]; then
        # Resolution detected - switch based on vertical res
        if [[ "$VRES" -le 300 ]]; then
            DVMODE="$CVMODE_TYPE P"  # Progressive for low-res
        else
            DVMODE="$CVMODE_TYPE"    # Interlaced for high-res
        fi
        
        # Switch if different from current
        if [[ "$CVMODE" != "$DVMODE" ]]; then
            tvservice -c "$DVMODE" 2>/dev/null
        fi
    else
        # No resolution detected - use saved target mode
        if [[ "$CVMODE" != "$SVMODE_TV" ]]; then
            tvservice -c "$SVMODE_TV" 2>/dev/null
        fi
    fi
    
    # Small delay to avoid hammering tvservice
    sleep 0.03
done
