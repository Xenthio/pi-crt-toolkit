#!/bin/bash
#
# Pi CRT Toolkit - Video Mode Control
# Abstracted video mode switching that works across drivers
#
# Supports:
# - Legacy: tvservice (Buster and earlier)
# - FKMS: tvservice (Bullseye default, Pi4 CRT recommended)
# - KMS: DRM/modetest (Bookworm/Trixie - limited CRT support)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

#
# Video Mode Definitions
#
declare -A VIDEO_MODES=(
    # NTSC modes (60Hz)
    ["240p"]="ntsc,progressive,60,720,240"
    ["480i"]="ntsc,interlaced,60,720,480"
    # PAL modes (50Hz)
    ["288p"]="pal,progressive,50,720,288"
    ["576i"]="pal,interlaced,50,720,576"
)

# tvservice mode strings (Legacy/FKMS)
declare -A TVSERVICE_MODES=(
    ["240p"]="NTSC 4:3 P"
    ["480i"]="NTSC 4:3"
    ["288p"]="PAL 4:3 P"
    ["576i"]="PAL 4:3"
)

# KMS mode strings for modetest
declare -A KMS_MODES=(
    ["240p"]="720x240"
    ["480i"]="720x480i"
    ["288p"]="720x288"
    ["576i"]="720x576i"
)

# sdtv_mode values for config.txt (boot-time only)
declare -A SDTV_MODES=(
    ["240p"]=16   # NTSC progressive
    ["480i"]=0    # NTSC interlaced
    ["288p"]=18   # PAL progressive
    ["576i"]=2    # PAL interlaced
)

#
# KMS/DRM Helper Functions (for full KMS driver)
#

# Find the composite connector ID
_get_composite_connector() {
    modetest -M vc4 -c 2>/dev/null | grep -iE "Composite" | awk '{print $1}' | head -1
}

# Get current DRM connector status
_get_drm_status() {
    local connector=$(_get_composite_connector)
    [[ -z "$connector" ]] && return 1
    
    modetest -M vc4 -c 2>/dev/null | grep -A30 "^$connector" | head -30
}

#
# Video Mode Switching - Driver Specific
#

# Switch video mode using tvservice (Legacy/FKMS)
# This is the primary method for CRT setups
_switch_tvservice() {
    local mode="$1"
    local tvmode="${TVSERVICE_MODES[$mode]}"
    
    if [[ -z "$tvmode" ]]; then
        echo "Error: Unknown mode '$mode'" >&2
        return 1
    fi
    
    echo "Switching to $mode via tvservice..."
    tvservice -c "$tvmode" 2>/dev/null
    local result=$?
    
    # Small delay for mode to settle
    sleep 0.3
    
    # Refresh framebuffer to apply change (helps some apps pick up new mode)
    fbset -depth 8 2>/dev/null
    fbset -depth 16 2>/dev/null
    
    return $result
}

# Switch video mode using DRM/modetest (Full KMS - Bookworm/Trixie)
# Note: This is less reliable for CRT than FKMS
_switch_kms() {
    local mode="$1"
    local kms_mode="${KMS_MODES[$mode]}"
    
    if [[ -z "$kms_mode" ]]; then
        echo "Error: Unknown mode '$mode'" >&2
        return 1
    fi
    
    # Use kms-switch if available (handles daemon + fbset)
    if command -v kms-switch &>/dev/null; then
        kms-switch "$mode"
        return $?
    fi
    
    # Fallback to direct modetest (mode won't persist)
    local connector=$(_get_composite_connector)
    if [[ -z "$connector" ]]; then
        echo "Error: Composite connector not found" >&2
        return 1
    fi
    
    echo "Switching to $mode via KMS (connector $connector)..."
    echo "Warning: Mode may not persist without kms-switch installed"
    
    # Use modetest to set mode (runs in background)
    (
        modetest -M vc4 -s "$connector:$kms_mode" 2>/dev/null &
        sleep 0.5
    ) &
    
    sleep 1
    echo "Mode set to $kms_mode"
    return 0
}

# Switch video mode - main abstracted function
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
            if command -v modetest &>/dev/null; then
                _switch_kms "$mode"
            else
                echo "Error: modetest not available (install libdrm-tests)" >&2
                return 1
            fi
            ;;
        *)
            echo "Error: Unknown driver '$DRIVER'" >&2
            return 1
            ;;
    esac
}

#
# Smart Mode Switching for Emulators
# Switches to 240p/480i based on game resolution
#

# Determine best mode for a given vertical resolution
get_best_mode_for_resolution() {
    local vres="$1"
    local prefer_ntsc="${2:-true}"
    
    if [[ "$vres" -le 300 ]]; then
        # Low res games -> progressive
        if [[ "$prefer_ntsc" == "true" ]]; then
            echo "240p"
        else
            echo "288p"
        fi
    else
        # High res games -> interlaced
        if [[ "$prefer_ntsc" == "true" ]]; then
            echo "480i"
        else
            echo "576i"
        fi
    fi
}

# Watch RetroArch log and switch modes dynamically
# Used by runcommand scripts
watch_retroarch_mode() {
    local default_mode="${1:-240p}"
    local log_file="/tmp/retroarch/retroarch.log"
    
    # Wait for retroarch to start
    until pgrep -x retroarch >/dev/null 2>&1; do
        sleep 0.1
    done
    sleep 0.5
    
    # Wait for video driver init
    while pgrep -x retroarch >/dev/null 2>&1; do
        sleep 0.1
        if grep -q "Found display driver:" "$log_file" 2>/dev/null; then
            break
        fi
    done
    sleep 0.5
    
    local current_mode="$default_mode"
    
    # Monitor resolution changes
    while pgrep -x retroarch >/dev/null 2>&1; do
        # Read retroarch log for resolution
        local vres=$(awk '/SET_GEOMETRY:/ {t=$0}END{print t}' "$log_file" 2>/dev/null)
        vres=${vres##*x}
        vres=${vres%,*}
        
        if [[ -n "$vres" ]] && [[ "$vres" =~ ^[0-9]+$ ]]; then
            local best_mode=$(get_best_mode_for_resolution "$vres")
            if [[ "$best_mode" != "$current_mode" ]]; then
                set_video_mode "$best_mode"
                current_mode="$best_mode"
            fi
        fi
        
        sleep 0.03
    done
}

#
# Status Functions
#

# Get current video mode
get_video_mode() {
    init_platform
    
    case "$DRIVER" in
        legacy|fkms)
            if supports_feature tvservice; then
                local status=$(tvservice -s 2>/dev/null)
                
                # Parse tvservice output
                if echo "$status" | grep -qiE "NTSC.*progressive|720x240"; then
                    echo "240p"
                elif echo "$status" | grep -qiE "NTSC.*interlace|720x480"; then
                    echo "480i"
                elif echo "$status" | grep -qiE "PAL.*progressive|720x288"; then
                    echo "288p"
                elif echo "$status" | grep -qiE "PAL.*interlace|720x576"; then
                    echo "576i"
                else
                    echo "unknown"
                fi
            else
                echo "unknown"
            fi
            ;;
        kms)
            # For KMS, check fbset or DRM debug state
            local fb_mode=$(fbset -s 2>/dev/null | grep "mode " | tr -d '"' | awk '{print $2}')
            case "$fb_mode" in
                720x240)  echo "240p" ;;
                720x480)  echo "480i" ;;  # Can't easily distinguish 480i from 480p via fbset
                720x288)  echo "288p" ;;
                720x576)  echo "576i" ;;
                *)        
                    # Try DRM debug
                    local drm_size=$(cat /sys/kernel/debug/dri/1/state 2>/dev/null | grep "size=720x" | head -1 | grep -oE '720x[0-9]+')
                    case "$drm_size" in
                        720x240)  echo "240p" ;;
                        720x480)  echo "480i" ;;
                        720x288)  echo "288p" ;;
                        720x576)  echo "576i" ;;
                        *)        echo "unknown" ;;
                    esac
                    ;;
            esac
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get resolution from current output
get_output_resolution() {
    init_platform
    
    case "$DRIVER" in
        legacy|fkms)
            if supports_feature tvservice; then
                tvservice -s 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1
            else
                fbset 2>/dev/null | grep geometry | awk '{print $2"x"$3}'
            fi
            ;;
        kms)
            # Use fbset for current resolution
            local fb_mode=$(fbset -s 2>/dev/null | grep "mode " | tr -d '"' | awk '{print $2}')
            if [[ -n "$fb_mode" ]]; then
                echo "$fb_mode"
            else
                # Fallback to DRM debug
                cat /sys/kernel/debug/dri/1/state 2>/dev/null | grep "size=720x" | head -1 | grep -oE '720x[0-9]+'
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Print full video status
print_video_status() {
    init_platform
    
    echo "Driver: $DRIVER"
    echo "Video Mode: $(get_video_mode)"
    echo "Resolution: $(get_output_resolution)"
    
    if [[ "$DRIVER" == "legacy" ]] || [[ "$DRIVER" == "fkms" ]]; then
        echo ""
        echo "tvservice status:"
        tvservice -s 2>/dev/null
        echo ""
        echo "Available modes (tvservice -m CEA):"
        tvservice -m CEA 2>/dev/null | head -5
    elif [[ "$DRIVER" == "kms" ]]; then
        echo ""
        echo "Available KMS modes:"
        kmsprint -m 2>/dev/null | grep -i composite
    fi
}

#
# CLI Interface
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        240p|480i|288p|576i)
            set_video_mode "$1"
            ;;
        watch)
            watch_retroarch_mode "${2:-240p}"
            ;;
        status|get)
            print_video_status
            ;;
        mode)
            # Just print current mode (for scripts)
            get_video_mode
            ;;
        resolution|res)
            # Just print current resolution (for scripts)
            get_output_resolution
            ;;
        driver)
            # Just print detected driver (for scripts)
            init_platform
            echo "$DRIVER"
            ;;
        list)
            echo "Available video modes:"
            for mode in "${!VIDEO_MODES[@]}"; do
                IFS=',' read -r standard scan refresh width height <<< "${VIDEO_MODES[$mode]}"
                echo "  $mode - ${width}x${height}@${refresh}Hz $standard $scan"
            done | sort
            ;;
        --help|-h|help)
            cat << EOF
Pi CRT Toolkit - Video Mode Control

Usage: $0 <command> [args]

Video modes (driver-agnostic):
  240p          Switch to 240p (NTSC progressive)
  480i          Switch to 480i (NTSC interlaced)
  288p          Switch to 288p (PAL progressive)
  576i          Switch to 576i (PAL interlaced)

Emulator integration:
  watch [mode]  Watch RetroArch and auto-switch 240p/480i

Status commands:
  status        Show full video status
  mode          Print current mode (240p/480i/288p/576i)
  resolution    Print current resolution
  driver        Print detected driver (legacy/fkms/kms)
  list          List available modes

Examples:
  $0 240p           # Switch to 240p
  $0 status         # Show current status
  $0 mode           # Output: 240p (for scripting)

Driver support:
  Legacy/FKMS: Full support via tvservice
  KMS: Limited support via modetest/DRM
EOF
            ;;
        *)
            echo "Usage: $0 <240p|480i|288p|576i|status|mode|list|help>"
            echo "Run '$0 help' for full usage"
            exit 1
            ;;
    esac
fi
