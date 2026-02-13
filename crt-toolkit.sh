#!/bin/bash
#
# Pi CRT Toolkit
# Setup and configuration utility for CRT TV output via composite video
#
# Similar to retropie_setup.sh and raspi-config
#

VERSION="1.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install location (when installed)
INSTALL_DIR="/opt/crt-toolkit"

# Use installed lib if available, otherwise local
if [[ -d "$INSTALL_DIR/lib" ]]; then
    LIB_DIR="$INSTALL_DIR/lib"
elif [[ -d "$SCRIPT_DIR/lib" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    LIB_DIR=""
fi

# Load modules if available
[[ -n "$LIB_DIR" ]] && {
    [[ -f "$LIB_DIR/platform.sh" ]] && source "$LIB_DIR/platform.sh"
    [[ -f "$LIB_DIR/video.sh" ]] && source "$LIB_DIR/video.sh"
    [[ -f "$LIB_DIR/color.sh" ]] && source "$LIB_DIR/color.sh"
    [[ -f "$LIB_DIR/boot.sh" ]] && source "$LIB_DIR/boot.sh"
    [[ -f "$LIB_DIR/hotkeys.sh" ]] && source "$LIB_DIR/hotkeys.sh"
}

# Config
CONFIG_DIR="/etc/crt-toolkit"
CONFIG_FILE="$CONFIG_DIR/config"

# User preferences
COLOR_MODE="pal60"
BOOT_MODE="ntsc480i"

# Dialog dimensions
MENU_HEIGHT=20
MENU_WIDTH=70
LIST_HEIGHT=12

#
# Utility Functions
#

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        echo "Try: sudo $0"
        exit 1
    fi
}

# Install dialog if needed
ensure_dialog() {
    if ! command -v dialog &>/dev/null; then
        echo "Installing dialog..."
        apt-get update -qq
        apt-get install -y -qq dialog
    fi
}

# Load config
load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

# Save config
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
# Pi CRT Toolkit Configuration
COLOR_MODE="$COLOR_MODE"
BOOT_MODE="$BOOT_MODE"
EOF
}

# Check if toolkit is installed
is_installed() {
    [[ -d "$INSTALL_DIR" ]] && [[ -x "/usr/local/bin/crt-toolkit" ]]
}

# Check if RetroPie is installed
is_retropie() {
    [[ -d "/opt/retropie" ]]
}

# Initialize platform detection (with fallbacks)
init_platform() {
    if declare -f detect_os &>/dev/null; then
        detect_os
        detect_pi_model
        detect_driver
    else
        # Fallback detection
        OS_CODENAME=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2 || echo "unknown")
        PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null | grep -oE "Pi [0-9]+" | head -1 || echo "unknown")
        DRIVER="unknown"
        [[ -f /usr/bin/tvservice ]] && DRIVER="fkms"
    fi
}

#
# Installation Functions
#

do_install() {
    dialog --backtitle "Pi CRT Toolkit" \
        --title "Install CRT Toolkit" \
        --yesno "This will install:\n\n\
• Video mode scripts (crt-240p, crt-480i, etc)\n\
• Global hotkeys (F7-F12)\n\
• Boot configuration for composite output\n\
$(is_retropie && echo '• RetroPie integration (auto 240p for games)')\n\n\
Proceed with installation?" $MENU_HEIGHT 60
    
    [[ $? -ne 0 ]] && return
    
    # Run installation with progress
    (
        echo "10"; echo "# Installing scripts..."
        sleep 0.5
        
        # Install lib files
        mkdir -p "$INSTALL_DIR/lib" /usr/local/lib/crt-toolkit
        if [[ -d "$SCRIPT_DIR/lib" ]]; then
            cp "$SCRIPT_DIR/lib/"*.sh "$INSTALL_DIR/lib/" 2>/dev/null
            cp "$SCRIPT_DIR/lib/"*.sh /usr/local/lib/crt-toolkit/ 2>/dev/null
        fi
        
        echo "30"; echo "# Installing command scripts..."
        install_command_scripts
        
        echo "50"; echo "# Installing hotkeys..."
        install_hotkey_config
        
        echo "70"; echo "# Configuring boot..."
        configure_boot_settings
        
        if is_retropie; then
            echo "85"; echo "# Setting up RetroPie..."
            install_retropie_hooks
        fi
        
        echo "95"; echo "# Creating symlink..."
        cp "$SCRIPT_DIR/crt-toolkit.sh" "$INSTALL_DIR/" 2>/dev/null || true
        chmod +x "$INSTALL_DIR/crt-toolkit.sh"
        ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit
        
        echo "100"; echo "# Done!"
    ) | dialog --backtitle "Pi CRT Toolkit" \
        --title "Installing" \
        --gauge "Starting installation..." 8 60 0
    
    dialog --backtitle "Pi CRT Toolkit" \
        --title "Installation Complete" \
        --msgbox "CRT Toolkit has been installed!\n\n\
Hotkeys:\n\
  F7  = PAL60 color    F8  = NTSC color\n\
  F9  = 240p           F10 = 480i\n\
  F11 = 288p (PAL)     F12 = 576i (PAL)\n\n\
Please REBOOT to apply boot settings." $MENU_HEIGHT 55
}

install_command_scripts() {
    local script_dir="/usr/local/bin"
    
    # crt-240p
    cat > "$script_dir/crt-240p" << 'EOF'
#!/bin/bash
tvservice -c "NTSC 4:3 P" 2>/dev/null
fbset -depth 8 && fbset -depth 16
[[ "$(cat /tmp/crt-toolkit-color 2>/dev/null)" == "pal60" ]] && \
    python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
EOF
    
    # crt-480i
    cat > "$script_dir/crt-480i" << 'EOF'
#!/bin/bash
tvservice -c "NTSC 4:3" 2>/dev/null
fbset -depth 8 && fbset -depth 16
[[ "$(cat /tmp/crt-toolkit-color 2>/dev/null)" == "pal60" ]] && \
    python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
EOF
    
    # crt-288p
    cat > "$script_dir/crt-288p" << 'EOF'
#!/bin/bash
tvservice -c "PAL 4:3 P" 2>/dev/null
fbset -depth 8 && fbset -depth 16
EOF
    
    # crt-576i
    cat > "$script_dir/crt-576i" << 'EOF'
#!/bin/bash
tvservice -c "PAL 4:3" 2>/dev/null
fbset -depth 8 && fbset -depth 16
EOF
    
    # crt-pal60
    cat > "$script_dir/crt-pal60" << 'EOF'
#!/bin/bash
python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
echo "pal60" > /tmp/crt-toolkit-color
EOF
    
    # crt-ntsc
    cat > "$script_dir/crt-ntsc" << 'EOF'
#!/bin/bash
python3 /home/pi/tweakvec/tweakvec.py --preset NTSC 2>/dev/null
echo "ntsc" > /tmp/crt-toolkit-color
EOF
    
    chmod +x "$script_dir"/crt-{240p,480i,288p,576i,pal60,ntsc}
}

install_hotkey_config() {
    # Install triggerhappy if needed
    if ! command -v thd &>/dev/null; then
        apt-get install -y -qq triggerhappy
    fi
    
    # Create config
    mkdir -p /etc/triggerhappy/triggers.d
    cat > /etc/triggerhappy/triggers.d/crt-toolkit.conf << 'EOF'
# Pi CRT Toolkit Hotkeys
KEY_F7      1    /usr/local/bin/crt-pal60
KEY_F8      1    /usr/local/bin/crt-ntsc
KEY_F9      1    /usr/local/bin/crt-240p
KEY_F10     1    /usr/local/bin/crt-480i
KEY_F11     1    /usr/local/bin/crt-288p
KEY_F12     1    /usr/local/bin/crt-576i
EOF
    
    # Run as root
    mkdir -p /etc/systemd/system/triggerhappy.service.d
    cat > /etc/systemd/system/triggerhappy.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
EOF
    
    systemctl daemon-reload
    systemctl enable triggerhappy
    systemctl restart triggerhappy
}

configure_boot_settings() {
    local config_file="/boot/config.txt"
    [[ -f "/boot/firmware/config.txt" ]] && config_file="/boot/firmware/config.txt"
    
    # Backup
    cp "$config_file" "${config_file}.bak.$(date +%Y%m%d)" 2>/dev/null
    
    # Remove old toolkit config
    sed -i '/# === Pi CRT Toolkit/,/# === End CRT Toolkit/d' "$config_file"
    
    # Get sdtv_mode based on BOOT_MODE
    local sdtv_mode=0
    local fb_height=480
    case "$BOOT_MODE" in
        ntsc240p) sdtv_mode=16; fb_height=448 ;;
        ntsc480i) sdtv_mode=0;  fb_height=480 ;;
        pal288p)  sdtv_mode=18; fb_height=576 ;;
        pal576i)  sdtv_mode=2;  fb_height=576 ;;
    esac
    
    # Append config
    cat >> "$config_file" << EOF

# === Pi CRT Toolkit Start ===
[pi4]
dtoverlay=vc4-fkms-v3d
max_framebuffers=2

enable_tvout=1
sdtv_mode=$sdtv_mode
sdtv_aspect=1
disable_overscan=1

framebuffer_width=720
framebuffer_height=$fb_height

hdmi_ignore_hotplug=1
audio_pwm_mode=2

[all]
# === End CRT Toolkit ===
EOF
}

install_retropie_hooks() {
    [[ ! -d /opt/retropie ]] && return
    
    # runcommand-onstart.sh
    cat > /opt/retropie/configs/all/runcommand-onstart.sh << 'EOF'
#!/bin/bash
# Switch to 240p for games (unless in 480i list)
interlaced=""
[[ -f "/opt/retropie/configs/$1/480i.txt" ]] && interlaced=$(cat "/opt/retropie/configs/$1/480i.txt")

if echo "$interlaced" | grep -qxi "all" || echo "$3" | grep -qwi "$interlaced" 2>/dev/null; then
    exit 0  # Stay in 480i
fi

tvservice -s 2>/dev/null | grep -q NTSC && /usr/local/bin/crt-240p >/dev/null 2>&1
EOF
    chmod +x /opt/retropie/configs/all/runcommand-onstart.sh
    
    # runcommand-onend.sh
    cat > /opt/retropie/configs/all/runcommand-onend.sh << 'EOF'
#!/bin/bash
tvservice -s 2>/dev/null | grep -q NTSC && /usr/local/bin/crt-480i >/dev/null 2>&1
EOF
    chmod +x /opt/retropie/configs/all/runcommand-onend.sh
}

#
# Configuration Menus
#

do_color_mode() {
    init_platform
    local current="$COLOR_MODE"
    
    local choice
    choice=$(dialog --backtitle "Pi CRT Toolkit" \
        --title "Colour Mode" \
        --default-item "$current" \
        --menu "Select colour encoding for composite output:\n\n\
PAL60 uses PAL colour (4.43MHz) with NTSC timing (60Hz).\n\
This gives better colour on most CRT TVs.\n\n\
Driver: $DRIVER" $MENU_HEIGHT $MENU_WIDTH $LIST_HEIGHT \
        "pal60" "PAL60 - Better colour on most TVs (recommended)" \
        "ntsc"  "NTSC - Standard NTSC colour encoding" \
        "pal"   "PAL - Standard PAL colour (50Hz modes)" \
        2>&1 >/dev/tty)
    
    [[ -z "$choice" ]] && return
    
    COLOR_MODE="$choice"
    save_config
    
    # Apply immediately using abstracted function
    if declare -f set_color_mode &>/dev/null; then
        case "$choice" in
            pal60) set_color_mode "PAL" ;;   # PAL color on 60Hz = PAL60
            ntsc)  set_color_mode "NTSC" ;;
            pal)   set_color_mode "PAL" ;;
        esac
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "Colour mode set to: $choice\n\nApplied immediately." 8 45
    elif is_installed; then
        # Fallback to scripts
        case "$choice" in
            pal60) /usr/local/bin/crt-pal60 2>/dev/null ;;
            ntsc)  /usr/local/bin/crt-ntsc 2>/dev/null ;;
        esac
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "Colour mode set to: $choice\n\nApplied immediately." 8 45
    else
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "Colour mode set to: $choice\n\nWill be applied after installation." 8 45
    fi
}

do_resolution() {
    local current="$BOOT_MODE"
    
    local choice
    choice=$(dialog --backtitle "Pi CRT Toolkit" \
        --title "Default Resolution" \
        --default-item "$current" \
        --menu "Select default boot resolution:\n\n\
This sets the resolution used at boot and for\n\
EmulationStation/desktop. Games use 240p." $MENU_HEIGHT $MENU_WIDTH $LIST_HEIGHT \
        "ntsc480i" "480i (720x480 @ 60Hz) - NTSC interlaced" \
        "ntsc240p" "240p (720x448 @ 60Hz) - NTSC progressive" \
        "pal576i"  "576i (720x576 @ 50Hz) - PAL interlaced" \
        "pal288p"  "288p (720x576 @ 50Hz) - PAL progressive" \
        2>&1 >/dev/tty)
    
    [[ -z "$choice" ]] && return
    
    BOOT_MODE="$choice"
    save_config
    
    if is_installed; then
        configure_boot_settings
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "Default resolution set to: $choice\n\nPlease REBOOT to apply." 8 50
    else
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "Default resolution set to: $choice\n\nWill be applied after installation." 8 50
    fi
}

do_video_mode() {
    init_platform
    
    local current
    if declare -f get_video_mode &>/dev/null; then
        current=$(get_video_mode)
    else
        current=$(tvservice -s 2>/dev/null | grep -oE "(NTSC|PAL).*" || echo "unknown")
    fi
    
    local choice
    choice=$(dialog --backtitle "Pi CRT Toolkit" \
        --title "Switch Video Mode" \
        --menu "Current: $current (Driver: $DRIVER)\n\nSwitch video mode now (immediate effect):" $MENU_HEIGHT $MENU_WIDTH $LIST_HEIGHT \
        "240p" "NTSC 240p - Progressive 60Hz" \
        "480i" "NTSC 480i - Interlaced 60Hz" \
        "288p" "PAL 288p - Progressive 50Hz" \
        "576i" "PAL 576i - Interlaced 50Hz" \
        2>&1 >/dev/tty)
    
    [[ -z "$choice" ]] && return
    
    # Use abstracted video switching if available
    if declare -f set_video_mode &>/dev/null; then
        set_video_mode "$choice"
    else
        # Fallback to tvservice (Legacy/FKMS)
        case "$choice" in
            240p) tvservice -c "NTSC 4:3 P" ;;
            480i) tvservice -c "NTSC 4:3" ;;
            288p) tvservice -c "PAL 4:3 P" ;;
            576i) tvservice -c "PAL 4:3" ;;
        esac
        fbset -depth 8 && fbset -depth 16
    fi
    
    # Reapply color if needed (NTSC modes)
    if [[ "$COLOR_MODE" == "pal60" ]] && [[ "$choice" == "240p" || "$choice" == "480i" ]]; then
        if declare -f set_color_mode &>/dev/null; then
            set_color_mode "PAL"  # PAL color on 480i = PAL60
        else
            python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
        fi
    fi
}

do_hotkeys() {
    if [[ -f /etc/triggerhappy/triggers.d/crt-toolkit.conf ]]; then
        local status="INSTALLED"
    else
        local status="NOT INSTALLED"
    fi
    
    dialog --backtitle "Pi CRT Toolkit" \
        --title "Global Hotkeys" \
        --yesno "Status: $status\n\n\
Hotkey mappings:\n\
  F7  = PAL60 colour\n\
  F8  = NTSC colour\n\
  F9  = 240p\n\
  F10 = 480i\n\
  F11 = 288p (PAL)\n\
  F12 = 576i (PAL)\n\n\
Install/reinstall hotkeys?" $MENU_HEIGHT 50
    
    [[ $? -ne 0 ]] && return
    
    install_hotkey_config
    dialog --backtitle "Pi CRT Toolkit" \
        --msgbox "Hotkeys installed successfully!" 6 40
}

do_retropie() {
    if ! is_retropie; then
        dialog --backtitle "Pi CRT Toolkit" \
            --msgbox "RetroPie is not installed on this system." 6 50
        return
    fi
    
    local choice
    choice=$(dialog --backtitle "Pi CRT Toolkit" \
        --title "RetroPie Integration" \
        --menu "Configure RetroPie CRT settings:" $MENU_HEIGHT $MENU_WIDTH $LIST_HEIGHT \
        1 "Install/Update runcommand hooks" \
        2 "About 480i game exceptions" \
        2>&1 >/dev/tty)
    
    case $choice in
        1)
            install_retropie_hooks
            dialog --backtitle "Pi CRT Toolkit" \
                --msgbox "RetroPie hooks installed!\n\n\
Games will now automatically use 240p.\n\
EmulationStation uses 480i." 10 50
            ;;
        2)
            dialog --backtitle "Pi CRT Toolkit" \
                --msgbox "Per-game 480i exceptions:\n\n\
Create: /opt/retropie/configs/<system>/480i.txt\n\n\
Add game names (one per line):\n\
  Bloody Roar 2.pbp\n\
  Gran Turismo.bin\n\n\
Or use 'all' to force 480i for entire system." 14 55
            ;;
    esac
}

do_system_info() {
    init_platform
    
    local tv_status
    if [[ "$DRIVER" == "kms" ]]; then
        tv_status=$(kmsprint -m 2>/dev/null | grep -i composite || echo "KMS Composite")
    else
        tv_status=$(tvservice -s 2>/dev/null || echo "Not available")
    fi
    
    local color_status
    if declare -f get_color_mode &>/dev/null; then
        color_status=$(get_color_mode)
    else
        color_status="unknown"
    fi
    
    local installed_status="No"
    is_installed && installed_status="Yes"
    local retropie_status="No"
    is_retropie && retropie_status="Yes"
    
    dialog --backtitle "Pi CRT Toolkit" \
        --title "System Information" \
        --msgbox "\
Pi CRT Toolkit v$VERSION\n\n\
System:\n\
  OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)\n\
  Model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)\n\
  Driver: ${DRIVER:-unknown}\n\n\
Status:\n\
  Toolkit installed: $installed_status\n\
  RetroPie: $retropie_status\n\n\
Video:\n\
  $tv_status\n\
  Color: $color_status\n\n\
Settings:\n\
  Colour mode: $COLOR_MODE\n\
  Boot mode: $BOOT_MODE" $MENU_HEIGHT $MENU_WIDTH
}

do_update() {
    dialog --backtitle "Pi CRT Toolkit" \
        --title "Update" \
        --yesno "Download latest version from GitHub?" 7 50
    
    [[ $? -ne 0 ]] && return
    
    (
        echo "20"; echo "# Fetching updates..."
        cd "$INSTALL_DIR" 2>/dev/null || exit 1
        git fetch origin 2>&1
        
        echo "60"; echo "# Applying updates..."
        git reset --hard origin/main 2>&1
        
        echo "90"; echo "# Setting permissions..."
        chmod +x "$INSTALL_DIR/crt-toolkit.sh" "$INSTALL_DIR/lib/"*.sh 2>/dev/null
        
        echo "100"; echo "# Done!"
    ) | dialog --backtitle "Pi CRT Toolkit" \
        --title "Updating" \
        --gauge "Checking for updates..." 8 50 0
    
    dialog --backtitle "Pi CRT Toolkit" \
        --msgbox "Update complete!\n\nPlease restart the toolkit to use the new version." 8 55
}

do_uninstall() {
    dialog --backtitle "Pi CRT Toolkit" \
        --title "Uninstall" \
        --yesno "Remove Pi CRT Toolkit?\n\n\
This will remove:\n\
• Command scripts\n\
• Hotkey configuration\n\
• Toolkit files\n\n\
Boot config will NOT be modified." $MENU_HEIGHT 50
    
    [[ $? -ne 0 ]] && return
    
    rm -f /usr/local/bin/crt-{240p,480i,288p,576i,pal60,ntsc}
    rm -f /usr/local/bin/crt-toolkit
    rm -f /etc/triggerhappy/triggers.d/crt-toolkit.conf
    rm -rf /etc/systemd/system/triggerhappy.service.d/override.conf
    rm -rf /usr/local/lib/crt-toolkit
    rm -rf "$CONFIG_DIR"
    
    systemctl daemon-reload
    systemctl restart triggerhappy 2>/dev/null
    
    dialog --backtitle "Pi CRT Toolkit" \
        --msgbox "CRT Toolkit has been removed.\n\n\
Note: $INSTALL_DIR was kept.\n\
Boot config was not modified." 10 50
}

#
# Main Menu
#

show_main_menu() {
    while true; do
        init_platform
        
        # Build menu items
        local menu_items=()
        
        # Installation status
        if is_installed; then
            menu_items+=("I" "Update Installation")
        else
            menu_items+=("I" "Install CRT Toolkit")
        fi
        
        menu_items+=(
            "C" "Colour Mode         [$COLOR_MODE]"
            "R" "Resolution          [$BOOT_MODE]"
            "V" "Switch Video Mode   (immediate)"
            "H" "Global Hotkeys      (F7-F12)"
        )
        
        is_retropie && menu_items+=("P" "RetroPie Integration")
        
        menu_items+=(
            "S" "System Information"
        )
        
        is_installed && menu_items+=("U" "Uninstall")
        
        local choice
        choice=$(dialog --backtitle "Pi CRT Toolkit v$VERSION" \
            --title "Main Menu" \
            --cancel-label "Exit" \
            --menu "Use arrow keys to navigate, Enter to select:" $MENU_HEIGHT $MENU_WIDTH $LIST_HEIGHT \
            "${menu_items[@]}" \
            2>&1 >/dev/tty)
        
        case $choice in
            I) 
                if is_installed; then
                    do_update
                else
                    do_install
                fi
                ;;
            C) do_color_mode ;;
            R) do_resolution ;;
            V) do_video_mode ;;
            H) do_hotkeys ;;
            P) do_retropie ;;
            S) do_system_info ;;
            U) do_uninstall ;;
            *) 
                clear
                exit 0
                ;;
        esac
    done
}

#
# CLI Interface
#

show_help() {
    cat << EOF
Pi CRT Toolkit v$VERSION

Usage: $0 [command]

Commands:
  (none)      Launch interactive menu
  --240p      Switch to 240p immediately
  --480i      Switch to 480i immediately  
  --288p      Switch to 288p (PAL) immediately
  --576i      Switch to 576i (PAL) immediately
  --pal60     Apply PAL60 colour encoding
  --ntsc      Apply NTSC colour encoding
  --status    Show current video status
  --help      Show this help

One-line install:
  curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/crt-toolkit.sh | sudo bash
EOF
}

#
# Entry Point
#

main() {
    case "${1:-}" in
        --240p)
            tvservice -c "NTSC 4:3 P" 2>/dev/null
            fbset -depth 8 && fbset -depth 16
            ;;
        --480i)
            tvservice -c "NTSC 4:3" 2>/dev/null
            fbset -depth 8 && fbset -depth 16
            ;;
        --288p)
            tvservice -c "PAL 4:3 P" 2>/dev/null
            fbset -depth 8 && fbset -depth 16
            ;;
        --576i)
            tvservice -c "PAL 4:3" 2>/dev/null
            fbset -depth 8 && fbset -depth 16
            ;;
        --pal60)
            python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
            echo "pal60" > /tmp/crt-toolkit-color
            ;;
        --ntsc)
            python3 /home/pi/tweakvec/tweakvec.py --preset NTSC 2>/dev/null
            echo "ntsc" > /tmp/crt-toolkit-color
            ;;
        --status|-s)
            echo "Video: $(tvservice -s 2>/dev/null || echo 'unknown')"
            echo "Colour: $(cat /tmp/crt-toolkit-color 2>/dev/null || echo 'unknown')"
            ;;
        --help|-h)
            show_help
            ;;
        "")
            check_root
            ensure_dialog
            load_config
            show_main_menu
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
}

main "$@"
