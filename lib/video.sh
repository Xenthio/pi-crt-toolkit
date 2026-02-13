#!/bin/bash
#
# Pi CRT Toolkit - Video Mode Control
# Abstracted video mode switching that works across drivers
#
# Supports:
# - Legacy: tvservice (Buster and earlier)
# - FKMS: tvservice (Bullseye default)
# - KMS: modetest/DRM properties (Bookworm/Trixie)
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

# sdtv_mode values for config.txt
declare -A SDTV_MODES=(
    ["240p"]=16   # NTSC progressive
    ["480i"]=0    # NTSC interlaced
    ["288p"]=18   # PAL progressive
    ["576i"]=2    # PAL interlaced
)

#
# KMS/DRM Helper Functions
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
_switch_tvservice() {
    local mode="$1"
    local tvmode="${TVSERVICE_MODES[$mode]}"
    
    if [[ -z "$tvmode" ]]; then
        echo "Error: Unknown mode '$mode'" >&2
        return 1
    fi
    
    echo "Switching to $mode via tvservice..."
    tvservice -c "$tvmode" 2>/dev/null
    
    # Refresh framebuffer to apply change
    fbset -depth 8 2>/dev/null
    fbset -depth 16 2>/dev/null
    
    return 0
}

# Switch video mode using DRM/modetest (Full KMS - Trixie/Bookworm)
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
# Color Mode / TV Norm Control
#

# Set color mode via DRM property (KMS only)
# Values: NTSC, NTSC-443, NTSC-J, PAL, PAL-M, PAL-N, SECAM, Mono
_set_color_kms() {
    local color_mode="$1"
    local connector=$(_get_composite_connector)
    
    if [[ -z "$connector" ]]; then
        echo "Error: Composite connector not found" >&2
        return 1
    fi
    
    # Map color mode names to DRM enum values
    # Property 32 "TV mode": NTSC=0 NTSC-443=1 NTSC-J=2 PAL=3 PAL-M=4 PAL-N=5 SECAM=6 Mono=7
    local drm_value
    case "$color_mode" in
        NTSC|ntsc)       drm_value=0 ;;
        NTSC-443)        drm_value=1 ;;
        NTSC-J)          drm_value=2 ;;
        PAL|pal)         drm_value=3 ;;
        PAL-M)           drm_value=4 ;;
        PAL-N)           drm_value=5 ;;
        SECAM)           drm_value=6 ;;
        Mono)            drm_value=7 ;;
        PAL60|pal60)     drm_value=3 ;;  # PAL color with 480i = PAL60
        *)
            echo "Error: Unknown color mode '$color_mode'" >&2
            return 1
            ;;
    esac
    
    echo "Setting TV mode to $color_mode (value $drm_value) via DRM..."
    
    # Set the TV mode property
    modetest -M vc4 -w "$connector:TV mode:$drm_value" 2>/dev/null &
    sleep 0.5
    
    return 0
}

# Set color mode - abstracted for all drivers
set_color_mode() {
    local color_mode="$1"
    
    init_platform
    
    case "$DRIVER" in
        legacy|fkms)
            # Use tweakvec if available
            if [[ -f /home/pi/tweakvec/tweakvec.py ]]; then
                echo "Setting color to $color_mode via tweakvec..."
                sudo python3 /home/pi/tweakvec/tweakvec.py --preset "$color_mode" 2>/dev/null
            else
                echo "Warning: tweakvec not installed" >&2
                echo "Install with: cd /home/pi && git clone https://github.com/kFYatek/tweakvec.git" >&2
                return 1
            fi
            ;;
        kms)
            _set_color_kms "$color_mode"
            ;;
        *)
            echo "Error: Unknown driver '$DRIVER'" >&2
            return 1
            ;;
    esac
    
    # Save current color mode
    echo "$color_mode" > /tmp/crt-toolkit-color
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
                if echo "$status" | grep -qE "NTSC.*progressive|720x240"; then
                    echo "240p"
                elif echo "$status" | grep -qE "NTSC.*interlace|720x480"; then
                    echo "480i"
                elif echo "$status" | grep -qE "PAL.*progressive|720x288"; then
                    echo "288p"
                elif echo "$status" | grep -qE "PAL.*interlace|720x576"; then
                    echo "576i"
                else
                    echo "unknown"
                fi
            else
                echo "unknown"
            fi
            ;;
        kms)
            # Parse kmsprint output
            local mode=$(kmsprint -m 2>/dev/null | grep -i composite | grep -oE '[0-9]+x[0-9]+i?' | head -1)
            case "$mode" in
                720x240)  echo "240p" ;;
                720x480i) echo "480i" ;;
                720x288)  echo "288p" ;;
                720x576i) echo "576i" ;;
                *)        echo "unknown" ;;
            esac
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get current color mode
get_color_mode() {
    init_platform
    
    case "$DRIVER" in
        legacy|fkms)
            # Check saved state or tweakvec
            if [[ -f /tmp/crt-toolkit-color ]]; then
                cat /tmp/crt-toolkit-color
            else
                echo "unknown"
            fi
            ;;
        kms)
            # Read from DRM property
            local connector=$(_get_composite_connector)
            if [[ -n "$connector" ]]; then
                local value=$(modetest -M vc4 -c 2>/dev/null | grep -A3 "TV mode:" | grep "value:" | awk '{print $2}')
                case "$value" in
                    0) echo "NTSC" ;;
                    1) echo "NTSC-443" ;;
                    2) echo "NTSC-J" ;;
                    3) echo "PAL" ;;
                    4) echo "PAL-M" ;;
                    5) echo "PAL-N" ;;
                    6) echo "SECAM" ;;
                    7) echo "Mono" ;;
                    *) echo "unknown" ;;
                esac
            else
                echo "unknown"
            fi
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
            kmsprint -m 2>/dev/null | grep -i composite | grep -oE '[0-9]+x[0-9]+i?' | head -1
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Print full status
print_status() {
    init_platform
    
    echo "Driver: $DRIVER"
    echo "Video Mode: $(get_video_mode)"
    echo "Color Mode: $(get_color_mode)"
    echo "Resolution: $(get_output_resolution)"
    
    if [[ "$DRIVER" == "kms" ]]; then
        echo ""
        echo "Available KMS modes:"
        kmsprint -m 2>/dev/null | grep -i composite
    elif supports_feature tvservice; then
        echo ""
        echo "tvservice status:"
        tvservice -s 2>/dev/null
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
        color)
            if [[ -n "$2" ]]; then
                set_color_mode "$2"
            else
                echo "Current color: $(get_color_mode)"
            fi
            ;;
        status|get)
            print_status
            ;;
        list)
            echo "Available video modes:"
            for mode in "${!VIDEO_MODES[@]}"; do
                IFS=',' read -r standard scan refresh width height <<< "${VIDEO_MODES[$mode]}"
                echo "  $mode - ${width}x${height}@${refresh}Hz $standard $scan"
            done | sort
            echo ""
            echo "Available color modes:"
            echo "  NTSC, NTSC-J, NTSC-443, PAL, PAL-M, PAL-N, PAL60, SECAM, Mono"
            ;;
        *)
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Video modes:"
            echo "  240p          Switch to 240p (NTSC progressive)"
            echo "  480i          Switch to 480i (NTSC interlaced)"
            echo "  288p          Switch to 288p (PAL progressive)"
            echo "  576i          Switch to 576i (PAL interlaced)"
            echo ""
            echo "Color modes:"
            echo "  color <mode>  Set color mode (NTSC/PAL/PAL60/etc)"
            echo "  color         Show current color mode"
            echo ""
            echo "Status:"
            echo "  status        Show current video/color status"
            echo "  list          List available modes"
            exit 1
            ;;
    esac
fi
