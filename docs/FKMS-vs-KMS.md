# Pi CRT Toolkit - FKMS vs KMS

## Quick Summary

| Feature | FKMS | KMS |
|---------|------|-----|
| Enable composite | `enable_tvout=1` | `dtoverlay=...,composite=1` |
| Cmdline required | No | **Yes** (`video=Composite-1:...`) |
| Mode switching | tvservice (easy) | modetest/kms-switch |
| PAL60 color | tweakvec ✓ | cmdline tv_mode=PAL |
| RetroPie compat | Excellent | Works (with cmdline setup) |
| Overscan adjust | config.txt (pixel-perfect) | DRM props (soft scaling) |
| Recommended | **Yes (easiest)** | Yes (with proper setup) |

## Critical: KMS Requires cmdline.txt

**On Bookworm/Trixie (KMS), graphical apps need the `video=` parameter in cmdline.txt!**

Without it, SDL, RetroArch, EmulationStation, and other apps cannot find the composite display.

```
video=Composite-1:720x480@60ie
```

The `e` flag forces the output active even without hotplug detection.

## Configuration

### FKMS Setup (Bullseye recommended, or forced on Bookworm)

**/boot/config.txt** (or `/boot/firmware/config.txt` on Bookworm):
```ini
[pi4]
dtoverlay=vc4-fkms-v3d
max_framebuffers=2

[all]
enable_tvout=1
sdtv_mode=0
sdtv_aspect=1
hdmi_ignore_hotplug=1
audio_pwm_mode=2
```

No cmdline.txt changes needed for FKMS.

### KMS Setup (Bookworm/Trixie)

**/boot/firmware/config.txt:**
```ini
[all]
dtoverlay=vc4-kms-v3d,composite=1
max_framebuffers=2
hdmi_ignore_hotplug=1
disable_overscan=1
audio_pwm_mode=2
```

**/boot/firmware/cmdline.txt** (append to existing single line):
```
video=Composite-1:720x480@60ie,tv_mode=PAL
```

**Both are required for KMS!**

## Available KMS Video Modes

| Mode | cmdline parameter |
|------|-------------------|
| 480i (NTSC) | `720x480@60ie` |
| 240p (NTSC) | `720x240@60e` |
| 576i (PAL) | `720x576@50ie` |
| 288p (PAL) | `720x288@50e` |

Add `,tv_mode=<mode>` for color encoding:
- `tv_mode=NTSC` - Standard NTSC
- `tv_mode=PAL` - PAL color (use with 480i for PAL60-like)
- `tv_mode=NTSC-J` - Japanese NTSC
- `tv_mode=PAL-M` - Brazilian PAL

## Why FKMS is Easier

### 1. tvservice Mode Switching
FKMS keeps the legacy `tvservice` command working:
```bash
tvservice -c "NTSC 4:3 P"   # 240p
tvservice -c "NTSC 4:3"     # 480i
```
KMS requires DRM tools and a daemon to hold the mode.

### 2. PAL60 via tweakvec
- tweakvec gives true PAL60 (exact 4.43 MHz subcarrier)
- Only works on FKMS/Legacy (needs /dev/mem)
- KMS uses `tv_mode=PAL` which is close but boot-time only

### 3. Pixel-Perfect Overscan
FKMS allows overscan adjustment via config.txt:
```
overscan_left=16
overscan_right=16
```
These are true pixel offsets - no interpolation.

KMS DRM margin properties use soft scaling (blurry).

## Runtime Mode Switching

### FKMS
```bash
tvservice -c "NTSC 4:3 P"   # 240p
tvservice -c "NTSC 4:3"     # 480i
```

### KMS
```bash
# Using crt-toolkit
kms-switch 240p
kms-switch 480i

# Or modetest directly (requires holding DRM master)
modetest -M vc4 -s 46:720x240
```

## Troubleshooting

### KMS: Black screen / apps can't find display
Add `video=Composite-1:720x480@60ie` to cmdline.txt. This is **required** for userspace apps.

### KMS: RetroArch crashes
Ensure cmdline.txt has the video= parameter. RetroArch needs this to find the display.

### Wrong colors
- FKMS: Use tweakvec (`sudo python3 tweakvec.py --preset PAL60`)
- KMS: Add `,tv_mode=PAL` to the video= parameter in cmdline.txt

### Mode won't change at runtime (KMS)
KMS requires holding DRM master. Use `kms-switch` which runs a background daemon.

## Summary

**Use FKMS if:** You want easiest setup, tvservice, tweakvec PAL60, or pixel-perfect overscan.

**Use KMS if:** You're on Trixie (FKMS unavailable), or prefer the modern graphics stack. Just remember to set up cmdline.txt!

Both work well for CRT output when properly configured.
