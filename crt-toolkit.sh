#!/bin/bash
#
# Pi CRT Toolkit
# A menu-driven setup utility for CRT TV output via composite video
#
# Supports:
#   - Raspberry Pi 4 (and earlier with composite)
#   - Raspbian Buster, Bullseye, Bookworm
#   - Legacy, FKMS, and KMS graphics drivers
#

VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load library modules
LIB_DIR="$SCRIPT_DIR/lib"
[[ -f "$LIB_DIR/platform.sh" ]] && source "$LIB_DIR/platform.sh"
[[ -f "$LIB_DIR/video.sh" ]] && source "$LIB_DIR/video.sh"
[[ -f "$LIB_DIR/color.sh" ]] && source "$LIB_DIR/color.sh"
[[ -f "$LIB_DIR/boot.sh" ]] && source "$LIB_DIR/boot.sh"
[[ -f "$LIB_DIR/hotkeys.sh" ]] && source "$LIB_DIR/hotkeys.sh"

# Fallback if lib not available
if ! declare -f init_platform &>/dev/null; then
    init_platform() {
        OS_GENERATION="unknown"
        DRIVER="unknown"
        PI_MODEL="unknown"
    }
fi

# Config
CONFIG_DIR="/etc/crt-toolkit"
CONFIG_FILE="$CONFIG_DIR/config"

# User preferences (saved to config)
COLOR_MODE="pal60"
BOOT_MODE="ntsc480i"

#
# Check dependencies
#

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (sudo)"
        exit 1
    fi
}

check_deps() {
    local missing=()
    
    if ! command -v dialog &>/dev/null; then
        missing+=("dialog")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Installing dependencies: ${missing[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing[@]}"
    fi
}

#
# Config management
#

load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
# Pi CRT Toolkit Configuration
# Generated: $(date)
COLOR_MODE="$COLOR_MODE"
BOOT_MODE="$BOOT_MODE"
EOF
}

#
# RetroPie Integration
#

is_retropie() {
    [[ -d "/opt/retropie" ]]
}

install_retropie_integration() {
    if ! is_retropie; then
        echo "RetroPie not detected"
        return 1
    fi
    
    echo "Installing RetroPie integration..."
    
    # runcommand-onstart.sh
    cat > /opt/retropie/configs/all/runcommand-onstart.sh << 'SCRIPT'
#!/bin/bash
# Pi CRT Toolkit - Switch to 240p for emulators

# Load 480i exception list
interlaced=""
if [ -f "/opt/retropie/configs/$1/480i.txt" ]; then
    interlaced=$(tr -d "\r" < "/opt/retropie/configs/$1/480i.txt")
fi

# Check if game should be 480i
force_480i=false
if echo "$interlaced" | grep -qxi "all"; then
    force_480i=true
elif [[ -n "$interlaced" ]] && echo "$3" | grep -qwi "$interlaced"; then
    force_480i=true
fi

# Switch mode
if ! $force_480i && tvservice -s 2>/dev/null | grep -q NTSC; then
    /usr/local/bin/crt-240p
fi > /dev/null 2>&1
SCRIPT
    chmod +x /opt/retropie/configs/all/runcommand-onstart.sh
    
    # runcommand-onend.sh
    cat > /opt/retropie/configs/all/runcommand-onend.sh << 'SCRIPT'
#!/bin/bash
# Pi CRT Toolkit - Switch back to 480i
if tvservice -s 2>/dev/null | grep -q NTSC; then
    /usr/local/bin/crt-480i
fi > /dev/null 2>&1
SCRIPT
    chmod +x /opt/retropie/configs/all/runcommand-onend.sh
    
    echo "RetroPie integration installed"
}

#
# Menu System
#

show_main_menu() {
    while true; do
        init_platform
        
        local retropie_item=""
        is_retropie && retropie_item="6 \"RetroPie Integration\""
        
        local choice
        choice=$(dialog --clear --backtitle "Pi CRT Toolkit v$VERSION | $OS_CODENAME | $DRIVER driver | $PI_MODEL" \
            --title "Main Menu" \
            --menu "Choose an option:" 18 65 10 \
            1 "Quick Setup (Recommended)" \
            2 "Video Mode Settings" \
            3 "Color Mode Settings" \
            4 "Boot Configuration" \
            5 "Install Global Hotkeys" \
            $retropie_item \
            7 "Test Video Modes" \
            8 "System Information" \
            9 "Uninstall" \
            0 "Exit" \
            2>&1 >/dev/tty)
        
        case $choice in
            1) quick_setup_menu ;;
            2) video_mode_menu ;;
            3) color_mode_menu ;;
            4) boot_config_menu ;;
            5) hotkeys_menu ;;
            6) retropie_menu ;;
            7) test_modes_menu ;;
            8) system_info_menu ;;
            9) uninstall_menu ;;
            0|"") clear; exit 0 ;;
        esac
    done
}

quick_setup_menu() {
    # Step 1: Color preference
    local color_choice
    color_choice=$(dialog --clear --backtitle "Pi CRT Toolkit - Quick Setup (1/2)" \
        --title "Color Mode" \
        --menu "Select your preferred color encoding:\n\nPAL60 provides better color on most CRTs.\nUse NTSC only if you have color issues." 15 65 4 \
        1 "PAL60 (Recommended for most TVs)" \
        2 "Pure NTSC" \
        3 "I don't know (defaults to PAL60)" \
        2>&1 >/dev/tty)
    
    case $color_choice in
        1|3) COLOR_MODE="pal60" ;;
        2)   COLOR_MODE="ntsc" ;;
        *)   return ;;
    esac
    
    # Step 2: Boot resolution
    local boot_choice
    boot_choice=$(dialog --clear --backtitle "Pi CRT Toolkit - Quick Setup (2/2)" \
        --title "Default Resolution" \
        --menu "Select your default/boot resolution:\n\nHigher framerate (60Hz) = smoother motion\nHigher resolution (576) = more detail" 18 65 6 \
        1 "Prefer Higher Framerate (60Hz NTSC)" \
        2 "Prefer Higher Resolution (50Hz PAL)" \
        3 "720x480 @ 60Hz - NTSC 480i" \
        4 "720x480 @ 60Hz - NTSC 240p" \
        5 "720x576 @ 50Hz - PAL 576i" \
        6 "720x576 @ 50Hz - PAL 288p" \
        2>&1 >/dev/tty)
    
    case $boot_choice in
        1|3) BOOT_MODE="ntsc480i" ;;
        4)   BOOT_MODE="ntsc240p" ;;
        2|5) BOOT_MODE="pal576i" ;;
        6)   BOOT_MODE="pal288p" ;;
        *)   return ;;
    esac
    
    # Confirmation
    local retropie_msg=""
    is_retropie && retropie_msg="\n• RetroPie auto-switching (240p for games)"
    
    dialog --clear --backtitle "Pi CRT Toolkit - Quick Setup" \
        --title "Confirm Installation" \
        --yesno "Ready to install with these settings:\n\nColor Mode: $COLOR_MODE\nBoot Mode: $BOOT_MODE\n\nThis will install:\n• Video mode scripts (crt-240p, etc)\n• Global hotkeys (F7-F12)\n• Boot configuration$retropie_msg\n\nProceed with installation?" 18 60
    
    if [[ $? -eq 0 ]]; then
        clear
        echo "========================================"
        echo "  Pi CRT Toolkit - Installing"
        echo "========================================"
        echo ""
        
        save_config
        
        echo "[1/4] Installing video/color scripts..."
        if declare -f install_scripts &>/dev/null; then
            install_scripts
        fi
        
        echo ""
        echo "[2/4] Installing hotkeys..."
        if declare -f install_hotkeys &>/dev/null; then
            install_hotkeys
        fi
        
        echo ""
        echo "[3/4] Configuring boot settings..."
        if declare -f apply_boot_config &>/dev/null; then
            apply_boot_config "$BOOT_MODE"
        fi
        
        if is_retropie; then
            echo ""
            echo "[4/4] Installing RetroPie integration..."
            install_retropie_integration
        fi
        
        echo ""
        echo "========================================"
        echo "  Installation Complete!"
        echo "========================================"
        echo ""
        echo "Hotkeys:"
        echo "  F7  = PAL60 color"
        echo "  F8  = NTSC color"
        echo "  F9  = 240p"
        echo "  F10 = 480i"
        echo "  F11 = 288p (PAL)"
        echo "  F12 = 576i (PAL)"
        echo ""
        echo "Please REBOOT to apply boot settings."
        echo ""
        read -p "Press Enter to continue..."
    fi
}

video_mode_menu() {
    local current=$(get_video_mode 2>/dev/null || echo "unknown")
    
    local choice
    choice=$(dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Video Mode" \
        --menu "Current mode: $current\n\nSwitch video mode (takes effect immediately):" 14 55 4 \
        "240p" "NTSC 720x480 Progressive (60Hz)" \
        "480i" "NTSC 720x480 Interlaced (60Hz)" \
        "288p" "PAL 720x576 Progressive (50Hz)" \
        "576i" "PAL 720x576 Interlaced (50Hz)" \
        2>&1 >/dev/tty)
    
    if [[ -n "$choice" ]]; then
        clear
        echo "Switching to $choice..."
        if declare -f set_video_mode &>/dev/null; then
            set_video_mode "$choice"
        else
            # Fallback
            case "$choice" in
                240p) tvservice -c "NTSC 4:3 P" ;;
                480i) tvservice -c "NTSC 4:3" ;;
                288p) tvservice -c "PAL 4:3 P" ;;
                576i) tvservice -c "PAL 4:3" ;;
            esac
            fbset -depth 8 && fbset -depth 16
        fi
        sleep 1
    fi
}

color_mode_menu() {
    local current=$(get_color_mode 2>/dev/null || echo "unknown")
    
    local choice
    choice=$(dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Color Mode" \
        --menu "Current: $current\n\nSelect color encoding:" 12 55 3 \
        "pal60" "PAL60 (Better color on most CRTs)" \
        "ntsc"  "Pure NTSC" \
        2>&1 >/dev/tty)
    
    if [[ -n "$choice" ]]; then
        COLOR_MODE="$choice"
        save_config
        
        clear
        echo "Applying $choice color mode..."
        if declare -f set_color_mode &>/dev/null; then
            set_color_mode "$choice"
        fi
        sleep 1
    fi
}

boot_config_menu() {
    local choice
    choice=$(dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Boot Configuration" \
        --menu "Current: $BOOT_MODE\n\nSelect default boot mode:" 14 55 4 \
        "ntsc480i" "NTSC 480i (720x480 @ 60Hz interlaced)" \
        "ntsc240p" "NTSC 240p (720x448 @ 60Hz progressive)" \
        "pal576i"  "PAL 576i (720x576 @ 50Hz interlaced)" \
        "pal288p"  "PAL 288p (720x576 @ 50Hz progressive)" \
        2>&1 >/dev/tty)
    
    if [[ -n "$choice" ]]; then
        BOOT_MODE="$choice"
        save_config
        
        clear
        echo "Updating boot configuration..."
        if declare -f apply_boot_config &>/dev/null; then
            apply_boot_config "$BOOT_MODE"
        fi
        
        dialog --msgbox "Boot configuration updated.\n\nPlease REBOOT to apply changes." 8 45
    fi
}

hotkeys_menu() {
    dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Install Global Hotkeys" \
        --yesno "This will install global keyboard hotkeys:\n\n  F7  = PAL60 color\n  F8  = NTSC color\n  F9  = 240p\n  F10 = 480i\n  F11 = 288p (PAL)\n  F12 = 576i (PAL)\n\nHotkeys work in terminal, games, everywhere.\n\nProceed?" 17 50
    
    if [[ $? -eq 0 ]]; then
        clear
        if declare -f install_hotkeys &>/dev/null; then
            install_hotkeys
        else
            echo "Error: Hotkey module not loaded"
        fi
        read -p "Press Enter to continue..."
    fi
}

retropie_menu() {
    if ! is_retropie; then
        dialog --msgbox "RetroPie is not installed on this system." 6 50
        return
    fi
    
    local choice
    choice=$(dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "RetroPie Integration" \
        --menu "Configure RetroPie CRT settings:" 12 55 3 \
        1 "Install/Update Integration" \
        2 "Configure 480i Game Exceptions" \
        3 "View Current Configuration" \
        2>&1 >/dev/tty)
    
    case $choice in
        1)
            clear
            install_retropie_integration
            read -p "Press Enter to continue..."
            ;;
        2)
            dialog --msgbox "To force 480i for specific games:\n\nCreate a file:\n/opt/retropie/configs/<system>/480i.txt\n\nAdd game names (one per line):\nBloody Roar 2.pbp\nGran Turismo.bin\n\nOr use 'all' to force 480i for entire system." 14 55
            ;;
        3)
            local msg="runcommand-onstart.sh: "
            [[ -f /opt/retropie/configs/all/runcommand-onstart.sh ]] && msg+="installed" || msg+="not found"
            msg+="\nruncommand-onend.sh: "
            [[ -f /opt/retropie/configs/all/runcommand-onend.sh ]] && msg+="installed" || msg+="not found"
            dialog --msgbox "$msg" 8 50
            ;;
    esac
}

test_modes_menu() {
    local choice
    choice=$(dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Test Video Modes" \
        --menu "Select a mode to test (changes immediately):" 14 50 6 \
        1 "240p (NTSC Progressive)" \
        2 "480i (NTSC Interlaced)" \
        3 "288p (PAL Progressive)" \
        4 "576i (PAL Interlaced)" \
        5 "PAL60 Color" \
        6 "NTSC Color" \
        2>&1 >/dev/tty)
    
    clear
    case $choice in
        1) echo "Switching to 240p..."; tvservice -c "NTSC 4:3 P" 2>/dev/null; fbset -depth 8 && fbset -depth 16 ;;
        2) echo "Switching to 480i..."; tvservice -c "NTSC 4:3" 2>/dev/null; fbset -depth 8 && fbset -depth 16 ;;
        3) echo "Switching to 288p..."; tvservice -c "PAL 4:3 P" 2>/dev/null; fbset -depth 8 && fbset -depth 16 ;;
        4) echo "Switching to 576i..."; tvservice -c "PAL 4:3" 2>/dev/null; fbset -depth 8 && fbset -depth 16 ;;
        5) echo "Applying PAL60..."; set_color_mode pal60 2>/dev/null ;;
        6) echo "Applying NTSC..."; set_color_mode ntsc 2>/dev/null ;;
        *) return ;;
    esac
    sleep 2
}

system_info_menu() {
    init_platform
    
    local tv_status=$(tvservice -s 2>/dev/null || echo "tvservice not available")
    local fb_info=$(fbset 2>/dev/null | grep geometry || echo "fbset not available")
    local color_mode=$(get_color_mode 2>/dev/null || echo "unknown")
    local retropie_status="Not installed"
    is_retropie && retropie_status="Installed"
    
    local driver_note=""
    case "$DRIVER" in
        legacy) driver_note="Full tvservice support" ;;
        fkms)   driver_note="tvservice available, limited fbset" ;;
        kms)    driver_note="No tvservice, DRM only" ;;
    esac
    
    dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "System Information" \
        --msgbox "Platform:\n  OS: $OS_ID $OS_VERSION_ID ($OS_CODENAME)\n  Pi Model: $PI_MODEL\n  Driver: $DRIVER ($driver_note)\n\nVideo Status:\n  $tv_status\n\nFramebuffer:\n  $fb_info\n\nSettings:\n  Color Mode: $color_mode\n  Boot Mode: $BOOT_MODE\n  RetroPie: $retropie_status" 20 65
}

uninstall_menu() {
    dialog --clear --backtitle "Pi CRT Toolkit" \
        --title "Uninstall" \
        --yesno "This will remove:\n\n• Video mode scripts\n• Hotkey configuration\n• Library files\n\nBoot config changes will NOT be removed.\n\nAre you sure?" 14 50
    
    if [[ $? -eq 0 ]]; then
        clear
        echo "Removing Pi CRT Toolkit..."
        
        # Remove scripts
        rm -f /usr/local/bin/crt-{240p,480i,288p,576i,pal60,ntsc}
        
        # Remove hotkey config
        rm -f /etc/triggerhappy/triggers.d/crt-toolkit.conf
        rm -f /etc/systemd/system/triggerhappy.service.d/override.conf
        
        # Remove library
        rm -rf /usr/local/lib/crt-toolkit
        
        # Remove config
        rm -rf "$CONFIG_DIR"
        
        # Restart triggerhappy
        systemctl daemon-reload
        systemctl restart triggerhappy 2>/dev/null
        
        echo ""
        echo "Pi CRT Toolkit removed."
        echo "Note: Boot config in $(get_config_path) was not modified."
        read -p "Press Enter to continue..."
    fi
}

#
# CLI Mode
#

show_help() {
    cat << EOF
Pi CRT Toolkit v$VERSION

Usage: $0 [command] [options]

Commands:
  (none)          Launch interactive menu
  --install       Quick install with prompts
  
  --240p          Switch to 240p mode
  --480i          Switch to 480i mode
  --288p          Switch to 288p (PAL) mode
  --576i          Switch to 576i (PAL) mode
  
  --pal60         Apply PAL60 color encoding
  --ntsc          Apply NTSC color encoding
  
  --status        Show current video/color status
  --info          Show system information
  --help          Show this help

Examples:
  sudo crt-toolkit              # Launch menu
  sudo crt-toolkit --240p       # Switch to 240p now
  sudo crt-toolkit --status     # Show current state
EOF
}

#
# Main Entry Point
#

main() {
    # Initialize platform detection
    init_platform 2>/dev/null
    
    case "${1:-}" in
        --install|-i)
            check_root
            check_deps
            load_config
            quick_setup_menu
            ;;
        --240p)
            set_video_mode 240p 2>/dev/null || { tvservice -c "NTSC 4:3 P"; fbset -depth 8 && fbset -depth 16; }
            ;;
        --480i)
            set_video_mode 480i 2>/dev/null || { tvservice -c "NTSC 4:3"; fbset -depth 8 && fbset -depth 16; }
            ;;
        --288p)
            set_video_mode 288p 2>/dev/null || { tvservice -c "PAL 4:3 P"; fbset -depth 8 && fbset -depth 16; }
            ;;
        --576i)
            set_video_mode 576i 2>/dev/null || { tvservice -c "PAL 4:3"; fbset -depth 8 && fbset -depth 16; }
            ;;
        --pal60)
            set_color_mode pal60 2>/dev/null
            ;;
        --ntsc)
            set_color_mode ntsc 2>/dev/null
            ;;
        --status|-s)
            echo "Video: $(get_video_mode 2>/dev/null || tvservice -s 2>/dev/null || echo 'unknown')"
            echo "Color: $(get_color_mode 2>/dev/null || echo 'unknown')"
            echo "Resolution: $(get_output_resolution 2>/dev/null || echo 'unknown')"
            ;;
        --info)
            print_platform_info 2>/dev/null || {
                echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
                echo "Model: $(cat /proc/device-tree/model 2>/dev/null)"
                echo "tvservice: $(tvservice -s 2>/dev/null || echo 'not available')"
            }
            ;;
        --help|-h)
            show_help
            ;;
        "")
            check_root
            check_deps
            load_config
            show_main_menu
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
