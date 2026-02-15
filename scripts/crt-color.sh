#!/bin/bash
#
# crt-color - Set TV color mode on KMS
# 
# On KMS, runtime color changes aren't supported without holding DRM master.
# This script modifies cmdline.txt and optionally reboots.
#

CMDLINE="/boot/firmware/cmdline.txt"
[[ ! -f "$CMDLINE" ]] && CMDLINE="/boot/cmdline.txt"

usage() {
    echo "Usage: $0 <pal60|pal|ntsc|ntsc-j> [--reboot]"
    echo ""
    echo "Modes:"
    echo "  pal60   PAL color on 60Hz (for US/JP consoles on PAL TVs)"
    echo "  pal     Standard PAL"
    echo "  ntsc    Standard NTSC"
    echo "  ntsc-j  Japanese NTSC"
    echo ""
    echo "Options:"
    echo "  --reboot   Reboot immediately after changing"
    echo ""
    echo "Note: KMS requires reboot to change color mode."
    echo "For runtime color switching, use FKMS driver with tweakvec."
}

# Map friendly names to KMS tv_mode values
get_tv_mode() {
    case "${1,,}" in
        pal60|pal)   echo "PAL" ;;
        ntsc)        echo "NTSC" ;;
        ntsc-j)      echo "NTSC-J" ;;
        ntsc-443)    echo "NTSC-443" ;;
        pal-m)       echo "PAL-M" ;;
        pal-n)       echo "PAL-N" ;;
        secam)       echo "SECAM" ;;
        *)           echo "" ;;
    esac
}

# Update cmdline.txt with new tv_mode
update_cmdline() {
    local mode="$1"
    local cmdline=$(cat "$CMDLINE")
    
    # Check if video=Composite-1 exists
    if ! echo "$cmdline" | grep -q "video=Composite-1:"; then
        echo "Error: No video=Composite-1 found in cmdline.txt"
        echo "Add something like: video=Composite-1:720x480@60ie"
        return 1
    fi
    
    # Remove existing tv_mode if present
    cmdline=$(echo "$cmdline" | sed 's/,tv_mode=[^[:space:],]*//')
    
    # Add new tv_mode after the video mode spec (before any space)
    # Match video=Composite-1:720x480@60ie or similar
    cmdline=$(echo "$cmdline" | sed "s|\(video=Composite-1:[^[:space:]]*\)|\1,tv_mode=$mode|")
    
    # Write back
    echo "$cmdline" > "$CMDLINE"
    echo "Updated $CMDLINE with tv_mode=$mode"
}

# Main
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

MODE="$1"
shift

TV_MODE=$(get_tv_mode "$MODE")
if [[ -z "$TV_MODE" ]]; then
    echo "Unknown mode: $MODE"
    usage
    exit 1
fi

DO_REBOOT=false
for arg in "$@"; do
    case "$arg" in
        --reboot|-r) DO_REBOOT=true ;;
    esac
done

# Need root for cmdline.txt
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo"
    exit 1
fi

# Update cmdline.txt
if ! update_cmdline "$TV_MODE"; then
    exit 1
fi

if [[ "$DO_REBOOT" == true ]]; then
    echo "Rebooting in 2 seconds..."
    sleep 2
    reboot
else
    echo ""
    echo "Reboot required to apply changes."
    echo "Run: sudo reboot"
fi
