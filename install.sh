#!/bin/bash
#
# Pi CRT Toolkit - Quick Installer
# Downloads the toolkit and launches the setup menu
#
# One-line install:
#   curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | sudo bash
#

set -e

REPO_URL="https://github.com/Xenthio/pi-crt-toolkit"
INSTALL_DIR="/opt/crt-toolkit"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║         Pi CRT Toolkit Installer           ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Run with sudo${NC}"
    exit 1
fi

# Check Pi model
if [[ -f /proc/device-tree/model ]]; then
    model=$(tr -d '\0' < /proc/device-tree/model)
    echo -e "Detected: ${GREEN}$model${NC}"
    
    if [[ "$model" == *"Pi 5"* ]]; then
        echo -e "${RED}Error: Pi 5 has no composite output${NC}"
        exit 1
    fi
fi

echo ""
echo "Downloading Pi CRT Toolkit..."

# Install git if needed
command -v git &>/dev/null || apt-get install -y -qq git

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard origin/main
else
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/crt-toolkit.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true

# Create symlink
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit

echo ""
echo -e "${GREEN}Download complete!${NC}"
echo ""

# Launch the toolkit
exec "$INSTALL_DIR/crt-toolkit.sh"
