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
#   3. Configure in /etc/crt-toolkit/display-detect.conf
#

set -e

#
# Configuration
#

CONFIG_DIR="/etc/crt-toolkit"
DETECT_CONF="$CONFIG_DIR/display-detect.conf"
STATE_FILE="/var/lib/crt-toolkit/display-state"

# Default settings (overridden by config file)
ENABLE_SPEAKER=false
SPEAKER_GPIO=18
SPEAKER_GND_INFO="GND (pin 6, 9, 14, 20, 25, 30, 34, or 39)"

# Boot config location (auto-detected)
BOOT_CONFIG=""

# Load config file if exists
load_config() {
    if [[ -f "$DETECT_CONF" ]]; then
        source "$DETECT_CONF"
    fi
}

# Create default config file
create_default_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$DETECT_CONF" << 'EOF'
# CRT Toolkit - Display Detection Configuration
#
# Enable audio feedback via PC speaker/buzzer
# Set to true and configure GPIO pin to enable
ENABLE_SPEAKER=false

# GPIO pin for speaker positive terminal
# Common choices: 18 (PWM capable), 17, 27
SPEAKER_GPIO=18

# Informational: Which pin to use for ground
# (not used by script, just for reference)
SPEAKER_GND_INFO="GND (pin 6, 9, 14, 20, 25, 30, 34, or 39)"

# Speaker frequency settings (Hz)
BEEP_FREQ_HIGH=2000
BEEP_FREQ_LOW=800

# Beep durations (milliseconds)
BEEP_SHORT=100
BEEP_LONG=300

# Auto-reboot when display config changes
# Set to false to only log changes without rebooting
AUTO_REBOOT=true
EOF
    echo "Created default config at $DETECT_CONF"
}

#
# Detect boot config location
#

detect_boot_config() {
    if [[ -f "/boot/firmware/config.txt" ]]; then
        BOOT_CONFIG="/boot/firmware/config.txt"
    else
        BOOT_CONFIG="/boot/config.txt"
    fi
}

#
# Logging
#

log() {
    echo "[display-detect] $*"
    logger -t crt-display-detect "$*" 2>/dev/null || true
}

#
# GPIO Speaker Functions
#

speaker_init() {
    [[ "$ENABLE_SPEAKER" != "true" ]] && return 1
    
    if [[ -d /sys/class/gpio/gpio$SPEAKER_GPIO ]]; then
        return 0
    fi
    echo $SPEAKER_GPIO > /sys/class/gpio/export 2>/dev/null || return 1
    echo out > /sys/class/gpio/gpio$SPEAKER_GPIO/direction 2>/dev/null || return 1
    return 0
}

speaker_cleanup() {
    [[ "$ENABLE_SPEAKER" != "true" ]] && return
    echo $SPEAKER_GPIO > /sys/class/gpio/unexport 2>/dev/null || true
}

# Simple beep using GPIO toggle or hardware PWM
beep() {
    [[ "$ENABLE_SPEAKER" != "true" ]] && return
    
    local duration_ms="${1:-100}"
    local freq="${2:-1000}"
    
    if ! speaker_init; then
        return
    fi
    
    # Try hardware PWM first (cleaner sound)
    if [[ -d /sys/class/pwm/pwmchip0 ]] && [[ "$SPEAKER_GPIO" == "18" || "$SPEAKER_GPIO" == "12" ]]; then
        local pwm_channel=0
        [[ "$SPEAKER_GPIO" == "12" ]] && pwm_channel=0
        [[ "$SPEAKER_GPIO" == "18" ]] && pwm_channel=0
        
        echo $pwm_channel > /sys/class/pwm/pwmchip0/export 2>/dev/null || true
        local pwm_path="/sys/class/pwm/pwmchip0/pwm$pwm_channel"
        
        if [[ -d "$pwm_path" ]]; then
            local period=$((1000000000 / freq))
            echo $period > "$pwm_path/period" 2>/dev/null || true
            echo $((period / 2)) > "$pwm_path/duty_cycle" 2>/dev/null || true
            echo 1 > "$pwm_path/enable" 2>/dev/null || true
            
            # Sleep for duration
            local sleep_time=$(echo "scale=3; $duration_ms/1000" | bc 2>/dev/null || echo "0.1")
            sleep $sleep_time
            
            echo 0 > "$pwm_path/enable" 2>/dev/null || true
            return
        fi
    fi
    
    # Fallback: software GPIO toggle (lower quality)
    local gpio_file="/sys/class/gpio/gpio$SPEAKER_GPIO/value"
    if [[ -f "$gpio_file" ]]; then
        local period_us=$((1000000 / freq))
        local half_period=$((period_us / 2))
        local cycles=$((duration_ms * freq / 1000))
        
        for ((i=0; i<cycles; i++)); do
            echo 1 > "$gpio_file"
            usleep $half_period 2>/dev/null || sleep 0.0005
            echo 0 > "$gpio_file"
            usleep $half_period 2>/dev/null || sleep 0.0005
        done
    fi
}

# Beep patterns
beep_hdmi() {
    # Two short high beeps = HDMI detected
    local freq=${BEEP_FREQ_HIGH:-2000}
    local dur=${BEEP_SHORT:-100}
    beep $dur $freq
    sleep 0.1
    beep $dur $freq
}

beep_composite() {
    # One long low beep = Composite mode
    local freq=${BEEP_FREQ_LOW:-800}
    local dur=${BEEP_LONG:-300}
    beep $dur $freq
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
        local status=$(tvservice -s 2>/dev/null)
        if echo "$status" | grep -qi "HDMI"; then
            return 0
        fi
    fi
    
    # Method 3: Check EDID presence
    for edid in /sys/class/drm/card*-HDMI-*/edid; do
        if [[ -f "$edid" ]] && [[ -s "$edid" ]]; then
            return 0
        fi
    done
    
    return 1
}

get_config_mode() {
    if grep -qE "^hdmi_ignore_hotplug=1" "$BOOT_CONFIG" 2>/dev/null; then
        echo "composite"
    elif grep -qE "^enable_tvout=1" "$BOOT_CONFIG" 2>/dev/null; then
        if grep -qE "^hdmi_force_hotplug=1" "$BOOT_CONFIG" 2>/dev/null; then
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

enable_hdmi_config() {
    log "Configuring for HDMI output"
    
    cp "$BOOT_CONFIG" "$BOOT_CONFIG.bak"
    
    sed -i '/^hdmi_ignore_hotplug=1/d' "$BOOT_CONFIG"
    sed -i '/^enable_tvout=1/d' "$BOOT_CONFIG"
    sed -i '/^sdtv_mode=/d' "$BOOT_CONFIG"
    sed -i '/^sdtv_aspect=/d' "$BOOT_CONFIG"
    
    if ! grep -qE "^hdmi_force_hotplug=1" "$BOOT_CONFIG"; then
        echo "hdmi_force_hotplug=1" >> "$BOOT_CONFIG"
    fi
}

enable_composite_config() {
    log "Configuring for Composite output"
    
    cp "$BOOT_CONFIG" "$BOOT_CONFIG.bak"
    
    sed -i '/^hdmi_force_hotplug=1/d' "$BOOT_CONFIG"
    
    if ! grep -qE "^hdmi_ignore_hotplug=1" "$BOOT_CONFIG"; then
        echo "hdmi_ignore_hotplug=1" >> "$BOOT_CONFIG"
    fi
    if ! grep -qE "^enable_tvout=1" "$BOOT_CONFIG"; then
        echo "enable_tvout=1" >> "$BOOT_CONFIG"
    fi
    if ! grep -qE "^sdtv_mode=" "$BOOT_CONFIG"; then
        echo "sdtv_mode=0" >> "$BOOT_CONFIG"
    fi
    if ! grep -qE "^sdtv_aspect=" "$BOOT_CONFIG"; then
        echo "sdtv_aspect=1" >> "$BOOT_CONFIG"
    fi
}

#
# State Management
#

save_state() {
    local state="$1"
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$state" > "$STATE_FILE"
}

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
    detect_boot_config
    load_config
    
    local current_config=$(get_config_mode)
    local hdmi_connected=false
    local need_reboot=false
    local auto_reboot=${AUTO_REBOOT:-true}
    
    log "Starting display detection (config: $current_config, speaker: $ENABLE_SPEAKER)"
    
    if detect_hdmi; then
        hdmi_connected=true
        log "HDMI detected"
    else
        log "No HDMI detected, assuming Composite"
    fi
    
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
    
    speaker_cleanup
    
    if [[ "$need_reboot" == "true" ]] && [[ "$auto_reboot" == "true" ]]; then
        log "Config changed, rebooting in 3 seconds..."
        sleep 3
        reboot
    elif [[ "$need_reboot" == "true" ]]; then
        log "Config changed but AUTO_REBOOT=false, reboot manually to apply"
    fi
    
    log "Display detection complete, using $(get_config_mode)"
}

#
# CLI
#

show_help() {
    cat << EOF
Usage: $0 [command]

Commands:
  (none)        Run detection and switch config if needed
  --check       Just check what's connected (no changes)
  --init-config Create default configuration file
  --status      Show current state
  --help        Show this help

Configuration: $DETECT_CONF

Speaker Setup (optional):
  1. Edit $DETECT_CONF
  2. Set ENABLE_SPEAKER=true
  3. Set SPEAKER_GPIO to your GPIO pin (default: 18)
  4. Connect speaker positive to GPIO $SPEAKER_GPIO
  5. Connect speaker negative to $SPEAKER_GND_INFO

Beep Patterns:
  Two short high beeps = HDMI detected
  One long low beep = Composite mode
  Rising tone = Switching configs (will reboot)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --check|--check-only)
            detect_boot_config
            if detect_hdmi; then
                echo "hdmi"
            else
                echo "composite"
            fi
            ;;
        --init-config)
            create_default_config
            ;;
        --status)
            detect_boot_config
            load_config
            echo "Boot config: $BOOT_CONFIG"
            echo "Current mode: $(get_config_mode)"
            echo "Last state: $(get_state)"
            echo "Speaker enabled: $ENABLE_SPEAKER"
            [[ "$ENABLE_SPEAKER" == "true" ]] && echo "Speaker GPIO: $SPEAKER_GPIO"
            ;;
        --help|-h)
            show_help
            ;;
        "")
            main
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
fi
