#!/bin/bash
#
# Pi CRT Toolkit - Quick Installer
# Downloads the toolkit and optionally sets up RetroPie integration
#
# One-line install:
#   curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | sudo bash
#

set -e

REPO_URL="https://github.com/Xenthio/pi-crt-toolkit"
INSTALL_DIR="/opt/crt-toolkit"
RETROPIE_CONFIGS="/opt/retropie/configs"
TWEAKVEC_REPO="https://github.com/kFYatek/tweakvec.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# Detect driver
DRIVER="unknown"
if grep -qE "^dtoverlay=vc4-fkms-v3d" /boot/config.txt 2>/dev/null || \
   grep -qE "^dtoverlay=vc4-fkms-v3d" /boot/firmware/config.txt 2>/dev/null; then
    DRIVER="fkms"
elif grep -qE "^dtoverlay=vc4-kms-v3d" /boot/config.txt 2>/dev/null || \
     grep -qE "^dtoverlay=vc4-kms-v3d" /boot/firmware/config.txt 2>/dev/null; then
    DRIVER="kms"
elif tvservice -s &>/dev/null; then
    DRIVER="legacy"
fi
echo -e "Driver: ${GREEN}$DRIVER${NC}"

# Detect RetroPie
HAS_RETROPIE=false
if [[ -d "$RETROPIE_CONFIGS" ]]; then
    HAS_RETROPIE=true
    echo -e "RetroPie: ${GREEN}Found${NC}"
else
    echo -e "RetroPie: ${YELLOW}Not found${NC}"
fi

echo ""
echo "Downloading Pi CRT Toolkit..."

# Install git if needed
command -v git &>/dev/null || apt-get install -y -qq git

# Clone or update toolkit
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
chmod +x "$INSTALL_DIR/retropie/"*.sh 2>/dev/null || true

# Create symlink for main tool
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit

echo -e "  ${GREEN}✓${NC} Core toolkit installed"""

#
# Driver-specific setup
#

if [[ "$DRIVER" == "fkms" ]] || [[ "$DRIVER" == "legacy" ]]; then
    echo ""
    echo -e "${CYAN}Setting up FKMS/Legacy driver components...${NC}"
    
    # Install tweakvec for PAL60 support
    TWEAKVEC_DIR="$INSTALL_DIR/lib/tweakvec"
    if [[ ! -d "$TWEAKVEC_DIR" ]]; then
        echo "  Installing tweakvec (PAL60 support)..."
        git clone --depth 1 "$TWEAKVEC_REPO" "$TWEAKVEC_DIR" 2>/dev/null || true
        
        if [[ -f "$TWEAKVEC_DIR/tweakvec.py" ]]; then
            echo -e "  ${GREEN}✓${NC} tweakvec installed"
        else
            echo -e "  ${YELLOW}!${NC} tweakvec install failed (PAL60 will not work)"
        fi
    else
        echo -e "  ${GREEN}✓${NC} tweakvec already present"
    fi
fi

if [[ "$OS_CODENAME" == "trixie" || "$OS_CODENAME" == "bookworm" ]]; then
    echo ""
    echo -e "${CYAN}Setting up KMS mode tools...${NC}"
    
    # Install build deps if needed
    if [[ ! -f /usr/include/libdrm/xf86drm.h ]]; then
        apt-get install -y -qq libdrm-dev gcc
    fi
    
    # Compile setmode daemon
    if [[ -f "$INSTALL_DIR/src/setmode.c" ]]; then
        mkdir -p "$INSTALL_DIR/bin"
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

#
# Display Auto-Detection Service (HDMI/Composite switching)
#

echo ""
echo -e "${CYAN}Setting up display auto-detection...${NC}"

if [[ -f "$INSTALL_DIR/scripts/boot-display-detect.sh" ]]; then
    chmod +x "$INSTALL_DIR/scripts/boot-display-detect.sh"
    
    # Create default config if not exists
    if [[ ! -f "/etc/crt-toolkit/display-detect.conf" ]]; then
        "$INSTALL_DIR/scripts/boot-display-detect.sh" --init-config
    fi
    
    # Install systemd service
    if [[ -f "$INSTALL_DIR/systemd/crt-display-detect.service" ]]; then
        cp "$INSTALL_DIR/systemd/crt-display-detect.service" /etc/systemd/system/
        systemctl daemon-reload
        
        echo ""
        echo "Display auto-detection can switch between HDMI and Composite at boot."
        echo -n "  Enable auto HDMI/Composite detection? [y/N] "
        read -r enable_detect
        if [[ "$enable_detect" =~ ^[Yy] ]]; then
            systemctl enable crt-display-detect.service
            echo -e "  ${GREEN}✓${NC} Display detection enabled"
            echo ""
            echo "Optional: Connect a PC speaker for audio feedback"
            echo "  Edit /etc/crt-toolkit/display-detect.conf to enable"
            echo "  Set ENABLE_SPEAKER=true and SPEAKER_GPIO=<pin>"
        else
            echo -e "  ${YELLOW}!${NC} Display detection not enabled"
            echo "  Enable later with: systemctl enable crt-display-detect"
        fi
    fi
fi

#
# RetroPie Integration
#

if [[ "$HAS_RETROPIE" == "true" ]]; then
    echo ""
    echo -e "${CYAN}Setting up RetroPie integration...${NC}"
    
    # Backup existing runcommand scripts
    if [[ -f "$RETROPIE_CONFIGS/all/runcommand-onstart.sh" ]]; then
        if [[ ! -f "$RETROPIE_CONFIGS/all/runcommand-onstart.sh.backup" ]]; then
            cp "$RETROPIE_CONFIGS/all/runcommand-onstart.sh" \
               "$RETROPIE_CONFIGS/all/runcommand-onstart.sh.backup"
            echo -e "  ${GREEN}✓${NC} Backed up existing runcommand-onstart.sh"
        fi
    fi
    
    if [[ -f "$RETROPIE_CONFIGS/all/runcommand-onend.sh" ]]; then
        if [[ ! -f "$RETROPIE_CONFIGS/all/runcommand-onend.sh.backup" ]]; then
            cp "$RETROPIE_CONFIGS/all/runcommand-onend.sh" \
               "$RETROPIE_CONFIGS/all/runcommand-onend.sh.backup"
            echo -e "  ${GREEN}✓${NC} Backed up existing runcommand-onend.sh"
        fi
    fi
    
    # Install runcommand scripts
    if [[ -f "$INSTALL_DIR/retropie/runcommand-onstart.sh" ]]; then
        cp "$INSTALL_DIR/retropie/runcommand-onstart.sh" "$RETROPIE_CONFIGS/all/"
        chmod +x "$RETROPIE_CONFIGS/all/runcommand-onstart.sh"
        echo -e "  ${GREEN}✓${NC} Installed runcommand-onstart.sh"
    fi
    
    if [[ -f "$INSTALL_DIR/retropie/runcommand-onend.sh" ]]; then
        cp "$INSTALL_DIR/retropie/runcommand-onend.sh" "$RETROPIE_CONFIGS/all/"
        chmod +x "$RETROPIE_CONFIGS/all/runcommand-onend.sh"
        echo -e "  ${GREEN}✓${NC} Installed runcommand-onend.sh"
    fi
    
    if [[ -f "$INSTALL_DIR/retropie/change_vmode.sh" ]]; then
        cp "$INSTALL_DIR/retropie/change_vmode.sh" "$RETROPIE_CONFIGS/all/"
        chmod +x "$RETROPIE_CONFIGS/all/change_vmode.sh"
        echo -e "  ${GREEN}✓${NC} Installed change_vmode.sh"
    fi
    
    # Install DiegoDimuro's broPi runcommand-menu scripts and shaders
    echo ""
    echo "Fetching RetroArch runcommand-menu scripts..."
    BROPI_TMP="/tmp/crt-bropi-install-$$"
    mkdir -p "$BROPI_TMP"
    
    if git clone --depth 1 https://github.com/DiegoDimuro/crt-broPi4-composite.git "$BROPI_TMP/bropi" 2>/dev/null; then
        # Install runcommand-menu scripts
        mkdir -p "$RETROPIE_CONFIGS/all/runcommand-menu"
        if cp "$BROPI_TMP/bropi/configs/all/runcommand-menu/"*.sh "$RETROPIE_CONFIGS/all/runcommand-menu/" 2>/dev/null; then
            chmod +x "$RETROPIE_CONFIGS/all/runcommand-menu/"*.sh
            echo -e "  ${GREEN}✓${NC} Installed 22 runcommand-menu scripts"
        fi
        
        # Install alignment shaders
        mkdir -p "$RETROPIE_CONFIGS/all/retroarch/shaders"
        if [[ -d "$BROPI_TMP/bropi/shaders" ]]; then
            cp -r "$BROPI_TMP/bropi/shaders/"* "$RETROPIE_CONFIGS/all/retroarch/shaders/" 2>/dev/null || true
            echo -e "  ${GREEN}✓${NC} Installed RetroArch shaders"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Could not fetch broPi scripts (offline?), skipping"
    fi
    
    rm -rf "$BROPI_TMP"
    
    echo ""
    echo -e "${YELLOW}Note:${NC} The runcommand scripts will automatically:"
    echo "  - Set PAL60 color before launching games"
    echo "  - Switch to 240p for low-res games"
    echo "  - Switch to 480i for high-res games (PSX, etc)"
    echo "  - Revert to 480i when returning to EmulationStation"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Run 'crt-toolkit' to open the configuration menu"
echo ""

# Offer to launch the toolkit
if [[ -t 0 ]]; then
    echo -n "Launch CRT Toolkit now? [Y/n] "
    read -r response
    if [[ ! "$response" =~ ^[Nn] ]]; then
        exec "$INSTALL_DIR/crt-toolkit.sh"
    fi
fi
