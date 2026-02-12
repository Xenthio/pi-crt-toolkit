# Pi CRT Toolkit

A menu-driven setup utility for CRT TV output via composite video on Raspberry Pi.

## Features

- **Interactive Setup Menu** - Similar to RetroPie Setup and raspi-config
- **Cross-Platform Support** - Works on Buster, Bullseye, and Bookworm
- **Driver Abstraction** - Supports Legacy, FKMS, and KMS graphics drivers
- **Multiple Video Modes** - 240p, 480i (NTSC) and 288p, 576i (PAL)
- **PAL60 Color Support** - Better color reproduction on most CRTs
- **Global Hotkeys** - Switch modes instantly with F7-F12
- **RetroPie Integration** - Automatic 240p switching for emulators

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | sudo bash
```

Or clone and run manually:

```bash
git clone https://github.com/Xenthio/pi-crt-toolkit.git
cd pi-crt-toolkit
sudo ./crt-toolkit.sh
```

## Compatibility

| OS Version | Status | Notes |
|------------|--------|-------|
| Raspbian Buster (10) | ✅ Full | Recommended |
| Raspbian Bullseye (11) | ✅ Full | |
| Raspbian Bookworm (12) | ⚠️ Partial | KMS driver limits some features |

| Graphics Driver | tvservice | Runtime Switching | PAL60 |
|-----------------|-----------|-------------------|-------|
| Legacy | ✅ | ✅ | ✅ |
| FKMS (vc4-fkms-v3d) | ✅ | ✅ | ✅ |
| KMS (vc4-kms-v3d) | ❌ | ⚠️ Limited | ⚠️ Limited |

## Hotkeys

After installation, these global hotkeys are available anywhere:

| Key | Function |
|-----|----------|
| F7 | PAL60 color mode |
| F8 | NTSC color mode |
| F9 | 240p (NTSC progressive) |
| F10 | 480i (NTSC interlaced) |
| F11 | 288p (PAL progressive) |
| F12 | 576i (PAL interlaced) |

## Video Modes

### NTSC (60Hz) - Americas, Japan
- **240p** - Progressive scan, perfect for retro games
- **480i** - Interlaced, better for text/menus

### PAL (50Hz) - Europe, Australia
- **288p** - Progressive scan
- **576i** - Interlaced, higher resolution

## Color Modes

### PAL60
Uses PAL color encoding (4.43MHz subcarrier) with NTSC timing (60Hz). This provides:
- Better color saturation
- More accurate hues
- Works on most multi-standard CRTs

### Pure NTSC
Standard NTSC color encoding (3.58MHz subcarrier). Use if PAL60 causes issues.

## RetroPie Integration

When RetroPie is detected, the toolkit installs runcommand hooks:

- Games automatically switch to 240p
- EmulationStation runs in 480i
- Per-game 480i override support

### Per-Game 480i Override

Create `/opt/retropie/configs/<system>/480i.txt`:

```
# Force 480i for these games
Bloody Roar 2.pbp
Gran Turismo.bin

# Or force entire system to 480i:
all
```

## Command Line Usage

```bash
# Launch interactive menu
sudo crt-toolkit

# Direct mode switching
sudo crt-toolkit --240p
sudo crt-toolkit --480i
sudo crt-toolkit --288p
sudo crt-toolkit --576i

# Color mode
sudo crt-toolkit --pal60
sudo crt-toolkit --ntsc

# Information
sudo crt-toolkit --status
sudo crt-toolkit --info
```

## Architecture

```
pi-crt-toolkit/
├── crt-toolkit.sh      # Main script with dialog menu
├── install.sh          # One-line installer
├── lib/
│   ├── platform.sh     # OS/driver detection
│   ├── video.sh        # Video mode abstraction
│   ├── color.sh        # Color mode (PAL60/NTSC)
│   ├── boot.sh         # Boot config management
│   └── hotkeys.sh      # Keyboard hotkey setup
└── README.md
```

## How It Works

### Driver Detection
The toolkit detects which graphics driver is in use:
- **Legacy**: Full dispmanx/tvservice support
- **FKMS**: tvservice works, but fbset is limited
- **KMS**: Full DRM, no tvservice (requires different approach)

### Video Switching
- On Legacy/FKMS: Uses `tvservice -c "MODE"` 
- On KMS: Uses DRM/modetest (limited runtime switching)

### Color Encoding
Uses [tweakvec](https://github.com/ArcadeHustle/tweakvec) to modify VEC registers for PAL60 color output on NTSC timing.

## Troubleshooting

### Black screen after mode switch
The framebuffer may not refresh properly. Try:
```bash
fbset -depth 8 && fbset -depth 16
```

### Colors look wrong
Try switching between PAL60 and NTSC:
```bash
sudo crt-toolkit --pal60
# or
sudo crt-toolkit --ntsc
```

### Hotkeys not working
Check triggerhappy status:
```bash
sudo systemctl status triggerhappy
```

### No composite output
Ensure `enable_tvout=1` is in `/boot/config.txt` and reboot.

## Credits

- [Sakitoshi/retropie-crt-tvout](https://github.com/Sakitoshi/retropie-crt-tvout) - Original 240p scripts
- [DiegoDimuro/crt-broPi4-composite](https://github.com/DiegoDimuro/crt-broPi4-composite) - Pi4 composite setup
- [tweakvec](https://github.com/ArcadeHustle/tweakvec) - PAL60 color encoding

## License

MIT License
