#!/bin/bash
#
# Pi CRT Toolkit - Video Control (VEC Direct Access)
#
# Controls the Video Encoder Core directly via /dev/mem
# Works on ALL drivers: Legacy, FKMS, KMS
#
# Architecture:
#   - Pi 4 and earlier: BCM2711/BCM2835 VEC at 0x7ec13000 (VC4)
#   - Pi 5: RP1 VEC (different registers, TODO)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh" 2>/dev/null || true

# VEC register addresses (Pi 4 and earlier)
VEC_BASE_VC4="0x7ec13000"
VEC_CONFIG2_OFFSET="0x18c"
PROG_SCAN_BIT="0x00008000"

# Tweakvec path
TWEAKVEC=""
for path in "/opt/crt-toolkit/lib/tweakvec/tweakvec.py" "/home/pi/tweakvec/tweakvec.py"; do
    [[ -f "$path" ]] && TWEAKVEC="$path" && break
done

#
# Hardware detection
#

get_vec_generation() {
    # Detect which VEC hardware we have
    local model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    
    if [[ "$model" == *"Pi 5"* ]]; then
        echo "rp1"  # Pi 5 has RP1 chip with different VEC
    else
        echo "vc4"  # Pi 4 and earlier use VideoCore VEC
    fi
}

#
# Direct VEC register access (Pi 4 and earlier)
#

# Read a VEC register
vec_read_reg() {
    local offset="$1"
    local addr=$((VEC_BASE_VC4 + offset))
    
    # Use devmem2 if available, otherwise python
    if command -v devmem2 &>/dev/null; then
        devmem2 $addr w 2>/dev/null | grep -oE '0x[0-9A-Fa-f]+' | tail -1
    else
        python3 -c "
import mmap, os, struct
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, offset=$VEC_BASE_VC4)
val = struct.unpack('<I', m[$offset:$offset+4])[0]
print(f'0x{val:08x}')
m.close()
os.close(fd)
" 2>/dev/null
    fi
}

# Write a VEC register
vec_write_reg() {
    local offset="$1"
    local value="$2"
    local addr=$((VEC_BASE_VC4 + offset))
    
    if command -v devmem2 &>/dev/null; then
        devmem2 $addr w $value &>/dev/null
    else
        python3 -c "
import mmap, os, struct
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, offset=$VEC_BASE_VC4)
m[$offset:$offset+4] = struct.pack('<I', $value)
m.close()
os.close(fd)
" 2>/dev/null
    fi
}

#
# Progressive/Interlaced control
#

# Get current scan mode
get_scan_mode() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            local config2=$(vec_read_reg 0x18c)
            config2=$((config2))  # Convert to int
            if (( config2 & 0x8000 )); then
                echo "progressive"
            else
                echo "interlaced"
            fi
            ;;
        rp1)
            echo "unknown"  # TODO: Pi 5 support
            ;;
    esac
}

# Set progressive scan (240p/288p)
set_progressive() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            local config2=$(vec_read_reg 0x18c)
            config2=$((config2))
            config2=$((config2 | 0x8000))  # Set PROG_SCAN bit
            vec_write_reg 0x18c $config2
            echo "Progressive scan enabled"
            ;;
        rp1)
            echo "Error: Pi 5 not yet supported"
            return 1
            ;;
    esac
}

# Set interlaced scan (480i/576i)  
set_interlaced() {
    local gen=$(get_vec_generation)
    
    case "$gen" in
        vc4)
            local config2=$(vec_read_reg 0x18c)
            config2=$((config2))
            config2=$((config2 & ~0x8000))  # Clear PROG_SCAN bit
            vec_write_reg 0x18c $config2
            echo "Interlaced scan enabled"
            ;;
        rp1)
            echo "Error: Pi 5 not yet supported"
            return 1
            ;;
    esac
}

# Toggle between progressive and interlaced
toggle_scan() {
    local current=$(get_scan_mode)
    if [[ "$current" == "progressive" ]]; then
        set_interlaced
    else
        set_progressive
    fi
}

#
# Color mode control (via tweakvec)
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
    
    sudo python3 "$TWEAKVEC" --preset "$preset"
    echo "$mode" > /tmp/crt-toolkit-color 2>/dev/null || true
    echo "Color mode set to $preset"
}

get_color_mode() {
    # Try to read from our state file
    if [[ -f /tmp/crt-toolkit-color ]]; then
        cat /tmp/crt-toolkit-color
    else
        echo "unknown"
    fi
}

#
# Combined mode setting
#

# Set video mode: 240p, 480i, 288p, 576i
set_video_mode() {
    local mode="$1"
    
    case "$mode" in
        240p)
            set_progressive
            ;;
        480i)
            set_interlaced
            ;;
        288p)
            set_progressive
            ;;
        576i)
            set_interlaced
            ;;
        *)
            echo "Unknown mode: $mode"
            echo "Available: 240p, 480i, 288p, 576i"
            return 1
            ;;
    esac
}

#
# Status display
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
    
    if [[ "$gen" == "vc4" ]]; then
        local config2=$(vec_read_reg 0x18c)
        echo "VEC Config2: $config2"
    fi
}

#
# CLI Interface
#

show_help() {
    cat << 'EOF'
Pi CRT Toolkit - Video Control

Direct VEC hardware control via /dev/mem
Works on ALL drivers: Legacy, FKMS, KMS

Usage: video.sh <command> [args]

Scan Mode (240p/480i toggle):
  progressive, 240p    Enable progressive scan
  interlaced, 480i     Enable interlaced scan
  toggle               Toggle between progressive/interlaced

Color Mode (via tweakvec):
  pal60                PAL60 (US/JP consoles on PAL TVs)
  ntsc                 Standard NTSC
  pal                  Standard PAL
  ntsc-j               Japanese NTSC (no pedestal)

Status:
  status               Show current video status
  scan                 Show current scan mode only
  color                Show current color mode only

Examples:
  video.sh 240p        # Switch to progressive (240p)
  video.sh 480i        # Switch to interlaced (480i)
  video.sh pal60       # Set PAL60 color encoding
  video.sh toggle      # Toggle progressive/interlaced
  video.sh status      # Show full status

Hardware Support:
  Pi 4 and earlier: Full support (VC4 VEC)
  Pi 5: Not yet supported (RP1 VEC - different registers)
EOF
}

# Main CLI handler
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Need root for /dev/mem access
    if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "status" ]] && [[ "${1:-}" != "scan" ]] && [[ "${1:-}" != "color" ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "help" ]]; then
        exec sudo "$0" "$@"
    fi
    
    case "${1:-}" in
        # Scan modes
        progressive|240p|288p)
            set_progressive
            ;;
        interlaced|480i|576i)
            set_interlaced
            ;;
        toggle)
            toggle_scan
            ;;
        
        # Color modes
        pal60|pal|ntsc|ntsc-j|ntsc-443|ntsc443|pal-m|pal-n|secam)
            set_color_mode "$1"
            ;;
        color)
            if [[ -n "$2" ]]; then
                set_color_mode "$2"
            else
                get_color_mode
            fi
            ;;
        
        # Status
        status)
            print_status
            ;;
        scan)
            get_scan_mode
            ;;
        
        # Help
        --help|-h|help)
            show_help
            ;;
        
        *)
            echo "Usage: video.sh <240p|480i|toggle|pal60|ntsc|status|help>"
            echo "Run 'video.sh help' for full usage"
            exit 1
            ;;
    esac
fi
