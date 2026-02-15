#!/bin/bash
#
# Pi CRT Toolkit - RetroPie runcommand-onstart.sh
# Runs BEFORE an emulator launches
#
# This script:
# 1. Sets up PAL60 color encoding via tweakvec
# 2. Determines if game should run in 240p or 480i
# 3. Launches background mode watcher for dynamic switching
#
# Arguments from RetroPie:
# $1 = system (nes, snes, psx, etc)
# $2 = emulator (lr-fceumm, lr-snes9x, etc)
# $3 = ROM path
# $4 = command
#

SYSTEM="$1"
EMULATOR="$2"
ROM_PATH="$3"

# Source toolkit libraries
TOOLKIT_DIR="/opt/crt-toolkit"
if [[ -d "$TOOLKIT_DIR/lib" ]]; then
    source "$TOOLKIT_DIR/lib/platform.sh"
    source "$TOOLKIT_DIR/lib/video.sh"
    source "$TOOLKIT_DIR/lib/color.sh"
fi

# Config directories
CONFIGS_DIR="/opt/retropie/configs"
PORTS_CONFIGS="$CONFIGS_DIR/ports"

#
# Mode Override Files
# Create 240p.txt or 480i.txt in system config folder with game names (one per line)
# to force specific games to a particular mode
#

# Read override file and check if ROM matches
check_mode_override() {
    local override_file="$1"
    local rom_name="$2"
    
    if [[ ! -f "$override_file" ]]; then
        return 1
    fi
    
    # Read file, escape brackets for grep
    local patterns=$(tr -d "\r" < "$override_file" | sed -e 's/\[/\\[/g')
    
    if [[ -z "$patterns" ]]; then
        return 1
    fi
    
    if echo "$rom_name" | grep -qiF "$patterns"; then
        return 0
    fi
    
    return 1
}

# Determine default video mode for system
get_system_default_mode() {
    local system="$1"
    
    # Most retro systems are 240p native
    # Override for systems that commonly use 480i
    case "$system" in
        # Systems that often use 480i
        psx|ps1|playstation)
            # PSX is mixed - let dynamic switching handle it
            echo "auto"
            ;;
        dreamcast|dc)
            echo "480i"
            ;;
        # Everything else defaults to 240p
        *)
            echo "240p"
            ;;
    esac
}

# Get ROM name without path/extension for matching
get_rom_name() {
    local path="$1"
    basename "${path%.*}"
}

#
# Main Logic
#

ROM_NAME=$(get_rom_name "$ROM_PATH")

# Check for mode override files
FORCE_480I=false
FORCE_240P=false

# Check system-specific overrides
if check_mode_override "$CONFIGS_DIR/$SYSTEM/480i.txt" "$ROM_NAME"; then
    FORCE_480I=true
elif check_mode_override "$CONFIGS_DIR/$SYSTEM/240p.txt" "$ROM_NAME"; then
    FORCE_240P=true
fi

# Check ports overrides (for ports/$SYSTEM)
if [[ -d "$PORTS_CONFIGS/$SYSTEM" ]]; then
    if check_mode_override "$PORTS_CONFIGS/$SYSTEM/480i.txt" "$ROM_NAME"; then
        FORCE_480I=true
    elif check_mode_override "$PORTS_CONFIGS/$SYSTEM/240p.txt" "$ROM_NAME"; then
        FORCE_240P=true
    fi
fi

# Determine target mode
if [[ "$FORCE_480I" == "true" ]]; then
    TARGET_MODE="480i"
elif [[ "$FORCE_240P" == "true" ]]; then
    TARGET_MODE="240p"
else
    TARGET_MODE=$(get_system_default_mode "$SYSTEM")
fi

# Save target mode for change_vmode.sh
echo "$TARGET_MODE" > /tmp/crt-target-mode

# 1. Set PAL60 color encoding (if tweakvec available)
if command -v python3 &>/dev/null; then
    setup_pal60_for_game 2>/dev/null
fi

# 2. Launch background mode watcher (for dynamic 240p/480i switching)
# This monitors RetroArch's reported resolution and switches modes
if [[ "$EMULATOR" == lr-* ]] && [[ "$TARGET_MODE" == "auto" || -z "$TARGET_MODE" ]]; then
    # For auto mode, start the watcher
    nohup bash "$TOOLKIT_DIR/lib/video.sh" watch "240p" >/dev/null 2>&1 &
    echo $! > /tmp/crt-mode-watcher.pid
else
    # For forced mode, just set it now
    if [[ -n "$TARGET_MODE" ]] && [[ "$TARGET_MODE" != "auto" ]]; then
        set_video_mode "$TARGET_MODE" 2>/dev/null
    fi
fi

exit 0
