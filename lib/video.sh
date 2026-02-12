#!/bin/bash
#
# Pi CRT Toolkit - Video Mode Control
# Abstracted video mode switching that works across drivers
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

#
# Video Mode Definitions
#
declare -A VIDEO_MODES=(
    # NTSC modes
    ["240p"]="ntsc,progressive,60,720,480"
    ["480i"]="ntsc,interlaced,60,720,480"
    # PAL modes
    ["288p"]="pal,progressive,50,720,576"
    ["576i"]="pal,interlaced,50,720,576"
)

# tvservice mode codes
declare -A TVSERVICE_MODES=(
    ["240p"]="NTSC 4:3 P"
    ["480i"]="NTSC 4:3"
    ["288p"]="PAL 4:3 P"
    ["576i"]="PAL 4:3"
)

# sdtv_mode values for config.txt
declare -A SDTV_MODES=(
    ["240p"]=16   # NTSC progressive
    ["480i"]=0    # NTSC interlaced
    ["288p"]=18   # PAL progressive
    ["576i"]=2    # PAL interlaced
)

#
# Video Mode Switching - Driver Abstracted
#

# Switch video mode using tvservice (legacy/fkms)
_switch_tvservice() {
    local mode="$1"
    local tvmode="${TVSERVICE_MODES[$mode]}"
    
    if [[ -z "$tvmode" ]]; then
        echo "Error: Unknown mode '$mode'" >&2
        return 1
    fi
    
    tvservice -c "$tvmode" 2>/dev/null
    
    # Refresh framebuffer
    fbset -depth 8 && fbset -depth 16
    
    return 0
}

# Switch video mode using DRM/KMS (full kms driver)
_switch_drm() {
    local mode="$1"
    
    # Parse mode info
    IFS=',' read -r standard scan refresh width height <<< "${VIDEO_MODES[$mode]}"
    
    # On full KMS, we need to use modetest or modify config and reboot
    # For runtime switching, we can try kmsprint if available
    
    if command -v modetest &>/dev/null; then
        # Find the composite connector
        local connector=$(modetest -M vc4 -c 2>/dev/null | grep -E "composite|Composite" | awk '{print $1}')
        if [[ -n "$connector" ]]; then
            # This is limited - full KMS often requires reboot for mode changes
            echo "Warning: Full KMS driver has limited runtime mode switching" >&2
            echo "Mode change may require reboot" >&2
        fi
    fi
    
    echo "Full KMS mode switching not fully implemented yet" >&2
    return 1
}

# Main mode switch function
set_video_mode() {
    local mode="$1"
    
    init_platform
    
    # Validate mode
    if [[ -z "${VIDEO_MODES[$mode]}" ]]; then
        echo "Error: Unknown video mode '$mode'" >&2
        echo "Available modes: ${!VIDEO_MODES[*]}" >&2
        return 1
    fi
    
    # Check composite support
    if ! supports_feature composite; then
        echo "Error: This Pi model does not support composite output" >&2
        return 1
    fi
    
    # Switch based on driver
    case "$DRIVER" in
        legacy|fkms)
            if supports_feature tvservice; then
                _switch_tvservice "$mode"
            else
                echo "Error: tvservice not available" >&2
                return 1
            fi
            ;;
        kms)
            _switch_drm "$mode"
            ;;
        *)
            echo "Error: Unknown driver '$DRIVER'" >&2
            return 1
            ;;
    esac
}

# Get current video mode
get_video_mode() {
    init_platform
    
    if supports_feature tvservice; then
        local status=$(tvservice -s 2>/dev/null)
        
        # Parse tvservice output
        if echo "$status" | grep -q "NTSC.*progressive"; then
            echo "240p"
        elif echo "$status" | grep -q "NTSC.*interlaced"; then
            echo "480i"
        elif echo "$status" | grep -q "PAL.*progressive"; then
            echo "288p"
        elif echo "$status" | grep -q "PAL.*interlaced"; then
            echo "576i"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Get resolution from tvservice (for apps that need real output size)
get_output_resolution() {
    init_platform
    
    if supports_feature tvservice; then
        local res=$(tvservice -s 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
        echo "$res"
    else
        # Fallback to fbset
        fbset 2>/dev/null | grep geometry | awk '{print $2"x"$3}'
    fi
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        240p|480i|288p|576i)
            set_video_mode "$1"
            ;;
        status|get)
            echo "Current mode: $(get_video_mode)"
            echo "Resolution: $(get_output_resolution)"
            ;;
        list)
            echo "Available modes:"
            for mode in "${!VIDEO_MODES[@]}"; do
                IFS=',' read -r standard scan refresh width height <<< "${VIDEO_MODES[$mode]}"
                echo "  $mode - ${width}x${height}@${refresh}Hz $standard $scan"
            done
            ;;
        *)
            echo "Usage: $0 <240p|480i|288p|576i|status|list>"
            exit 1
            ;;
    esac
fi
