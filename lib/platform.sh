#!/bin/bash
#
# Pi CRT Toolkit - OS and Driver Abstraction Layer
# Handles differences between Buster/Bullseye/Bookworm/Trixie and Legacy/FKMS/KMS
#

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
    
    # Categorize by major version
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
# Returns: legacy, fkms, kms, or unknown
detect_driver() {
    local config_file
    config_file=$(get_config_path)
    
    # Check what's loaded in kernel
    local has_vc4=$(lsmod | grep -c "^vc4" || echo 0)
    
    # Check config.txt for overlay (excluding comments)
    local has_fkms=$(grep -E "^dtoverlay=vc4-fkms-v3d" "$config_file" 2>/dev/null | wc -l || echo 0)
    local has_kms=$(grep -E "^dtoverlay=vc4-kms-v3d" "$config_file" 2>/dev/null | wc -l || echo 0)
    
    # Check for DRM devices
    local has_drm=false
    [[ -d /dev/dri ]] && has_drm=true
    
    # Check if tvservice exists and works (legacy/fkms only)
    local has_tvservice=false
    if command -v tvservice &>/dev/null; then
        if tvservice -s &>/dev/null; then
            has_tvservice=true
        fi
    fi
    
    # Determine driver
    if [[ "$has_fkms" -gt 0 ]] && [[ "$has_tvservice" == "true" ]]; then
        DRIVER="fkms"
    elif [[ "$has_kms" -gt 0 ]] || { [[ "$has_drm" == "true" ]] && [[ "$has_tvservice" != "true" ]]; }; then
        DRIVER="kms"
    elif [[ "$has_tvservice" == "true" ]]; then
        DRIVER="legacy"
    else
        DRIVER="unknown"
    fi
    
    export DRIVER
}

# Detect Pi model
detect_pi_model() {
    PI_MODEL="unknown"
    PI_REVISION=""
    
    if [[ -f /proc/device-tree/model ]]; then
        local model=$(tr -d '\0' < /proc/device-tree/model)
        case "$model" in
            *"Pi 5"*)   PI_MODEL="pi5" ;;
            *"Pi 4"*)   PI_MODEL="pi4" ;;
            *"Pi 3"*)   PI_MODEL="pi3" ;;
            *"Pi 2"*)   PI_MODEL="pi2" ;;
            *"Pi Zero 2"*) PI_MODEL="pi02" ;;
            *"Pi Zero"*) PI_MODEL="pi0" ;;
            *)          PI_MODEL="unknown" ;;
        esac
    fi
    
    export PI_MODEL PI_REVISION
}

# Check feature support
# Usage: supports_feature <feature>
# Features: composite, tvservice, drm_tv_mode, fbset_resize, cmdline_tv_norm
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
            # DRM "TV mode" property for runtime color switching (KMS only, kernel 6.3+)
            [[ "$DRIVER" == "kms" ]] && [[ -e /dev/dri/card0 ]]
            ;;
        cmdline_tv_norm)
            # Kernel cmdline vc4.tv_norm for boot-time color (kernel 5.10+)
            # Works on FKMS and KMS
            [[ "$DRIVER" == "fkms" ]] || [[ "$DRIVER" == "kms" ]]
            ;;
        fbset_resize)
            # fbset can resize on legacy driver only
            [[ "$DRIVER" == "legacy" ]]
            ;;
        tweakvec)
            # tweakvec needs legacy or fkms (direct VEC register access)
            [[ "$DRIVER" == "legacy" ]] || [[ "$DRIVER" == "fkms" ]]
            ;;
        dtoverlay_composite)
            # Trixie/Bookworm: need dtoverlay=vc4-kms-v3d,composite
            # Earlier: use enable_tvout=1
            [[ "$OS_GENERATION" == "bookworm" ]] || [[ "$OS_GENERATION" == "trixie" ]]
            ;;
    esac
}

# Get config.txt path (differs on Bookworm+)
# Bookworm/Trixie: /boot/firmware/config.txt
# Earlier: /boot/config.txt
get_config_path() {
    if [[ -f "/boot/firmware/config.txt" ]]; then
        echo "/boot/firmware/config.txt"
    else
        echo "/boot/config.txt"
    fi
}

# Get cmdline.txt path (differs on Bookworm+)
get_cmdline_path() {
    if [[ -f "/boot/firmware/cmdline.txt" ]]; then
        echo "/boot/firmware/cmdline.txt"
    else
        echo "/boot/cmdline.txt"
    fi
}

# Initialize detection
init_platform() {
    detect_os
    detect_pi_model
    detect_driver
}

# Print platform info
print_platform_info() {
    init_platform
    echo "OS: $OS_ID $OS_VERSION_ID ($OS_CODENAME) - Generation: $OS_GENERATION"
    echo "Pi Model: $PI_MODEL"
    echo "Driver: $DRIVER"
    echo "Config: $(get_config_path)"
    echo "Cmdline: $(get_cmdline_path)"
    echo ""
    echo "Feature Support:"
    echo "  Composite output:    $(supports_feature composite && echo 'Yes' || echo 'No')"
    echo "  tvservice:           $(supports_feature tvservice && echo 'Yes' || echo 'No')"
    echo "  DRM TV mode:         $(supports_feature drm_tv_mode && echo 'Yes' || echo 'No')"
    echo "  cmdline tv_norm:     $(supports_feature cmdline_tv_norm && echo 'Yes' || echo 'No')"
    echo "  fbset resize:        $(supports_feature fbset_resize && echo 'Yes' || echo 'No')"
    echo "  tweakvec:            $(supports_feature tweakvec && echo 'Yes' || echo 'No')"
    echo "  dtoverlay,composite: $(supports_feature dtoverlay_composite && echo 'Yes' || echo 'No')"
}

# If run directly, print info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_platform_info
fi
