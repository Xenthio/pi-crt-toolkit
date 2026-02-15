#!/bin/bash
#
# Pi CRT Toolkit - Hotkey Configuration
# Sets up global keyboard hotkeys via triggerhappy
#
# All hotkeys use direct VEC access - works on Legacy, FKMS, and KMS!
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(dirname "$SCRIPT_DIR")"

TRIGGERHAPPY_CONF="/etc/triggerhappy/triggers.d/crt-toolkit.conf"
SYSTEMD_OVERRIDE="/etc/systemd/system/triggerhappy.service.d/override.conf"

#
# Installation
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

create_hotkey_config() {
    echo "Creating hotkey configuration..."
    
    mkdir -p "$(dirname "$TRIGGERHAPPY_CONF")"
    
    cat > "$TRIGGERHAPPY_CONF" << 'EOF'
# Pi CRT Toolkit - Global Hotkeys
# 
# All hotkeys use direct VEC hardware access via /dev/mem
# Works on ALL drivers: Legacy, FKMS, KMS
#
# Key Mapping:
#   F7  = PAL60 color mode
#   F8  = NTSC color mode
#   F9  = Progressive scan (240p)
#   F10 = Interlaced scan (480i)
#   F11 = Toggle progressive/interlaced
#   F12 = (reserved)

KEY_F7      1    /usr/local/bin/crt-pal60
KEY_F8      1    /usr/local/bin/crt-ntsc
KEY_F9      1    /usr/local/bin/crt-240p
KEY_F10     1    /usr/local/bin/crt-480i
KEY_F11     1    /usr/local/bin/crt-toggle
EOF
    
    echo "Created: $TRIGGERHAPPY_CONF"
}

configure_systemd() {
    echo "Configuring triggerhappy service..."
    
    mkdir -p "$(dirname "$SYSTEMD_OVERRIDE")"
    
    cat > "$SYSTEMD_OVERRIDE" << 'EOF'
[Service]
# Run as root for /dev/mem access
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
EOF
    
    systemctl daemon-reload
    echo "Created: $SYSTEMD_OVERRIDE"
}

install_scripts() {
    echo "Installing hotkey scripts..."
    
    local script_dir="/usr/local/bin"
    local video_sh="$TOOLKIT_DIR/lib/video.sh"
    
    # All scripts use the unified video.sh which does direct VEC access
    # This works on ALL drivers!
    
    # F7 - PAL60
    cat > "$script_dir/crt-pal60" << EOF
#!/bin/bash
exec "$video_sh" pal60
EOF
    
    # F8 - NTSC
    cat > "$script_dir/crt-ntsc" << EOF
#!/bin/bash
exec "$video_sh" ntsc
EOF
    
    # F9 - Progressive (240p)
    cat > "$script_dir/crt-240p" << EOF
#!/bin/bash
exec "$video_sh" progressive
EOF
    
    # F10 - Interlaced (480i)
    cat > "$script_dir/crt-480i" << EOF
#!/bin/bash
exec "$video_sh" interlaced
EOF
    
    # F11 - Toggle
    cat > "$script_dir/crt-toggle" << EOF
#!/bin/bash
exec "$video_sh" toggle
EOF
    
    chmod +x "$script_dir"/crt-{pal60,ntsc,240p,480i,toggle}
    
    echo "Installed: crt-pal60, crt-ntsc, crt-240p, crt-480i, crt-toggle"
}

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

install_hotkeys() {
    install_triggerhappy
    install_scripts
    create_hotkey_config
    configure_systemd
    enable_service
    
    echo ""
    echo "Hotkey installation complete!"
    echo ""
    echo "Available hotkeys (direct VEC control - works on all drivers!):"
    echo "  F7  = PAL60 color"
    echo "  F8  = NTSC color"
    echo "  F9  = Progressive scan (240p)"
    echo "  F10 = Interlaced scan (480i)"
    echo "  F11 = Toggle progressive/interlaced"
}

uninstall_hotkeys() {
    echo "Removing hotkey configuration..."
    
    rm -f "$TRIGGERHAPPY_CONF"
    rm -f "$SYSTEMD_OVERRIDE"
    rm -f /usr/local/bin/crt-{pal60,ntsc,240p,480i,toggle}
    
    systemctl daemon-reload
    systemctl restart triggerhappy 2>/dev/null
    
    echo "Hotkeys removed"
}

show_status() {
    echo "=== Triggerhappy Status ==="
    systemctl is-active triggerhappy && echo "Service: running" || echo "Service: not running"
    
    echo ""
    echo "=== Config File ==="
    if [[ -f "$TRIGGERHAPPY_CONF" ]]; then
        echo "$TRIGGERHAPPY_CONF exists"
        grep -v "^#" "$TRIGGERHAPPY_CONF" | grep -v "^$"
    else
        echo "Not configured"
    fi
    
    echo ""
    echo "=== Installed Scripts ==="
    for script in crt-{pal60,ntsc,240p,480i,toggle}; do
        if [[ -x "/usr/local/bin/$script" ]]; then
            echo "  $script ✓"
        else
            echo "  $script ✗"
        fi
    done
}

# CLI
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
