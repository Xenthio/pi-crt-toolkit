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
YELLOW='\033[1;33m'
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

# Detect OS
OS_CODENAME=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2 || echo "unknown")
echo -e "OS: ${GREEN}$OS_CODENAME${NC}"

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
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true

# Create symlink for main tool
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit

# Build and install KMS mode setter (for Trixie/Bookworm)
if [[ "$OS_CODENAME" == "trixie" || "$OS_CODENAME" == "bookworm" ]]; then
    echo ""
    echo -e "${YELLOW}Building KMS mode tools...${NC}"
    
    # Install build deps if needed
    if [[ ! -f /usr/include/libdrm/xf86drm.h ]]; then
        apt-get install -y -qq libdrm-dev gcc
    fi
    
    # Compile setmode
    if [[ -f "$INSTALL_DIR/src/setmode.c" ]]; then
        gcc -o "$INSTALL_DIR/bin/crt-setmode" "$INSTALL_DIR/src/setmode.c" \
            -ldrm -I/usr/include/libdrm 2>/dev/null
        
        if [[ -f "$INSTALL_DIR/bin/crt-setmode" ]]; then
            cp "$INSTALL_DIR/bin/crt-setmode" /usr/local/bin/
            chmod +x /usr/local/bin/crt-setmode
            echo -e "  ${GREEN}✓${NC} crt-setmode installed"
        fi
    fi
    
    # Install KMS switch script
    if [[ -f "$INSTALL_DIR/scripts/kms-switch.sh" ]]; then
        cp "$INSTALL_DIR/scripts/kms-switch.sh" /usr/local/bin/kms-switch
        chmod +x /usr/local/bin/kms-switch
        echo -e "  ${GREEN}✓${NC} kms-switch installed"
    fi
    
    # Install modetest if not present
    if ! command -v modetest &>/dev/null; then
        apt-get install -y -qq libdrm-tests
    fi
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""

# Launch the toolkit
exec "$INSTALL_DIR/crt-toolkit.sh"
