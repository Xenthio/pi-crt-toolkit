# Pi CRT Toolkit

A menu-driven setup utility for CRT TV output via composite video on Raspberry Pi.

**Recommended setup: Pi 4 + FKMS driver + RetroPie**

## Features

- **Interactive Setup Menu** - Similar to RetroPie Setup and raspi-config
- **Cross-Platform Support** - Works on Buster, Bullseye, Bookworm
- **Driver Abstraction** - Supports Legacy, FKMS, and KMS graphics drivers
- **Multiple Video Modes** - 240p, 480i (NTSC) and 288p, 576i (PAL)
- **PAL60 Color Support** - Better color reproduction on most CRTs
- **Global Hotkeys** - Switch modes instantly with F7-F12
- **RetroPie Integration** - Automatic 240p/480i switching for emulators

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | sudo bash
```

Or clone and run manually:

```bash
git clone https://github.com/Xenthio/pi-crt-toolkit.git
cd pi-crt-toolkit
sudo ./install.sh
```

The installer will:
1. Detect your OS and graphics driver
2. Install tweakvec for PAL60 support (FKMS/Legacy)
3. Set up RetroPie integration (if detected)
4. Launch the configuration menu

## Why FKMS?

**Use FKMS, not KMS, for CRT output.** See [FKMS vs KMS](docs/FKMS-vs-KMS.md) for details.

| Feature | FKMS ✓ | KMS |
|---------|--------|-----|
| tvservice mode switch | Yes | No |
| PAL60 via tweakvec | Yes | No |
| RetroPie compatible | Yes | Broken |
| Pixel-perfect overscan | Yes | Soft scaling |

### Enable FKMS

In `/boot/config.txt` (or `/boot/firmware/config.txt` on Bookworm):

```ini
[pi4]
dtoverlay=vc4-fkms-v3d

[all]
dtoverlay=vc4-fkms-v3d
enable_tvout=1
sdtv_mode=0
sdtv_aspect=1
```

## Compatibility

| OS Version | Driver | Status |
|------------|--------|--------|
| Buster (10) | FKMS | ✅ Best |
| Bullseye (11) | FKMS | ✅ Best |
| Bookworm (12) | FKMS | ✅ Works |
| Bookworm (12) | KMS | ⚠️ Limited |
| Trixie (13) | KMS | ⚠️ Limited |

## Video Modes

### NTSC (60Hz) - Americas, Japan
- **240p** - Progressive scan, perfect for retro games
- **480i** - Interlaced, better for text/menus

### PAL (50Hz) - Europe, Australia
- **288p** - Progressive scan
- **576i** - Interlaced

## Color Modes

### PAL60 (Recommended)
PAL color encoding (4.43MHz) with NTSC timing (60Hz):
- Better color saturation than pure NTSC
- Works on most multi-standard CRTs
- Required for proper colors from US/Japan consoles on PAL TVs
- **Requires tweakvec** (installed automatically on FKMS)

### NTSC
Standard NTSC color (3.58MHz). Use if PAL60 causes issues.

## RetroPie Integration

When RetroPie is detected, the toolkit installs runcommand hooks:

1. **Before game launch** (`runcommand-onstart.sh`):
   - Sets PAL60 color encoding via tweakvec
   - Starts background mode watcher

2. **During gameplay** (`change_vmode.sh`):
   - Monitors RetroArch's reported resolution
   - Switches to 240p for low-res games (≤300 lines)
   - Switches to 480i for high-res games (>300 lines)

3. **After game exit** (`runcommand-onend.sh`):
   - Reverts to 480i for EmulationStation

### Per-Game Mode Override

Force specific games to 480i by creating `/opt/retropie/configs/<system>/480i.txt`:

```
# One game name per line
Bloody Roar 2
Gran Turismo
```

Or force 240p with `240p.txt`.

## Hotkeys

After installation with triggerhappy:

| Key | Function |
|-----|----------|
| F7 | PAL60 color |
| F8 | NTSC color |
| F9 | 240p |
| F10 | 480i |
| F11 | 288p |
| F12 | 576i |

## Command Line

```bash
# Launch menu
sudo crt-toolkit

# Direct mode switching
crt-toolkit --240p
crt-toolkit --480i
crt-toolkit --pal60
crt-toolkit --ntsc

# Status
crt-toolkit --status
```

## Architecture

```
pi-crt-toolkit/
├── crt-toolkit.sh          # Main dialog menu
├── install.sh              # Installer
├── lib/
│   ├── platform.sh         # OS/driver detection
│   ├── video.sh            # Mode switching abstraction
│   ├── color.sh            # PAL60/NTSC color control
│   ├── boot.sh             # config.txt management
│   └── hotkeys.sh          # triggerhappy setup
├── retropie/
│   ├── runcommand-onstart.sh
│   ├── runcommand-onend.sh
│   └── change_vmode.sh
├── configs/
│   └── config.txt.fkms-crt # Sample config
└── docs/
    └── FKMS-vs-KMS.md
```

## Troubleshooting

### No composite output
1. Check `enable_tvout=1` in config.txt
2. Ensure FKMS overlay is enabled
3. Reboot

### Wrong colors / color rolling
```bash
# Try PAL60
sudo /opt/crt-toolkit/lib/color.sh pal60

# Or pure NTSC
sudo /opt/crt-toolkit/lib/color.sh ntsc
```

### RetroArch black screen / crashes
This usually means KMS driver. RetroArch's KMS backend checks the wrong DRM card.
**Solution**: Switch to FKMS driver.

### Hotkeys not working
```bash
sudo systemctl status triggerhappy
sudo systemctl restart triggerhappy
```

## Credits

- [Sakitoshi/retropie-crt-tvout](https://github.com/Sakitoshi/retropie-crt-tvout) - Original 240p scripts
- [DiegoDimuro/crt-broPi4-composite](https://github.com/DiegoDimuro/crt-broPi4-composite) - Pi4 composite guide
- [kFYatek/tweakvec](https://github.com/kFYatek/tweakvec) - PAL60 VEC register tool
- [ruckage/es-theme-snes-mini](https://github.com/ruckage/es-theme-snes-mini) - ES theme base

## License

MIT License
