# CRT Toolkit for Raspberry Pi 4

A menu-driven setup utility for CRT TV output via composite video on Raspberry Pi 4.

![Menu Screenshot](screenshots/menu.png)

## Features

- **Interactive Setup Menu** - Similar to RetroPie Setup and raspi-config
- **Multiple Video Modes** - 240p, 480i (NTSC) and 288p, 576i (PAL)
- **PAL60 Color Support** - Better color reproduction on most CRTs
- **Global Hotkeys** - Switch modes instantly with F7-F12
- **RetroPie Integration** - Automatic 240p switching for emulators
- **Boot Configuration** - Set default resolution on startup

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/Xenthio/crt-toolkit/main/install.sh | sudo bash
```

Or clone and run manually:

```bash
git clone https://github.com/Xenthio/crt-toolkit.git
cd crt-toolkit
sudo ./crt-toolkit.sh
```

## Hotkeys

After installation, these global hotkeys are available:

| Key | Function |
|-----|----------|
| F7 | PAL60 color mode |
| F8 | NTSC color mode |
| F9 | 240p (NTSC progressive) |
| F10 | 480i (NTSC interlaced) |
| F11 | 288p (PAL progressive) |
| F12 | 576i (PAL interlaced) |

## Video Modes

### NTSC (60Hz)
- **240p** - 720x480 progressive, perfect for retro games
- **480i** - 720x480 interlaced, better for menus/text

### PAL (50Hz)
- **288p** - 720x576 progressive
- **576i** - 720x576 interlaced

## Color Modes

### PAL60
Uses PAL color encoding (4.43MHz subcarrier) with NTSC timing (60Hz). This provides better color saturation and accuracy on most CRT TVs that support both standards.

### Pure NTSC
Standard NTSC color encoding (3.58MHz subcarrier). Use if your TV has issues with PAL60.

## RetroPie Integration

When RetroPie is detected, the toolkit installs:

- `runcommand-onstart.sh` - Switches to 240p before launching games
- `runcommand-onend.sh` - Switches back to 480i for EmulationStation

### Per-Game 480i Override

Create a file `/opt/retropie/configs/<system>/480i.txt` with game names that should run in 480i:

```
# Force 480i for these games
Bloody Roar 2.pbp
Gran Turismo.pbp
all   # Use "all" to force 480i for entire system
```

## Configuration

Config is stored in `/etc/crt-toolkit/config`:

```bash
COLOR_MODE="pal60"      # pal60 or ntsc
BOOT_MODE="ntsc480i"    # ntsc240p, ntsc480i, pal288p, pal576i
```

## Requirements

- Raspberry Pi 4
- Composite video cable
- CRT TV with composite input
- RetroPie (optional, for emulation integration)

## Boot Configuration

The toolkit modifies `/boot/config.txt` to enable composite output:

```ini
[pi4]
dtoverlay=vc4-fkms-v3d
max_framebuffers=2
enable_tvout=1
framebuffer_width=720
framebuffer_height=480
sdtv_mode=0
sdtv_aspect=1
disable_overscan=1
hdmi_ignore_hotplug=1
audio_pwm_mode=2
```

## Command Line Usage

```bash
# Launch interactive menu
sudo crt-toolkit

# Quick install
sudo crt-toolkit --install

# Switch modes directly
sudo crt-toolkit --240p
sudo crt-toolkit --480i
sudo crt-toolkit --288p
sudo crt-toolkit --576i

# Change color mode
sudo crt-toolkit --pal60
sudo crt-toolkit --ntsc

# Check status
sudo crt-toolkit --status
```

## Credits

- [Sakitoshi/retropie-crt-tvout](https://github.com/Sakitoshi/retropie-crt-tvout) - Original 240p scripts
- [DiegoDimuro/crt-broPi4-composite](https://github.com/DiegoDimuro/crt-broPi4-composite) - Pi4 composite setup
- [tweakvec](https://github.com/ArcadeHustle/tweakvec) - PAL60 color encoding

## License

MIT License
