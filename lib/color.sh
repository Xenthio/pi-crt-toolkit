#!/bin/bash
#
# Pi CRT Toolkit - Color Mode Control
# PAL60 and NTSC color encoding via register manipulation
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

# Color mode state file
COLOR_STATE_FILE="/tmp/crt-toolkit-color"

#
# tweakvec integration
#

# Find tweakvec installation
find_tweakvec() {
    local paths=(
        "/usr/local/lib/crt-toolkit/tweakvec/tweakvec.py"
        "/home/pi/tweakvec/tweakvec.py"
        "$HOME/tweakvec/tweakvec.py"
        "/opt/crt-toolkit/tweakvec/tweakvec.py"
    )
    
    for path in "${paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Apply color mode via tweakvec
_apply_tweakvec() {
    local mode="$1"  # pal60 or ntsc
    local tweakvec_path
    
    tweakvec_path=$(find_tweakvec)
    if [[ $? -ne 0 ]]; then
        echo "Error: tweakvec not found" >&2
        return 1
    fi
    
    local preset
    case "$mode" in
        pal60|PAL60) preset="PAL60" ;;
        ntsc|NTSC)   preset="NTSC" ;;
        *)
            echo "Error: Unknown color mode '$mode'" >&2
            return 1
            ;;
    esac
    
    python3 "$tweakvec_path" --preset "$preset" 2>/dev/null
    return $?
}

#
# Native PAL60 implementation (no tweakvec dependency)
# Uses vcgencmd to modify VEC registers directly
#

# PAL60 register values (from tweakvec)
# These modify the Video Encoder (VEC) to output PAL color on NTSC timing
PAL60_REGS=(
    # Color burst frequency for PAL (4.43361875 MHz)
    "vec_fc=0x2A098ACB"
    # PAL phase settings
    "vec_sa=0x00000000"
)

NTSC_REGS=(
    # Color burst frequency for NTSC (3.579545 MHz)
    "vec_fc=0x21F07C1F"
    # NTSC phase settings  
    "vec_sa=0x00000000"
)

# Apply color mode via direct register access (experimental)
_apply_native() {
    local mode="$1"
    
    # Check if we can use vcgencmd
    if ! command -v vcgencmd &>/dev/null; then
        echo "Error: vcgencmd not found" >&2
        return 1
    fi
    
    # This is experimental - tweakvec does more complex manipulation
    # For now, just warn and fall back
    echo "Warning: Native color mode switching is experimental" >&2
    echo "Consider installing tweakvec for full support" >&2
    
    return 1
}

#
# Main color mode functions
#

set_color_mode() {
    local mode="$1"
    
    init_platform
    
    # Check support
    if ! supports_feature tweakvec; then
        echo "Error: Color mode switching not supported on $DRIVER driver" >&2
        return 1
    fi
    
    # Try tweakvec first, fall back to native
    if _apply_tweakvec "$mode"; then
        echo "$mode" > "$COLOR_STATE_FILE"
        return 0
    elif _apply_native "$mode"; then
        echo "$mode" > "$COLOR_STATE_FILE"
        return 0
    else
        echo "Error: Failed to set color mode" >&2
        return 1
    fi
}

get_color_mode() {
    if [[ -f "$COLOR_STATE_FILE" ]]; then
        cat "$COLOR_STATE_FILE"
    else
        echo "unknown"
    fi
}

# Install tweakvec if not present
install_tweakvec() {
    local install_path="/usr/local/lib/crt-toolkit/tweakvec"
    
    if find_tweakvec &>/dev/null; then
        echo "tweakvec already installed at: $(find_tweakvec)"
        return 0
    fi
    
    echo "Installing tweakvec..."
    mkdir -p "$(dirname "$install_path")"
    
    # Try different sources
    if git clone https://github.com/ArcadeHustle/tweakvec.git "$install_path" 2>/dev/null; then
        echo "Installed from ArcadeHustle/tweakvec"
    elif git clone https://github.com/mondul/tweakvec.git "$install_path" 2>/dev/null; then
        echo "Installed from mondul/tweakvec"
    else
        echo "Error: Failed to clone tweakvec" >&2
        return 1
    fi
    
    return 0
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        pal60|PAL60)
            set_color_mode "pal60"
            ;;
        ntsc|NTSC)
            set_color_mode "ntsc"
            ;;
        status|get)
            echo "Current color mode: $(get_color_mode)"
            echo "tweakvec: $(find_tweakvec 2>/dev/null || echo 'not found')"
            ;;
        install)
            install_tweakvec
            ;;
        *)
            echo "Usage: $0 <pal60|ntsc|status|install>"
            exit 1
            ;;
    esac
fi
