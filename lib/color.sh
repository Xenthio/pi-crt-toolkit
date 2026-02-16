#!/bin/bash
#
# Pi CRT Toolkit - Color Mode Control
# PAL60 and other color encoding modes
#
# IMPORTANT: PAL60 on FKMS requires tweakvec
# PAL60 = PAL color encoding (4.43 MHz subcarrier) on 525-line NTSC timing
# This gives proper PAL color on 60Hz displays - required for US/Japan consoles on PAL TVs
#
# Methods by driver:
# - ALL drivers: tweakvec (direct VEC register manipulation via /dev/mem)
# - tweakvec bypasses DRM entirely and works on Legacy, FKMS, and KMS
#
# Without tweakvec on FKMS:
# - sdtv_mode=4 (PAL-M) gives 525-line PAL but with 3.58 MHz subcarrier (wrong color)
# - sdtv_mode=0 (NTSC) gives proper 3.58 MHz but NTSC color encoding
# - PAL60 specifically needs PAL's 4.43 MHz subcarrier, which only tweakvec can set
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

# Color mode state file
COLOR_STATE_FILE="/tmp/crt-toolkit-color"

# tweakvec repo (Pi4 compatible fork)
TWEAKVEC_REPO="https://github.com/kFYatek/tweakvec.git"

#
# tweakvec Management
#

# Find tweakvec installation
find_tweakvec() {
    local paths=(
        "/opt/crt-toolkit/lib/tweakvec/tweakvec.py"
        "/usr/local/lib/crt-toolkit/tweakvec/tweakvec.py"
        "/home/pi/tweakvec/tweakvec.py"
        "$HOME/tweakvec/tweakvec.py"
    )
    
    for path in "${paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Install tweakvec
install_tweakvec() {
    local install_path="${1:-/opt/crt-toolkit/lib/tweakvec}"
    
    if find_tweakvec &>/dev/null; then
        echo "tweakvec already installed at: $(find_tweakvec)"
        return 0
    fi
    
    echo "Installing tweakvec to $install_path..."
    
    if ! command -v git &>/dev/null; then
        echo "Error: git not installed" >&2
        return 1
    fi
    
    mkdir -p "$(dirname "$install_path")"
    
    if git clone --depth 1 "$TWEAKVEC_REPO" "$install_path" 2>/dev/null; then
        echo "tweakvec installed successfully"
        return 0
    else
        echo "Error: Failed to clone tweakvec" >&2
        return 1
    fi
}

#
# Color Mode Application
#

# Apply color mode via tweakvec (FKMS/Legacy)
_apply_tweakvec() {
    local mode="$1"
    local tweakvec_path
    
    tweakvec_path=$(find_tweakvec)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Map mode names to tweakvec presets
    local preset
    case "${mode,,}" in
        pal60)      preset="PAL60" ;;
        ntsc)       preset="NTSC" ;;
        ntsc-j)     preset="NTSC_J" ;;
        pal)        preset="PAL" ;;
        pal-m)      preset="PAL_M" ;;
        pal-n)      preset="PAL_N" ;;
        secam)      preset="SECAM" ;;
        ntsc443)    preset="NTSC443" ;;
        mono525)    preset="MONO525" ;;
        mono625)    preset="MONO625" ;;
        *)
            echo "Error: Unknown color mode '$mode'" >&2
            return 1
            ;;
    esac
    
    # Run tweakvec with sudo (needs /dev/mem access)
    if sudo python3 "$tweakvec_path" --preset "$preset" 2>/dev/null; then
        return 0
    else
        echo "Error: tweakvec failed" >&2
        return 1
    fi
}

# Apply color mode via DRM property (KMS only)
_apply_kms() {
    local mode="$1"
    
    # KMS: Use tweakvec for direct VEC access (bypasses DRM)
    # This works on KMS because tweakvec uses /dev/mem directly
    # and doesn't require DRM master or connector access
    if _apply_tweakvec "$mode"; then
        return 0
    else
        echo "Error: tweakvec required for color mode on KMS" >&2
        echo "Install with: install.sh or manually clone to /opt/crt-toolkit/lib/tweakvec" >&2
        return 1
    fi
}

# Find composite connector (duplicated for standalone use)
_get_composite_connector() {
    modetest -M vc4 -c 2>/dev/null | grep -iE "Composite" | awk '{print $1}' | head -1
}

#
# Main Color Mode Functions
#

set_color_mode() {
    local mode="$1"
    
    init_platform
    
    local result=1
    
    case "$DRIVER" in
        legacy|fkms)
            # FKMS: tweakvec is required for PAL60
            if _apply_tweakvec "$mode"; then
                result=0
            else
                echo ""
                echo "Note: PAL60 on FKMS requires tweakvec." >&2
                echo "Install with: $0 install-tweakvec" >&2
                echo ""
                echo "Without tweakvec, color options are limited to:" >&2
                echo "  - Edit config.txt sdtv_mode (requires reboot)" >&2
                echo "  - sdtv_mode=0 (NTSC), =2 (PAL), =4 (PAL-M)" >&2
                return 1
            fi
            ;;
        kms)
            if _apply_kms "$mode"; then
                result=0
            fi
            ;;
        *)
            echo "Error: Unknown driver '$DRIVER'" >&2
            return 1
            ;;
    esac
    
    if [[ $result -eq 0 ]]; then
        echo "$mode" > "$COLOR_STATE_FILE"
        echo "Color mode set to: $mode"
    fi
    
    return $result
}

get_color_mode() {
    if [[ -f "$COLOR_STATE_FILE" ]]; then
        cat "$COLOR_STATE_FILE"
    else
        echo "unknown"
    fi
}

#
# Automatic PAL60 for Emulators
# Call this before launching RetroArch to set PAL60
#

setup_pal60_for_game() {
    init_platform
    
    # Only apply if we're on FKMS with tweakvec
    if [[ "$DRIVER" != "fkms" ]] && [[ "$DRIVER" != "legacy" ]]; then
        return 0
    fi
    
    if ! find_tweakvec &>/dev/null; then
        echo "Warning: tweakvec not installed, skipping PAL60 setup" >&2
        return 0
    fi
    
    set_color_mode "pal60"
}

#
# Status and Info
#

print_color_status() {
    init_platform
    
    echo "Driver: $DRIVER"
    echo "Current color mode: $(get_color_mode)"
    echo ""
    
    local tweakvec_path=$(find_tweakvec 2>/dev/null)
    if [[ -n "$tweakvec_path" ]]; then
        echo "tweakvec: $tweakvec_path"
    else
        echo "tweakvec: not installed"
        if [[ "$DRIVER" == "fkms" ]] || [[ "$DRIVER" == "legacy" ]]; then
            echo "  (Required for PAL60 on $DRIVER driver)"
        fi
    fi
    
    echo ""
    echo "Available color modes:"
    case "$DRIVER" in
        legacy|fkms)
            if [[ -n "$tweakvec_path" ]]; then
                echo "  PAL60    - PAL color on 525-line (60Hz) - recommended for retro gaming"
                echo "  NTSC     - Standard NTSC (3.58 MHz subcarrier)"
                echo "  NTSC-J   - Japanese NTSC (no pedestal)"
                echo "  PAL      - Standard PAL (625-line, 50Hz)"
                echo "  PAL-M    - Brazilian PAL (525-line, different subcarrier)"
                echo "  PAL-N    - Argentine PAL"
                echo "  NTSC443  - NTSC with PAL subcarrier"
                echo "  SECAM    - French/Russian standard"
            else
                echo "  (Install tweakvec for runtime color switching)"
            fi
            ;;
        kms)
            echo "  NTSC     - Standard NTSC"
            echo "  PAL      - Standard PAL (use with 480i for PAL60-like output)"
            echo "  PAL-M    - Brazilian PAL (closest to PAL60 without tweakvec)"
            echo "  PAL-N    - Argentine PAL"
            echo "  NTSC443  - NTSC with PAL subcarrier"
            echo "  SECAM    - French/Russian standard"
            ;;
    esac
}

#
# CLI Interface
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        pal60|PAL60|ntsc|NTSC|ntsc-j|NTSC-J|pal|PAL|pal-m|PAL-M|pal-n|PAL-N|secam|SECAM|ntsc443|NTSC443)
            set_color_mode "$1"
            ;;
        status|get)
            print_color_status
            ;;
        install-tweakvec|install)
            install_tweakvec
            ;;
        setup-game)
            setup_pal60_for_game
            ;;
        *)
            echo "Usage: $0 <command>"
            echo ""
            echo "Color modes:"
            echo "  pal60         Set PAL60 color encoding (recommended for retro gaming)"
            echo "  ntsc          Set NTSC color encoding"
            echo "  pal           Set PAL color encoding"
            echo "  (and others: ntsc-j, pal-m, pal-n, secam, ntsc443)"
            echo ""
            echo "Other commands:"
            echo "  status        Show color mode status and available options"
            echo "  install       Install tweakvec (required for PAL60 on FKMS)"
            echo "  setup-game    Auto-setup PAL60 for game launch"
            exit 1
            ;;
    esac
fi
