#!/bin/bash
#
# Pi CRT RetroPie Setup Script
# Run this on a fresh Raspberry Pi OS Bookworm Lite (64-bit)
#
# Usage: curl -sL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/setup-retropie-crt.sh | bash
#

set -e

echo "============================================="
echo "  Pi CRT RetroPie Setup Script"
echo "============================================="
echo ""

# Configuration - edit these before running!
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASS="${WIFI_PASS:-}"
WIFI_COUNTRY="${WIFI_COUNTRY:-AU}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "Don't run as root - run as pi user with sudo access"
    exit 1
fi

echo "[1/8] Updating system..."
sudo apt-get update
sudo apt-get upgrade -y

echo "[2/8] Setting keyboard layout to $KEYBOARD_LAYOUT..."
sudo sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$KEYBOARD_LAYOUT\"/" /etc/default/keyboard
sudo setupcon -k

echo "[3/8] Configuring WiFi..."
if [[ -n "$WIFI_SSID" ]]; then
    sudo nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" 2>/dev/null || \
    sudo bash -c "cat >> /etc/wpa_supplicant/wpa_supplicant.conf << EOF
country=$WIFI_COUNTRY
network={
    ssid=\"$WIFI_SSID\"
    psk=\"$WIFI_PASS\"
}
EOF"
    echo "WiFi configured for $WIFI_SSID"
else
    echo "Skipping WiFi (set WIFI_SSID and WIFI_PASS to configure)"
fi

echo "[4/8] Enabling SSH..."
sudo systemctl enable ssh
sudo systemctl start ssh

echo "[5/8] Installing RetroPie dependencies..."
sudo apt-get install -y git lsb-release

echo "[6/8] Installing RetroPie..."
cd ~
if [[ ! -d RetroPie-Setup ]]; then
    git clone --depth=1 https://github.com/RetroPie/RetroPie-Setup.git
fi
cd RetroPie-Setup

# Install basic packages (this takes a while!)
sudo ./retropie_setup.sh <<< $'U\nB\n'  # Update and Basic Install

echo "[7/8] Installing CRT Toolkit..."
cd /opt
sudo git clone https://github.com/Xenthio/pi-crt-toolkit.git crt-toolkit
sudo chmod +x /opt/crt-toolkit/lib/*.sh

# Clone tweakvec for VEC control
sudo git clone --depth 1 https://github.com/kFYatek/tweakvec.git /opt/crt-toolkit/lib/tweakvec

# Install hotkeys
sudo /opt/crt-toolkit/lib/hotkeys.sh install

echo "[7b/8] Installing RetroArch runcommand-menu scripts..."
mkdir -p /tmp/bropi-install
cd /tmp/bropi-install

# Clone DiegoDimuro's CRT broPi repo for menu scripts and shaders
git clone --depth 1 https://github.com/DiegoDimuro/crt-broPi4-composite.git bropi 2>/dev/null && {
    # Install runcommand-menu scripts
    mkdir -p ~/RetroPie/configs/all/runcommand-menu
    cp bropi/configs/all/runcommand-menu/*.sh ~/RetroPie/configs/all/runcommand-menu/ 2>/dev/null || true
    chmod +x ~/RetroPie/configs/all/runcommand-menu/*.sh 2>/dev/null || true
    
    # Install alignment shaders
    mkdir -p ~/RetroPie/configs/all/retroarch/shaders
    cp -r bropi/shaders/* ~/RetroPie/configs/all/retroarch/shaders/ 2>/dev/null || true
    
    echo "✓ RetroArch menu scripts and shaders installed"
} || echo "⚠ Could not install broPi scripts (offline?), continuing..."

cd /
rm -rf /tmp/bropi-install

echo "[8/8] Configuring composite video output..."

# Add KMS composite to config.txt
if ! grep -q "dtoverlay=vc4-kms-v3d,composite=1" /boot/firmware/config.txt; then
    sudo bash -c 'cat >> /boot/firmware/config.txt << EOF

# CRT Composite Output
dtoverlay=vc4-kms-v3d,composite=1
# Disable HDMI to ensure composite works
hdmi_ignore_hotplug=1
EOF'
fi

# Add video mode to cmdline.txt
if ! grep -q "video=Composite-1" /boot/firmware/cmdline.txt; then
    sudo sed -i 's/$/ video=Composite-1:720x480@60ie,tv_mode=PAL/' /boot/firmware/cmdline.txt
fi

# Fix permissions for RetroPie
sudo chmod 755 /root
sudo chown -R $USER:$USER /opt/retropie/configs/ 2>/dev/null || true
mkdir -p ~/RetroPie/roms

echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
echo "Hotkeys:"
echo "  F10 = Toggle color (PAL60 <-> NTSC)"
echo "  F11 = Toggle scan (progressive <-> interlaced)"
echo "  F12 = Toggle mode (240p <-> 480i)"
echo ""
echo "Reboot to apply video settings:"
echo "  sudo reboot"
echo ""
