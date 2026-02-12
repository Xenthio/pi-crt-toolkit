#!/bin/bash
#
# Pi CRT Toolkit Installer
# One-line install: curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | sudo bash
#

set -e

REPO_URL="https://github.com/Xenthio/pi-crt-toolkit"
INSTALL_DIR="/opt/crt-toolkit"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║         Pi CRT Toolkit Installer           ║"
echo "║   Raspberry Pi Composite Video Setup       ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Try: curl -sSL <url> | sudo bash"
    exit 1
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo -e "OS: ${GREEN}$PRETTY_NAME${NC}"
else
    echo -e "${YELLOW}Warning: Could not detect OS${NC}"
fi

# Detect Pi model
if [[ -f /proc/device-tree/model ]]; then
    PI_MODEL=$(cat /proc/device-tree/model | tr -d '\0')
    echo -e "Hardware: ${GREEN}$PI_MODEL${NC}"
    
    if [[ "$PI_MODEL" == *"Pi 5"* ]]; then
        echo -e "${RED}Error: Raspberry Pi 5 does not have composite video output${NC}"
        exit 1
    fi
fi

# Check for composite support
if ! grep -q "Pi 4\|Pi 3\|Pi 2\|Pi Zero\|Pi Model" /proc/device-tree/model 2>/dev/null; then
    echo -e "${YELLOW}Warning: This Pi model may not support composite output${NC}"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

echo ""

# Install dependencies
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq dialog git python3

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard origin/main
else
    echo "Downloading Pi CRT Toolkit..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# Make executable
chmod +x "$INSTALL_DIR/crt-toolkit.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true

# Create symlink
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Run 'sudo crt-toolkit' to start the setup menu."
echo ""

# Ask to run
read -p "Launch CRT Toolkit now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    exec /usr/local/bin/crt-toolkit
fi
