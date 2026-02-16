#!/bin/bash
#
# Pi CRT Toolkit - Video Control (VEC Direct Access)
#
# Controls the Video Encoder Core directly via /dev/mem
# Works on ALL drivers: Legacy, FKMS, KMS
#
# Architecture:
#   - Pi 4 and earlier: BCM2711/BCM2835 VEC (VC4)
#   - Pi 5: RP1 VEC (different registers, TODO)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tweakvec path - we use its proper address mapping
TWEAKVEC=""
for path in "/opt/crt-toolkit/lib/tweakvec/tweakvec.py" "/home/pi/tweakvec/tweakvec.py"; do
    [[ -f "$path" ]] && TWEAKVEC="$path" && break
done

TWEAKVEC_DIR=$(dirname "$TWEAKVEC" 2>/dev/null)

#
# Hardware detection
#

get_vec_generation() {
    local model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    
    if [[ "$model" == *"Pi 5"* ]]; then
        echo "rp1"
    else
        echo "vc4"
    fi
}

get_driver_mode() {
    # Detect which video driver is active
    if grep -qE "^dtoverlay=vc4-kms-v3d" /boot/firmware/config.txt 2>/dev/null || \
       grep -qE "^dtoverlay=vc4-kms-v3d" /boot/config.txt 2>/dev/null; then
        echo "kms"
    elif grep -qE "^dtoverlay=vc4-fkms-v3d" /boot/firmware/config.txt 2>/dev/null || \
         grep -qE "^dtoverlay=vc4-fkms-v3d" /boot/config.txt 2>/dev/null; then
        echo "fkms"
    elif tvservice -s &>/dev/null; then
        echo "legacy"
    else
        echo "unknown"
    fi
}

get_connector_id() {
    # Get the DRM connector ID for composite output
    cat /sys/class/drm/card?-Composite-1/connector_id 2>/dev/null | head -1
}

#
# VEC register access via tweakvec's proper address mapping
#

vec_python() {
    python3 << EOF
import sys, os
sys.path.insert(0, '$TWEAKVEC_DIR')
from tweakvec import ArmMemoryMapper, VecPixelValveAccessor, VecAccessor

mapper = ArmMemoryMapper()
memfd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
pv = VecPixelValveAccessor(memfd, mapper)
vec = VecAccessor(memfd, mapper, pv.model)

$1

os.close(memfd)
EOF
}

#
# Progressive/Interlaced control
#

get_scan_mode() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            vec_python 'print("progressive" if not (pv.v_control & 0x10) else "interlaced")'
            ;;
        rp1)
            echo "unknown"
            ;;
    esac
}

set_progressive() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            vec_python '
# Must set BOTH PixelValve and VEC for progressive to work
pv.v_control = pv.v_control & ~0x10   # Clear PV INTERLACE bit
vec.config2 = vec.config2 | 0x8000    # Set VEC PROG_SCAN bit
print("Progressive scan enabled (240p)")
'
            ;;
        rp1)
            echo "Error: Pi 5 not yet supported"
            return 1
            ;;
    esac
}

set_interlaced() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            vec_python '
# Must set BOTH PixelValve and VEC for interlaced to work
pv.v_control = pv.v_control | 0x10    # Set PV INTERLACE bit
vec.config2 = vec.config2 & ~0x8000   # Clear VEC PROG_SCAN bit
print("Interlaced scan enabled (480i)")
'
            ;;
        rp1)
            echo "Error: Pi 5 not yet supported"
            return 1
            ;;
    esac
}

toggle_scan() {
    local current=$(get_scan_mode)
    if [[ "$current" == "progressive" ]]; then
        set_interlaced
    else
        set_progressive
    fi
}

#
# Framebuffer resolution control
#

get_fb_height() {
    fbset -fb /dev/fb0 2>/dev/null | grep geometry | awk '{print $3}'
}

set_fb_240() {
    local driver=$(get_driver_mode)
    
    case "$driver" in
        kms)
            # KMS: Can't change framebuffer at runtime without DRM master
            # Boot resolution is set in cmdline.txt (video=Composite-1:720x480@60ie)
            # Only VEC scan mode is changed at runtime (see set_progressive)
            echo "KMS: Framebuffer resolution set at boot via cmdline.txt" >&2
            return 0
            ;;
        fkms|legacy)
            # FKMS/Legacy: fbset works
            fbset -fb /dev/fb0 -g 720 240 720 240 16 2>/dev/null
            ;;
        *)
            echo "Error: Unknown driver mode" >&2
            return 1
            ;;
    esac
}

set_fb_480() {
    local driver=$(get_driver_mode)
    
    case "$driver" in
        kms)
            # KMS: Can't change framebuffer at runtime without DRM master
            # Boot resolution is set in cmdline.txt (video=Composite-1:720x480@60ie)
            # Only VEC scan mode is changed at runtime (see set_interlaced)
            echo "KMS: Framebuffer resolution set at boot via cmdline.txt" >&2
            return 0
            ;;
        fkms|legacy)
            # FKMS/Legacy: fbset works
            fbset -fb /dev/fb0 -g 720 480 720 480 16 2>/dev/null
            ;;
        *)
            echo "Error: Unknown driver mode" >&2
            return 1
            ;;
    esac
}

#
# Full mode switch (framebuffer + scan mode)
#

set_mode_240p() {
    set_fb_240
    set_progressive
    echo "240p" > /tmp/crt-toolkit-mode 2>/dev/null || true
}

set_mode_480i() {
    set_fb_480
    set_interlaced
    echo "480i" > /tmp/crt-toolkit-mode 2>/dev/null || true
}

get_current_mode() {
    local height=$(get_fb_height)
    if [[ "$height" == "240" ]]; then
        echo "240p"
    else
        echo "480i"
    fi
}

toggle_mode() {
    local current=$(get_current_mode)
    if [[ "$current" == "240p" ]]; then
        set_mode_480i
        echo "Switched to 480i (720x480 interlaced)"
    else
        set_mode_240p
        echo "Switched to 240p (720x240 progressive)"
    fi
}

#
# Color mode control
#

set_color_mode() {
    local mode="$1"
    
    if [[ -z "$TWEAKVEC" ]]; then
        echo "Error: tweakvec not found"
        return 1
    fi
    
    local preset
    case "${mode,,}" in
        pal60)    preset="PAL60" ;;
        pal)      preset="PAL" ;;
        ntsc)     preset="NTSC" ;;
        ntsc-j)   preset="NTSC-J" ;;
        ntsc443)  preset="NTSC443" ;;
        pal-m)    preset="PAL-M" ;;
        pal-n)    preset="PAL-N" ;;
        secam)    preset="SECAM" ;;
        *)
            echo "Unknown color mode: $mode"
            echo "Available: pal60, pal, ntsc, ntsc-j, ntsc443, pal-m, pal-n, secam"
            return 1
            ;;
    esac
    
    python3 "$TWEAKVEC" --preset "$preset"
    echo "${mode,,}" > /tmp/crt-toolkit-color 2>/dev/null || true
    echo "Color mode set to $preset"
}

get_color_mode() {
    if [[ -f /tmp/crt-toolkit-color ]]; then
        cat /tmp/crt-toolkit-color
    else
        echo "unknown"
    fi
}

#
# Status
#

print_status() {
    local gen=$(get_vec_generation)
    local scan=$(get_scan_mode)
    local color=$(get_color_mode)
    
    echo "=== Pi CRT Toolkit - Video Status ==="
    echo "VEC Generation: $gen"
    echo "Scan Mode: $scan"
    echo "Color Mode: $color"
    echo "Tweakvec: ${TWEAKVEC:-not found}"
    
    if [[ "$gen" == "vc4" ]] && [[ -n "$TWEAKVEC" ]]; then
        vec_python 'print(f"VEC Config2: 0x{vec.config2:08x}")'
    fi
}

#
# CLI
#

show_help() {
    cat << 'EOF'
Pi CRT Toolkit - Video Control

Direct VEC hardware control via /dev/mem (uses tweakvec for address mapping)
Works on ALL drivers: Legacy, FKMS, KMS

Usage: video.sh <command> [args]

Scan Mode:
  progressive, 240p    Enable progressive scan (240p/288p)
  interlaced, 480i     Enable interlaced scan (480i/576i)
  toggle               Toggle between progressive/interlaced

Color Mode:
  pal60                PAL60 (US/JP consoles on PAL TVs)
  ntsc                 Standard NTSC
  pal                  Standard PAL
  ntsc-j               Japanese NTSC (no pedestal)

Status:
  status               Show current video status
  scan                 Show current scan mode only
  color                Show current color mode only

Examples:
  video.sh 240p        # Switch to progressive
  video.sh 480i        # Switch to interlaced
  video.sh pal60       # Set PAL60 color encoding
  video.sh toggle      # Toggle progressive/interlaced
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for tweakvec
    if [[ -z "$TWEAKVEC" ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "help" ]]; then
        echo "Error: tweakvec not found. Install it first:"
        echo "  git clone https://github.com/kFYatek/tweakvec /opt/crt-toolkit/lib/tweakvec"
        exit 1
    fi
    
    # Need root for /dev/mem
    if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "help" ]]; then
        exec sudo "$0" "$@"
    fi
    
    case "${1:-}" in
        progressive|240p|288p)  set_progressive ;;
        interlaced|480i|576i)   set_interlaced ;;
        toggle)                 toggle_scan ;;
        
        # Full mode switch (framebuffer + scan)
        mode-240p)              set_mode_240p ;;
        mode-480i)              set_mode_480i ;;
        toggle-mode)            toggle_mode ;;
        mode)                   get_current_mode ;;
        
        pal60|pal|ntsc|ntsc-j|ntsc443|pal-m|pal-n|secam)
            set_color_mode "$1"
            ;;
        color)
            [[ -n "$2" ]] && set_color_mode "$2" || get_color_mode
            ;;
        
        status)  print_status ;;
        scan)    get_scan_mode ;;
        
        --help|-h|help)  show_help ;;
        
        *)
            echo "Usage: video.sh <240p|480i|toggle|toggle-mode|pal60|ntsc|status|help>"
            exit 1
            ;;
    esac
fi
