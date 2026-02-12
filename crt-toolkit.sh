#!/bin/bash
#
# CRT Toolkit for Raspberry Pi 4
# A menu-driven setup utility for CRT output via composite video
#
# Inspired by RetroPie Setup and raspi-config
#

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/crt-toolkit"
CONFIG_FILE="$CONFIG_DIR/config"

# Default configuration
COLOR_MODE="pal60"
BOOT_MODE="ntsc480i"
TERMINAL_MODE="480i"
ES_MODE="480i"
EMULATOR_MODE="240p"

# Colors for dialog
export DIALOGRC=""
export NEWT_COLORS='
root=,black
window=,black
border=white,black
listbox=white,black
label=white,black
checkbox=white,black
actlistbox=black,white
actsellistbox=black,white
button=black,white
actbutton=white,black
'

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (sudo)"
        exit 1
    fi
}

# Check dependencies
check_deps() {
    local missing=()
    for cmd in dialog tvservice python3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Installing..."
        apt-get update
        apt-get install -y dialog
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
# CRT Toolkit Configuration
COLOR_MODE="$COLOR_MODE"
BOOT_MODE="$BOOT_MODE"
TERMINAL_MODE="$TERMINAL_MODE"
ES_MODE="$ES_MODE"
EMULATOR_MODE="$EMULATOR_MODE"
EOF
}

# Detect if RetroPie is installed
is_retropie() {
    [[ -d "/opt/retropie" ]]
}

# Detect Pi model
get_pi_model() {
    if grep -q "Raspberry Pi 4" /proc/cpuinfo 2>/dev/null; then
        echo "pi4"
    elif grep -q "Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
        echo "pi3"
    else
        echo "unknown"
    fi
}

#
# Video Mode Functions
#

set_240p() {
    tvservice -c "NTSC 4:3 P"
    fbset -depth 8 && fbset -depth 16
    apply_color_mode
}

set_480i() {
    tvservice -c "NTSC 4:3"
    fbset -depth 8 && fbset -depth 16
    apply_color_mode
}

set_288p() {
    tvservice -c "PAL 4:3 P"
    fbset -depth 8 && fbset -depth 16
}

set_576i() {
    tvservice -c "PAL 4:3"
    fbset -depth 8 && fbset -depth 16
}

apply_color_mode() {
    if [[ "$COLOR_MODE" == "pal60" ]]; then
        if [[ -f "/usr/local/lib/crt-toolkit/pal60.py" ]]; then
            python3 /usr/local/lib/crt-toolkit/pal60.py --apply
        elif [[ -f "$HOME/tweakvec/tweakvec.py" ]]; then
            python3 "$HOME/tweakvec/tweakvec.py" --preset PAL60
        fi
    fi
    echo "$COLOR_MODE" > /tmp/color_mode
}

#
# Installation Functions
#

install_mode_scripts() {
    echo "Installing video mode scripts..."
    
    mkdir -p /usr/local/bin
    
    # 240p script
    cat > /usr/local/bin/crt-240p << 'SCRIPT'
#!/bin/bash
tvservice -c "NTSC 4:3 P"
fbset -depth 8 && fbset -depth 16
COLOR_MODE=$(cat /tmp/color_mode 2>/dev/null || echo "pal60")
if [[ "$COLOR_MODE" == "pal60" ]]; then
    python3 /usr/local/lib/crt-toolkit/pal60.py --apply 2>/dev/null || \
    python3 ~/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
fi
SCRIPT
    chmod +x /usr/local/bin/crt-240p
    
    # 480i script
    cat > /usr/local/bin/crt-480i << 'SCRIPT'
#!/bin/bash
tvservice -c "NTSC 4:3"
fbset -depth 8 && fbset -depth 16
COLOR_MODE=$(cat /tmp/color_mode 2>/dev/null || echo "pal60")
if [[ "$COLOR_MODE" == "pal60" ]]; then
    python3 /usr/local/lib/crt-toolkit/pal60.py --apply 2>/dev/null || \
    python3 ~/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
fi
SCRIPT
    chmod +x /usr/local/bin/crt-480i
    
    # 288p script (PAL progressive)
    cat > /usr/local/bin/crt-288p << 'SCRIPT'
#!/bin/bash
tvservice -c "PAL 4:3 P"
fbset -depth 8 && fbset -depth 16
SCRIPT
    chmod +x /usr/local/bin/crt-288p
    
    # 576i script (PAL interlaced)
    cat > /usr/local/bin/crt-576i << 'SCRIPT'
#!/bin/bash
tvservice -c "PAL 4:3"
fbset -depth 8 && fbset -depth 16
SCRIPT
    chmod +x /usr/local/bin/crt-576i
    
    # PAL60 color script
    cat > /usr/local/bin/crt-pal60 << 'SCRIPT'
#!/bin/bash
python3 /usr/local/lib/crt-toolkit/pal60.py --apply 2>/dev/null || \
python3 ~/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
echo "pal60" > /tmp/color_mode
SCRIPT
    chmod +x /usr/local/bin/crt-pal60
    
    # NTSC color script
    cat > /usr/local/bin/crt-ntsc << 'SCRIPT'
#!/bin/bash
python3 /usr/local/lib/crt-toolkit/pal60.py --reset 2>/dev/null || \
python3 ~/tweakvec/tweakvec.py --preset NTSC 2>/dev/null
echo "ntsc" > /tmp/color_mode
SCRIPT
    chmod +x /usr/local/bin/crt-ntsc
    
    echo "Mode scripts installed."
}

install_hotkeys() {
    echo "Installing global hotkeys..."
    
    apt-get install -y triggerhappy &>/dev/null
    
    # Create triggerhappy config
    cat > /etc/triggerhappy/triggers.d/crt-toolkit.conf << 'EOF'
# CRT Toolkit Hotkeys
# F7 = PAL60 color, F8 = NTSC color
# F9 = 240p (NTSC), F10 = 480i (NTSC)
# F11 = 288p (PAL), F12 = 576i (PAL)
KEY_F7      1    /usr/local/bin/crt-pal60
KEY_F8      1    /usr/local/bin/crt-ntsc
KEY_F9      1    /usr/local/bin/crt-240p
KEY_F10     1    /usr/local/bin/crt-480i
KEY_F11     1    /usr/local/bin/crt-288p
KEY_F12     1    /usr/local/bin/crt-576i
EOF
    
    # Configure triggerhappy to run as root
    mkdir -p /etc/systemd/system/triggerhappy.service.d
    cat > /etc/systemd/system/triggerhappy.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
EOF
    
    systemctl daemon-reload
    systemctl enable triggerhappy
    systemctl restart triggerhappy
    
    echo "Hotkeys installed: F7=PAL60, F8=NTSC, F9=240p, F10=480i, F11=288p, F12=576i"
}

install_pal60_library() {
    echo "Installing PAL60 color library..."
    
    mkdir -p /usr/local/lib/crt-toolkit
    
    # Check if tweakvec exists
    if [[ -d "$HOME/tweakvec" ]] || [[ -d "/home/pi/tweakvec" ]]; then
        local tweakvec_path="${HOME}/tweakvec"
        [[ -d "/home/pi/tweakvec" ]] && tweakvec_path="/home/pi/tweakvec"
        
        # Create wrapper that uses tweakvec
        cat > /usr/local/lib/crt-toolkit/pal60.py << SCRIPT
#!/usr/bin/env python3
import sys
import os
sys.path.insert(0, "$tweakvec_path")
from tweakvec import *

if __name__ == "__main__":
    if "--apply" in sys.argv or "--preset" in sys.argv:
        os.system("python3 $tweakvec_path/tweakvec.py --preset PAL60")
    elif "--reset" in sys.argv:
        os.system("python3 $tweakvec_path/tweakvec.py --preset NTSC")
SCRIPT
        chmod +x /usr/local/lib/crt-toolkit/pal60.py
        echo "Using tweakvec for PAL60 color."
    else
        echo "tweakvec not found. Cloning..."
        git clone https://github.com/ArcadeHustle/tweakvec.git /usr/local/lib/crt-toolkit/tweakvec 2>/dev/null || \
        git clone https://github.com/mondul/tweakvec.git /usr/local/lib/crt-toolkit/tweakvec
        
        cat > /usr/local/lib/crt-toolkit/pal60.py << 'SCRIPT'
#!/usr/bin/env python3
import sys
import os

TWEAKVEC_PATH = "/usr/local/lib/crt-toolkit/tweakvec"

if __name__ == "__main__":
    if "--apply" in sys.argv:
        os.system(f"python3 {TWEAKVEC_PATH}/tweakvec.py --preset PAL60")
    elif "--reset" in sys.argv:
        os.system(f"python3 {TWEAKVEC_PATH}/tweakvec.py --preset NTSC")
SCRIPT
        chmod +x /usr/local/lib/crt-toolkit/pal60.py
    fi
}

install_retropie_integration() {
    if ! is_retropie; then
        echo "RetroPie not detected, skipping integration."
        return
    fi
    
    echo "Installing RetroPie integration..."
    
    # runcommand-onstart.sh - switch to 240p for games
    cat > /opt/retropie/configs/all/runcommand-onstart.sh << 'SCRIPT'
#!/bin/bash
# CRT Toolkit - Switch to 240p for emulators

# Check for 480i override files
interlaced=""
progresive=""

if [ -f "/opt/retropie/configs/$1/480i.txt" ]; then
    interlaced=$(tr -d "\r" < "/opt/retropie/configs/$1/480i.txt" | sed -e 's/\[/\\[/')
fi
if [ -f "/opt/retropie/configs/ports/$1/480i.txt" ]; then
    interlaced=$(tr -d "\r" < "/opt/retropie/configs/ports/$1/480i.txt" | sed -e 's/\[/\\[/')
fi
[ -z "$interlaced" ] && interlaced="empty"

if [ -f "/opt/retropie/configs/$1/240p.txt" ]; then
    progresive=$(tr -d "\r" < "/opt/retropie/configs/$1/240p.txt" | sed -e 's/\[/\\[/')
fi
if [ -f "/opt/retropie/configs/ports/$1/240p.txt" ]; then
    progresive=$(tr -d "\r" < "/opt/retropie/configs/ports/$1/240p.txt" | sed -e 's/\[/\\[/')
fi
[ -z "$progresive" ] && progresive="empty"

# Switch to 240p unless game is in 480i list
if tvservice -s | grep -q NTSC; then
    force_480i=false
    
    # Check if this game should be 480i
    if echo "$interlaced" | grep -qxi "all"; then
        force_480i=true
    elif ! echo "$interlaced" | grep -q "empty" && echo "$3" | grep -qwi "$interlaced"; then
        force_480i=true
    fi
    
    # Check if explicitly in 240p list
    if ! echo "$progresive" | grep -q "empty" && ! echo "$3" | grep -qwi "$progresive"; then
        force_480i=true
    fi
    
    if ! $force_480i; then
        /usr/local/bin/crt-240p
    fi
fi > /dev/null 2>&1
SCRIPT
    chmod +x /opt/retropie/configs/all/runcommand-onstart.sh
    
    # runcommand-onend.sh - switch back to 480i for ES
    cat > /opt/retropie/configs/all/runcommand-onend.sh << 'SCRIPT'
#!/bin/bash
# CRT Toolkit - Switch back to 480i for EmulationStation
if tvservice -s | grep -q NTSC; then
    /usr/local/bin/crt-480i
fi > /dev/null 2>&1
SCRIPT
    chmod +x /opt/retropie/configs/all/runcommand-onend.sh
    
    echo "RetroPie integration installed."
}

configure_boot() {
    echo "Configuring boot settings..."
    
    local config_file="/boot/config.txt"
    [[ -f "/boot/firmware/config.txt" ]] && config_file="/boot/firmware/config.txt"
    
    # Backup original
    cp "$config_file" "${config_file}.bak.$(date +%Y%m%d)" 2>/dev/null
    
    # Remove existing CRT toolkit settings
    sed -i '/# CRT Toolkit Settings/,/# End CRT Toolkit/d' "$config_file"
    
    # Determine framebuffer settings based on boot mode
    local fb_width=720
    local fb_height=480
    local sdtv_mode=0
    
    case "$BOOT_MODE" in
        ntsc240p)
            fb_width=720; fb_height=448; sdtv_mode=16 ;;
        ntsc480i)
            fb_width=720; fb_height=480; sdtv_mode=0 ;;
        pal288p)
            fb_width=720; fb_height=576; sdtv_mode=18 ;;
        pal576i)
            fb_width=720; fb_height=576; sdtv_mode=2 ;;
    esac
    
    # Add CRT toolkit settings
    cat >> "$config_file" << EOF

# CRT Toolkit Settings
[pi4]
dtoverlay=vc4-fkms-v3d
max_framebuffers=2

# TV Output
enable_tvout=1
framebuffer_width=$fb_width
framebuffer_height=$fb_height
sdtv_mode=$sdtv_mode
sdtv_aspect=1
disable_overscan=1

# Force composite even with HDMI connected
hdmi_ignore_hotplug=1

# Audio
audio_pwm_mode=2
# End CRT Toolkit
EOF
    
    echo "Boot configuration updated."
}

#
# Menu System
#

show_main_menu() {
    while true; do
        local choice
        choice=$(dialog --clear --backtitle "CRT Toolkit v$VERSION" \
            --title "Main Menu" \
            --menu "Choose an option:" 18 60 10 \
            1 "Quick Setup (Recommended)" \
            2 "Color Mode Settings" \
            3 "Video Mode Settings" \
            4 "Boot Configuration" \
            5 "Install Hotkeys" \
            6 "RetroPie Integration" \
            7 "Test Video Modes" \
            8 "View Current Status" \
            9 "Uninstall" \
            0 "Exit" \
            2>&1 >/dev/tty)
        
        case $choice in
            1) quick_setup ;;
            2) color_mode_menu ;;
            3) video_mode_menu ;;
            4) boot_config_menu ;;
            5) install_hotkeys_menu ;;
            6) retropie_menu ;;
            7) test_modes_menu ;;
            8) show_status ;;
            9) uninstall_menu ;;
            0|"") clear; exit 0 ;;
        esac
    done
}

quick_setup() {
    # Step 1: Color mode
    local color_choice
    color_choice=$(dialog --clear --backtitle "CRT Toolkit - Quick Setup" \
        --title "Color Mode" \
        --menu "Select your preferred color encoding:\n\nPAL60 is recommended for most CRTs as it provides better color on NTSC-timed signals." 15 60 4 \
        1 "PAL60 (Recommended)" \
        2 "Pure NTSC" \
        3 "I don't know (use PAL60)" \
        2>&1 >/dev/tty)
    
    case $color_choice in
        1|3) COLOR_MODE="pal60" ;;
        2) COLOR_MODE="ntsc" ;;
        *) return ;;
    esac
    
    # Step 2: Boot resolution
    local boot_choice
    if [[ "$COLOR_MODE" == "ntsc" ]] || [[ "$COLOR_MODE" == "pal60" ]]; then
        boot_choice=$(dialog --clear --backtitle "CRT Toolkit - Quick Setup" \
            --title "Boot Resolution" \
            --menu "Select your boot/default resolution:" 16 60 6 \
            1 "Prefer Higher Framerate (60Hz NTSC)" \
            2 "Prefer Higher Resolution (50Hz PAL)" \
            3 "720x480 @ 60Hz (NTSC 480i)" \
            4 "720x480 @ 60Hz (NTSC 240p)" \
            5 "720x576 @ 50Hz (PAL 576i)" \
            6 "720x576 @ 50Hz (PAL 288p)" \
            2>&1 >/dev/tty)
    fi
    
    case $boot_choice in
        1|3) BOOT_MODE="ntsc480i" ;;
        4) BOOT_MODE="ntsc240p" ;;
        2|5) BOOT_MODE="pal576i" ;;
        6) BOOT_MODE="pal288p" ;;
        *) return ;;
    esac
    
    # Confirm and install
    dialog --clear --backtitle "CRT Toolkit - Quick Setup" \
        --title "Confirm Installation" \
        --yesno "Ready to install with these settings:\n\nColor Mode: $COLOR_MODE\nBoot Mode: $BOOT_MODE\n\nThis will:\n- Install video mode scripts\n- Install global hotkeys (F7-F12)\n- Configure boot settings\n$(is_retropie && echo '- Setup RetroPie integration')\n\nProceed?" 16 60
    
    if [[ $? -eq 0 ]]; then
        clear
        echo "Installing CRT Toolkit..."
        echo ""
        
        save_config
        install_pal60_library
        install_mode_scripts
        install_hotkeys
        configure_boot
        
        if is_retropie; then
            install_retropie_integration
        fi
        
        echo ""
        echo "Installation complete!"
        echo ""
        echo "Hotkeys installed:"
        echo "  F7  = PAL60 color"
        echo "  F8  = NTSC color"
        echo "  F9  = 240p"
        echo "  F10 = 480i"
        echo "  F11 = 288p (PAL)"
        echo "  F12 = 576i (PAL)"
        echo ""
        echo "Please reboot to apply boot settings."
        echo ""
        read -p "Press Enter to continue..."
    fi
}

color_mode_menu() {
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "Color Mode Settings" \
        --menu "Current: $COLOR_MODE\n\nSelect color encoding:" 14 60 4 \
        1 "PAL60 (Better colors on most CRTs)" \
        2 "Pure NTSC" \
        3 "Apply current setting now" \
        0 "Back" \
        2>&1 >/dev/tty)
    
    case $choice in
        1) COLOR_MODE="pal60"; save_config ;;
        2) COLOR_MODE="ntsc"; save_config ;;
        3) apply_color_mode; dialog --msgbox "Color mode applied: $COLOR_MODE" 6 40 ;;
        0|"") return ;;
    esac
}

video_mode_menu() {
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "Video Mode Settings" \
        --menu "Configure default modes for different contexts:" 14 60 5 \
        1 "Terminal Mode: $TERMINAL_MODE" \
        2 "EmulationStation Mode: $ES_MODE" \
        3 "Emulator Mode: $EMULATOR_MODE" \
        0 "Back" \
        2>&1 >/dev/tty)
    
    case $choice in
        1) select_mode "TERMINAL_MODE" "Terminal" ;;
        2) select_mode "ES_MODE" "EmulationStation" ;;
        3) select_mode "EMULATOR_MODE" "Emulator" ;;
        0|"") return ;;
    esac
    save_config
}

select_mode() {
    local var_name="$1"
    local context="$2"
    local current_val="${!var_name}"
    
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "$context Mode" \
        --menu "Current: $current_val" 12 50 4 \
        "240p" "NTSC Progressive (60Hz)" \
        "480i" "NTSC Interlaced (60Hz)" \
        "288p" "PAL Progressive (50Hz)" \
        "576i" "PAL Interlaced (50Hz)" \
        2>&1 >/dev/tty)
    
    [[ -n "$choice" ]] && eval "$var_name=\"$choice\""
}

boot_config_menu() {
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "Boot Configuration" \
        --menu "Current boot mode: $BOOT_MODE" 14 60 5 \
        1 "NTSC 480i (720x480 @ 60Hz interlaced)" \
        2 "NTSC 240p (720x480 @ 60Hz progressive)" \
        3 "PAL 576i (720x576 @ 50Hz interlaced)" \
        4 "PAL 288p (720x576 @ 50Hz progressive)" \
        0 "Back" \
        2>&1 >/dev/tty)
    
    case $choice in
        1) BOOT_MODE="ntsc480i" ;;
        2) BOOT_MODE="ntsc240p" ;;
        3) BOOT_MODE="pal576i" ;;
        4) BOOT_MODE="pal288p" ;;
        0|"") return ;;
    esac
    
    save_config
    configure_boot
    dialog --msgbox "Boot configuration updated.\nPlease reboot to apply changes." 7 45
}

install_hotkeys_menu() {
    dialog --clear --backtitle "CRT Toolkit" \
        --title "Install Hotkeys" \
        --yesno "This will install global hotkeys:\n\nF7  = PAL60 color\nF8  = NTSC color\nF9  = 240p\nF10 = 480i\nF11 = 288p (PAL)\nF12 = 576i (PAL)\n\nProceed?" 15 45
    
    if [[ $? -eq 0 ]]; then
        clear
        install_hotkeys
        read -p "Press Enter to continue..."
    fi
}

retropie_menu() {
    if ! is_retropie; then
        dialog --msgbox "RetroPie is not installed on this system." 6 50
        return
    fi
    
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "RetroPie Integration" \
        --menu "Configure RetroPie CRT settings:" 14 60 4 \
        1 "Install/Update Integration" \
        2 "Set all systems to CRT mode" \
        3 "Configure 480i exceptions" \
        0 "Back" \
        2>&1 >/dev/tty)
    
    case $choice in
        1) 
            clear
            install_retropie_integration
            read -p "Press Enter to continue..."
            ;;
        0|"") return ;;
    esac
}

test_modes_menu() {
    local choice
    choice=$(dialog --clear --backtitle "CRT Toolkit" \
        --title "Test Video Modes" \
        --menu "Select a mode to test (will change immediately):" 14 50 6 \
        1 "240p (NTSC)" \
        2 "480i (NTSC)" \
        3 "288p (PAL)" \
        4 "576i (PAL)" \
        5 "PAL60 color" \
        6 "NTSC color" \
        2>&1 >/dev/tty)
    
    clear
    case $choice in
        1) echo "Switching to 240p..."; set_240p ;;
        2) echo "Switching to 480i..."; set_480i ;;
        3) echo "Switching to 288p..."; set_288p ;;
        4) echo "Switching to 576i..."; set_576i ;;
        5) echo "Applying PAL60 color..."; COLOR_MODE="pal60"; apply_color_mode ;;
        6) echo "Applying NTSC color..."; COLOR_MODE="ntsc"; apply_color_mode ;;
        *) return ;;
    esac
    sleep 2
}

show_status() {
    local tv_status=$(tvservice -s 2>/dev/null)
    local fb_info=$(fbset 2>/dev/null | grep geometry)
    local pi_model=$(get_pi_model)
    local retropie_status="Not installed"
    is_retropie && retropie_status="Installed"
    local color_mode_file=$(cat /tmp/color_mode 2>/dev/null || echo "unknown")
    
    dialog --clear --backtitle "CRT Toolkit" \
        --title "Current Status" \
        --msgbox "System Information:\n\nPi Model: $pi_model\nRetroPie: $retropie_status\n\nVideo Status:\n$tv_status\n\nFramebuffer:\n$fb_info\n\nColor Mode: $color_mode_file\n\nConfig:\nBoot Mode: $BOOT_MODE\nColor Mode: $COLOR_MODE" 20 60
}

uninstall_menu() {
    dialog --clear --backtitle "CRT Toolkit" \
        --title "Uninstall" \
        --yesno "This will remove:\n- Video mode scripts\n- Hotkey configuration\n- Boot config changes\n\nAre you sure?" 12 45
    
    if [[ $? -eq 0 ]]; then
        clear
        echo "Removing CRT Toolkit..."
        
        rm -f /usr/local/bin/crt-{240p,480i,288p,576i,pal60,ntsc}
        rm -f /etc/triggerhappy/triggers.d/crt-toolkit.conf
        rm -rf /usr/local/lib/crt-toolkit
        rm -rf "$CONFIG_DIR"
        
        systemctl restart triggerhappy 2>/dev/null
        
        echo "CRT Toolkit removed."
        echo "Note: Boot config changes in /boot/config.txt were not removed."
        read -p "Press Enter to continue..."
    fi
}

#
# Main Entry Point
#

main() {
    check_root
    check_deps
    load_config
    
    # Handle command line arguments
    case "${1:-}" in
        --install)
            quick_setup
            ;;
        --240p)
            set_240p
            ;;
        --480i)
            set_480i
            ;;
        --288p)
            set_288p
            ;;
        --576i)
            set_576i
            ;;
        --pal60)
            COLOR_MODE="pal60"
            apply_color_mode
            ;;
        --ntsc)
            COLOR_MODE="ntsc"
            apply_color_mode
            ;;
        --status)
            tvservice -s
            cat /tmp/color_mode 2>/dev/null && echo ""
            ;;
        --help|-h)
            echo "CRT Toolkit v$VERSION"
            echo ""
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  (none)     Launch interactive menu"
            echo "  --install  Quick install with prompts"
            echo "  --240p     Switch to 240p"
            echo "  --480i     Switch to 480i"
            echo "  --288p     Switch to 288p (PAL)"
            echo "  --576i     Switch to 576i (PAL)"
            echo "  --pal60    Apply PAL60 color"
            echo "  --ntsc     Apply NTSC color"
            echo "  --status   Show current video status"
            echo "  --help     Show this help"
            ;;
        *)
            show_main_menu
            ;;
    esac
}

main "$@"
