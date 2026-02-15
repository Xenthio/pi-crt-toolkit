#!/bin/bash
#
# Pi CRT Toolkit - OS and Driver Abstraction Layer
# Handles differences between Buster/Bullseye/Bookworm/Trixie and Legacy/FKMS/KMS
#

# Global state (cached after first detection)
OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""
OS_GENERATION=""
PI_MODEL=""
DRIVER=""
_PLATFORM_INITIALIZED=false

# Detect OS version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="$VERSION_ID"
        OS_CODENAME="$VERSION_CODENAME"
    else
        OS_ID="unknown"
        OS_VERSION_ID="0"
        OS_CODENAME="unknown"
    fi
    
    # Categorize by codename
    case "$OS_CODENAME" in
        buster)     OS_GENERATION="buster" ;;      # Debian 10 - Legacy driver default
        bullseye)   OS_GENERATION="bullseye" ;;    # Debian 11 - FKMS default
        bookworm)   OS_GENERATION="bookworm" ;;    # Debian 12 - Full KMS default
        trixie)     OS_GENERATION="trixie" ;;      # Debian 13 - Full KMS only
        *)          OS_GENERATION="unknown" ;;
    esac
    
    export OS_ID OS_VERSION_ID OS_CODENAME OS_GENERATION
}

# Detect graphics driver
detect_driver() {
    local config_file
    config_file=$(get_config_path)
    
    # Check config.txt for overlay (ignoring comments)
    local has_fkms=0
    local has_kms=0
    
    if [[ -f "$config_file" ]]; then
        has_fkms=$(grep -cE "^dtoverlay=vc4-fkms-v3d" "$config_file" 2>/dev/null || echo 0)
        has_kms=$(grep -cE "^dtoverlay=vc4-kms-v3d" "$config_file" 2>/dev/null || echo 0)
    fi
    
    # Check if tvservice works (legacy/fkms indicator)
    local has_tvservice=false
    if command -v tvservice &>/dev/null; then
        if tvservice -s &>/dev/null; then
            has_tvservice=true
        fi
    fi
    
    # Determine driver
    if [[ "$has_fkms" -gt 0 ]]; then
        DRIVER="fkms"
    elif [[ "$has_kms" -gt 0 ]]; then
        DRIVER="kms"
    elif [[ "$has_tvservice" == "true" ]]; then
        # No explicit overlay but tvservice works -> legacy
        DRIVER="legacy"
    else
        DRIVER="unknown"
    fi
    
    export DRIVER
}

# Detect Pi model
detect_pi_model() {
    PI_MODEL="unknown"
    
    if [[ -f /proc/device-tree/model ]]; then
        local model=$(tr -d '\0' < /proc/device-tree/model)
        case "$model" in
            *"Pi 5"*)      PI_MODEL="pi5" ;;
            *"Pi 4"*)      PI_MODEL="pi4" ;;
            *"Pi 3"*)      PI_MODEL="pi3" ;;
            *"Pi 2"*)      PI_MODEL="pi2" ;;
            *"Pi Zero 2"*) PI_MODEL="pi02" ;;
            *"Pi Zero"*)   PI_MODEL="pi0" ;;
            *)             PI_MODEL="unknown" ;;
        esac
    fi
    
    export PI_MODEL
}

# Check feature support
supports_feature() {
    local feature="$1"
    
    case "$feature" in
        composite)
            # Pi 4 and earlier have composite, Pi 5 does not
            [[ "$PI_MODEL" != "pi5" ]]
            ;;
        tvservice)
            # tvservice works on legacy and fkms, not full kms
            [[ "$DRIVER" == "legacy" ]] || [[ "$DRIVER" == "fkms" ]]
            ;;
        drm_tv_mode)
            # DRM "TV mode" property for runtime color switching (KMS only)
            [[ "$DRIVER" == "kms" ]] && [[ -e /dev/dri/card1 ]]
            ;;
        cmdline_tv_norm)
            # Kernel cmdline vc4.tv_norm for boot-time color
            [[ "$DRIVER" == "fkms" ]] || [[ "$DRIVER" == "kms" ]]
            ;;
        fbset_resize)
            # fbset can resize framebuffer on legacy driver
            [[ "$DRIVER" == "legacy" ]]
            ;;
        tweakvec)
            # tweakvec needs legacy or fkms (direct VEC register access via /dev/mem)
            [[ "$DRIVER" == "legacy" ]] || [[ "$DRIVER" == "fkms" ]]
            ;;
        dtoverlay_composite)
            # Bookworm/Trixie: need dtoverlay=vc4-kms-v3d,composite
            # Earlier: use enable_tvout=1
            [[ "$OS_GENERATION" == "bookworm" ]] || [[ "$OS_GENERATION" == "trixie" ]]
            ;;
        runtime_mode_switch)
            # Can switch video modes at runtime
            [[ "$DRIVER" == "legacy" ]] || [[ "$DRIVER" == "fkms" ]] || [[ "$DRIVER" == "kms" ]]
            ;;
    esac
}

# Get config.txt path (differs on Bookworm+)
get_config_path() {
    if [[ -f "/boot/firmware/config.txt" ]]; then
        echo "/boot/firmware/config.txt"
    else
        echo "/boot/config.txt"
    fi
}

# Get cmdline.txt path
get_cmdline_path() {
    if [[ -f "/boot/firmware/cmdline.txt" ]]; then
        echo "/boot/firmware/cmdline.txt"
    else
        echo "/boot/cmdline.txt"
    fi
}

# Initialize all detection (cached)
init_platform() {
    if [[ "$_PLATFORM_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    detect_os
    detect_pi_model
    detect_driver
    
    _PLATFORM_INITIALIZED=true
}

# Print platform info
print_platform_info() {
    init_platform
    
    echo "OS: $OS_ID $OS_VERSION_ID ($OS_CODENAME)"
    echo "Pi Model: $PI_MODEL"
    echo "Driver: $DRIVER"
    echo "Config: $(get_config_path)"
    echo ""
    echo "Feature Support:"
    echo "  Composite output:      $(supports_feature composite && echo 'Yes' || echo 'No')"
    echo "  tvservice:             $(supports_feature tvservice && echo 'Yes' || echo 'No')"
    echo "  DRM TV mode property:  $(supports_feature drm_tv_mode && echo 'Yes' || echo 'No')"
    echo "  tweakvec (PAL60):      $(supports_feature tweakvec && echo 'Yes' || echo 'No')"
    echo "  Runtime mode switch:   $(supports_feature runtime_mode_switch && echo 'Yes' || echo 'No')"
    
    if [[ "$DRIVER" == "fkms" ]]; then
        echo ""
        echo "FKMS Driver Notes:"
        echo "  - Use tvservice for mode switching"
        echo "  - Use tweakvec for PAL60 color encoding"
        echo "  - Best choice for CRT + RetroPie"
    elif [[ "$DRIVER" == "kms" ]]; then
        echo ""
        echo "KMS Driver Notes:"
        echo "  - Use modetest/kms-switch for mode switching"
        echo "  - PAL60 via DRM TV mode property (limited)"
        echo "  - RetroPie compatibility may be limited"
    fi
}

# If run directly, print info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_platform_info
fi
