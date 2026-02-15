#!/bin/bash
#
# Pi CRT Toolkit - Early Boot Display Detection
# Detects which display (HDMI or Composite) is connected and configures accordingly
#
# Pi 4 Limitation: HDMI and Composite cannot be active simultaneously.
# This script runs early in boot to detect what's connected and update config.
#
# Installation:
#   1. Copy to /opt/crt-toolkit/scripts/boot-display-detect.sh
#   2. Add systemd service or call from /etc/rc.local
#   3. Optionally connect a PC speaker to GPIO for audio feedback
#
# GPIO Speaker (optional):
#   Connect a PC speaker between GPIO 18 (PWM) and GND
#   The script will play a beep pattern to indicate detected display
#

set -e

CONFIG_FILE=""
STATE_FILE="/var/lib/crt-toolkit/display-state"
SPEAKER_GPIO=18

# Detect config.txt location
if [[ -f "/boot/firmware/config.txt" ]]; then
    CONFIG_FILE="/boot/firmware/config.txt"
else
    CONFIG_FILE="/boot/config.txt"
fi

# Logging
log() {
    echo "[display-detect] $*"
    logger -t crt-display-detect "$*"
}

#
# GPIO Speaker Functions
#

speaker_init() {
    if [[ -d /sys/class/gpio/gpio$SPEAKER_GPIO ]]; then
        return 0
    fi
    echo $SPEAKER_GPIO > /sys/class/gpio/export 2>/dev/null || true
    echo out > /sys/class/gpio/gpio$SPEAKER_GPIO/direction 2>/dev/null || true
}

# Simple beep using GPIO toggle (crude but works)
beep() {
    local duration_ms="${1:-100}"
    local freq="${2:-1000}"
    
    speaker_init
    
    local period_us=$((1000000 / freq))
    local half_period=$((period_us / 2))
    local cycles=$((duration_ms * freq / 1000))
    
    # Use hardware PWM if available, otherwise software toggle
    if [[ -f /sys/class/pwm/pwmchip0/export ]]; then
        # Hardware PWM on GPIO 18
        echo 0 > /sys/class/pwm/pwmchip0/export 2>/dev/null || true
        echo $((1000000000 / freq)) > /sys/class/pwm/pwmchip0/pwm0/period 2>/dev/null || true
        echo $((500000000 / freq)) > /sys/class/pwm/pwmchip0/pwm0/duty_cycle 2>/dev/null || true
        echo 1 > /sys/class/pwm/pwmchip0/pwm0/enable 2>/dev/null || true
        sleep $(echo "scale=3; $duration_ms/1000" | bc)
        echo 0 > /sys/class/pwm/pwmchip0/pwm0/enable 2>/dev/null || true
    else
        # Software toggle (lower quality)
        local gpio_file="/sys/class/gpio/gpio$SPEAKER_GPIO/value"
        if [[ -f "$gpio_file" ]]; then
            for ((i=0; i<cycles; i++)); do
                echo 1 > "$gpio_file"
                usleep $half_period 2>/dev/null || sleep 0.0005
                echo 0 > "$gpio_file"
                usleep $half_period 2>/dev/null || sleep 0.0005
            done
        fi
    fi
}

# Beep patterns for different states
beep_hdmi() {
    # Two short high beeps = HDMI detected
    beep 100 2000
    sleep 0.1
    beep 100 2000
}

beep_composite() {
    # One long low beep = Composite mode
    beep 300 800
}

beep_switching() {
    # Rising tone = switching configs, will reboot
    beep 100 600
    beep 100 800
    beep 100 1000
    beep 100 1200
}

#
# Display Detection
#

# Check if HDMI is connected
# Returns 0 if HDMI connected, 1 if not
detect_hdmi() {
    # Method 1: Check DRM connector status
    for connector in /sys/class/drm/card*-HDMI-*; do
        if [[ -f "$connector/status" ]]; then
            if grep -q "connected" "$connector/status" 2>/dev/null; then
                return 0
            fi
        fi
    done
    
    # Method 2: tvservice (FKMS only)
    if command -v tvservice &>/dev/null; then
        if tvservice -s 2>/dev/null | grep -qi "HDMI"; then
            return 0
        fi
    fi
    
    # Method 3: vcgencmd
    if command -v vcgencmd &>/dev/null; then
        local hpd=$(vcgencmd get_config hdmi_force_hotplug 2>/dev/null | cut -d= -f2)
        if [[ "$hpd" == "1" ]]; then
            # Forced HDMI, check if actually connected
            if vcgencmd display_power 2>/dev/null | grep -q "1"; then
                return 0
            fi
        fi
    fi
    
    return 1
}

# Check current config mode
get_config_mode() {
    if grep -qE "^hdmi_ignore_hotplug=1" "$CONFIG_FILE" 2>/dev/null; then
        echo "composite"
    elif grep -qE "^enable_tvout=1" "$CONFIG_FILE" 2>/dev/null; then
        if grep -qE "^hdmi_force_hotplug=1" "$CONFIG_FILE" 2>/dev/null; then
            echo "hdmi"
        else
            echo "composite"
        fi
    else
        echo "hdmi"
    fi
}

#
# Config Modification
#

# Enable HDMI mode in config.txt
enable_hdmi_config() {
    log "Configuring for HDMI output"
    
    # Backup current config
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    
    # Remove composite-specific settings
    sed -i '/^hdmi_ignore_hotplug=1/d' "$CONFIG_FILE"
    sed -i '/^enable_tvout=1/d' "$CONFIG_FILE"
    sed -i '/^sdtv_mode=/d' "$CONFIG_FILE"
    sed -i '/^sdtv_aspect=/d' "$CONFIG_FILE"
    
    # Ensure HDMI settings
    if ! grep -qE "^hdmi_force_hotplug=1" "$CONFIG_FILE"; then
        echo "hdmi_force_hotplug=1" >> "$CONFIG_FILE"
    fi
}

# Enable Composite mode in config.txt
enable_composite_config() {
    log "Configuring for Composite output"
    
    # Backup current config
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    
    # Remove HDMI force
    sed -i '/^hdmi_force_hotplug=1/d' "$CONFIG_FILE"
    
    # Add composite settings if not present
    if ! grep -qE "^hdmi_ignore_hotplug=1" "$CONFIG_FILE"; then
        echo "hdmi_ignore_hotplug=1" >> "$CONFIG_FILE"
    fi
    if ! grep -qE "^enable_tvout=1" "$CONFIG_FILE"; then
        echo "enable_tvout=1" >> "$CONFIG_FILE"
    fi
    if ! grep -qE "^sdtv_mode=" "$CONFIG_FILE"; then
        echo "sdtv_mode=0" >> "$CONFIG_FILE"
    fi
    if ! grep -qE "^sdtv_aspect=" "$CONFIG_FILE"; then
        echo "sdtv_aspect=1" >> "$CONFIG_FILE"
    fi
}

#
# State Management
#

# Save current display state
save_state() {
    local state="$1"
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$state" > "$STATE_FILE"
}

# Get last saved state
get_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

#
# Main Logic
#

main() {
    local current_config=$(get_config_mode)
    local last_state=$(get_state)
    local hdmi_connected=false
    local need_reboot=false
    
    log "Starting display detection (current config: $current_config)"
    
    # Detect HDMI
    if detect_hdmi; then
        hdmi_connected=true
        log "HDMI detected"
    else
        log "No HDMI detected, assuming Composite"
    fi
    
    # Determine if we need to switch
    if [[ "$hdmi_connected" == "true" ]]; then
        if [[ "$current_config" != "hdmi" ]]; then
            log "Switching from $current_config to HDMI"
            beep_switching
            enable_hdmi_config
            save_state "hdmi"
            need_reboot=true
        else
            beep_hdmi
            save_state "hdmi"
        fi
    else
        if [[ "$current_config" != "composite" ]]; then
            log "Switching from $current_config to Composite"
            beep_switching
            enable_composite_config
            save_state "composite"
            need_reboot=true
        else
            beep_composite
            save_state "composite"
        fi
    fi
    
    # Reboot if config changed
    if [[ "$need_reboot" == "true" ]]; then
        log "Config changed, rebooting in 3 seconds..."
        sleep 3
        reboot
    fi
    
    log "Display detection complete, using $current_config"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for --check-only flag
    if [[ "$1" == "--check-only" ]]; then
        if detect_hdmi; then
            echo "hdmi"
        else
            echo "composite"
        fi
        exit 0
    fi
    
    main "$@"
fi
