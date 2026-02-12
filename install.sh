#!/bin/bash
#
# CRT Toolkit Installer
# Downloads and runs the CRT Toolkit setup
#

set -e

REPO_URL="https://github.com/Xenthio/crt-toolkit"
INSTALL_DIR="/opt/crt-toolkit"

echo "╔════════════════════════════════════════╗"
echo "║       CRT Toolkit Installer            ║"
echo "║   Raspberry Pi 4 Composite Output      ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)"
    exit 1
fi

# Check Pi 4
if ! grep -q "Raspberry Pi 4" /proc/cpuinfo 2>/dev/null; then
    echo "Warning: This toolkit is designed for Raspberry Pi 4"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Install dependencies
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq dialog git python3

# Clone or update repository
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "Downloading CRT Toolkit..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Create symlink
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit
chmod +x "$INSTALL_DIR/crt-toolkit.sh"

echo ""
echo "Installation complete!"
echo ""
echo "Run 'sudo crt-toolkit' to start the setup menu."
echo ""

# Ask to run now
read -p "Launch CRT Toolkit now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    exec /usr/local/bin/crt-toolkit
fi
