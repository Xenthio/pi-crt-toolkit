#!/bin/bash
#
# Pi CRT Toolkit - Hotkey Configuration
# Sets up global keyboard hotkeys via triggerhappy
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/platform.sh"

TRIGGERHAPPY_CONF="/etc/triggerhappy/triggers.d/crt-toolkit.conf"
SYSTEMD_OVERRIDE="/etc/systemd/system/triggerhappy.service.d/override.conf"

#
# Default hotkey mappings
#
declare -A DEFAULT_HOTKEYS=(
    ["KEY_F7"]="crt-pal60"
    ["KEY_F8"]="crt-ntsc"
    ["KEY_F9"]="crt-240p"
    ["KEY_F10"]="crt-480i"
    ["KEY_F11"]="crt-288p"
    ["KEY_F12"]="crt-576i"
)

#
# Installation functions
#

install_triggerhappy() {
    if command -v thd &>/dev/null; then
        echo "triggerhappy already installed"
        return 0
    fi
    
    echo "Installing triggerhappy..."
    apt-get update -qq
    apt-get install -y -qq triggerhappy
}

# Create the hotkey config file
create_hotkey_config() {
    echo "Creating hotkey configuration..."
    
    mkdir -p "$(dirname "$TRIGGERHAPPY_CONF")"
    
    cat > "$TRIGGERHAPPY_CONF" << 'EOF'
# Pi CRT Toolkit - Global Hotkeys
# 
# Key Mapping:
#   F7  = PAL60 color mode
#   F8  = NTSC color mode
#   F9  = 240p (NTSC progressive)
#   F10 = 480i (NTSC interlaced)
#   F11 = 288p (PAL progressive)
#   F12 = 576i (PAL interlaced)
#
# Edit /usr/local/bin/crt-* scripts to customize behavior

KEY_F7      1    /usr/local/bin/crt-pal60
KEY_F8      1    /usr/local/bin/crt-ntsc
KEY_F9      1    /usr/local/bin/crt-240p
KEY_F10     1    /usr/local/bin/crt-480i
KEY_F11     1    /usr/local/bin/crt-288p
KEY_F12     1    /usr/local/bin/crt-576i
EOF
    
    echo "Created: $TRIGGERHAPPY_CONF"
}

# Configure triggerhappy to run as root (needed for tvservice/fbset)
configure_systemd() {
    echo "Configuring triggerhappy service..."
    
    mkdir -p "$(dirname "$SYSTEMD_OVERRIDE")"
    
    cat > "$SYSTEMD_OVERRIDE" << 'EOF'
[Service]
# Run as root for tvservice/fbset access
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
EOF
    
    systemctl daemon-reload
    echo "Created: $SYSTEMD_OVERRIDE"
}

# Install the command scripts
install_scripts() {
    init_platform
    
    echo "Installing command scripts..."
    echo "Detected driver: $DRIVER"
    
    local script_dir="/usr/local/bin"
    local lib_dir="/usr/local/lib/crt-toolkit"
    
    mkdir -p "$script_dir" "$lib_dir"
    
    # Copy lib files
    cp "$SCRIPT_DIR"/*.sh "$lib_dir/" 2>/dev/null || true
    chmod +x "$lib_dir"/*.sh 2>/dev/null || true
    
    if [[ "$DRIVER" == "kms" ]]; then
        # KMS mode - use kms-switch directly
        echo "Installing KMS-based scripts..."
        
        # crt-240p
        cat > "$script_dir/crt-240p" << 'SCRIPT'
#!/bin/bash
exec kms-switch 240p
SCRIPT
        
        # crt-480i
        cat > "$script_dir/crt-480i" << 'SCRIPT'
#!/bin/bash
exec kms-switch 480i
SCRIPT
        
        # crt-288p
        cat > "$script_dir/crt-288p" << 'SCRIPT'
#!/bin/bash
exec kms-switch 288p
SCRIPT
        
        # crt-576i
        cat > "$script_dir/crt-576i" << 'SCRIPT'
#!/bin/bash
exec kms-switch 576i
SCRIPT
        
        # crt-pal60 (set PAL color on current NTSC mode = PAL60)
        cat > "$script_dir/crt-pal60" << 'SCRIPT'
#!/bin/bash
CONN_ID=$(cat /sys/class/drm/card1-Composite-1/connector_id 2>/dev/null || modetest -M vc4 -c 2>/dev/null | grep -i composite | awk '{print $1}' | head -1)
modetest -M vc4 -w "$CONN_ID:TV mode:3" 2>/dev/null &
echo "pal60" > /tmp/crt-toolkit-color
echo "Color: PAL60"
SCRIPT
        
        # crt-ntsc
        cat > "$script_dir/crt-ntsc" << 'SCRIPT'
#!/bin/bash
CONN_ID=$(cat /sys/class/drm/card1-Composite-1/connector_id 2>/dev/null || modetest -M vc4 -c 2>/dev/null | grep -i composite | awk '{print $1}' | head -1)
modetest -M vc4 -w "$CONN_ID:TV mode:0" 2>/dev/null &
echo "ntsc" > /tmp/crt-toolkit-color
echo "Color: NTSC"
SCRIPT
    else
        # FKMS/Legacy mode - use tvservice
        echo "Installing tvservice-based scripts..."
        
        # crt-240p
        cat > "$script_dir/crt-240p" << 'SCRIPT'
#!/bin/bash
tvservice -c "NTSC 4:3 P" 2>/dev/null
fbset -depth 8 && fbset -depth 16
[[ "$(cat /tmp/crt-toolkit-color 2>/dev/null)" == "pal60" ]] && \
    python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
SCRIPT
        
        # crt-480i
        cat > "$script_dir/crt-480i" << 'SCRIPT'
#!/bin/bash
tvservice -c "NTSC 4:3" 2>/dev/null
fbset -depth 8 && fbset -depth 16
[[ "$(cat /tmp/crt-toolkit-color 2>/dev/null)" == "pal60" ]] && \
    python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
SCRIPT
        
        # crt-288p
        cat > "$script_dir/crt-288p" << 'SCRIPT'
#!/bin/bash
tvservice -c "PAL 4:3 P" 2>/dev/null
fbset -depth 8 && fbset -depth 16
SCRIPT
        
        # crt-576i
        cat > "$script_dir/crt-576i" << 'SCRIPT'
#!/bin/bash
tvservice -c "PAL 4:3" 2>/dev/null
fbset -depth 8 && fbset -depth 16
SCRIPT
        
        # crt-pal60
        cat > "$script_dir/crt-pal60" << 'SCRIPT'
#!/bin/bash
python3 /home/pi/tweakvec/tweakvec.py --preset PAL60 2>/dev/null
echo "pal60" > /tmp/crt-toolkit-color
SCRIPT
        
        # crt-ntsc
        cat > "$script_dir/crt-ntsc" << 'SCRIPT'
#!/bin/bash
python3 /home/pi/tweakvec/tweakvec.py --preset NTSC 2>/dev/null
echo "ntsc" > /tmp/crt-toolkit-color
SCRIPT
    fi
    
    # Make all executable
    chmod +x "$script_dir"/crt-{240p,480i,288p,576i,pal60,ntsc}
    
    echo "Installed scripts: crt-240p, crt-480i, crt-288p, crt-576i, crt-pal60, crt-ntsc"
}

# Enable and start triggerhappy
enable_service() {
    echo "Enabling triggerhappy service..."
    systemctl enable triggerhappy
    systemctl restart triggerhappy
    
    if systemctl is-active --quiet triggerhappy; then
        echo "triggerhappy is running"
    else
        echo "Warning: triggerhappy failed to start"
        systemctl status triggerhappy
    fi
}

# Full installation
install_hotkeys() {
    install_triggerhappy
    install_scripts
    create_hotkey_config
    configure_systemd
    enable_service
    
    echo ""
    echo "Hotkey installation complete!"
    echo ""
    echo "Available hotkeys:"
    echo "  F7  = PAL60 color"
    echo "  F8  = NTSC color"
    echo "  F9  = 240p"
    echo "  F10 = 480i"
    echo "  F11 = 288p (PAL)"
    echo "  F12 = 576i (PAL)"
}

# Uninstall hotkeys
uninstall_hotkeys() {
    echo "Removing hotkey configuration..."
    
    rm -f "$TRIGGERHAPPY_CONF"
    rm -f "$SYSTEMD_OVERRIDE"
    rm -f /usr/local/bin/crt-{240p,480i,288p,576i,pal60,ntsc}
    
    systemctl daemon-reload
    systemctl restart triggerhappy 2>/dev/null
    
    echo "Hotkeys removed"
}

# Show status
show_status() {
    echo "Triggerhappy status:"
    systemctl is-active triggerhappy && echo "  Service: running" || echo "  Service: not running"
    
    echo ""
    echo "Config file:"
    if [[ -f "$TRIGGERHAPPY_CONF" ]]; then
        echo "  $TRIGGERHAPPY_CONF (exists)"
        cat "$TRIGGERHAPPY_CONF" | grep -v "^#" | grep -v "^$"
    else
        echo "  Not configured"
    fi
    
    echo ""
    echo "Installed scripts:"
    for script in crt-{240p,480i,288p,576i,pal60,ntsc}; do
        if [[ -x "/usr/local/bin/$script" ]]; then
            echo "  /usr/local/bin/$script ✓"
        else
            echo "  /usr/local/bin/$script ✗"
        fi
    done
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        install)
            install_hotkeys
            ;;
        uninstall)
            uninstall_hotkeys
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 <install|uninstall|status>"
            exit 1
            ;;
    esac
fi
