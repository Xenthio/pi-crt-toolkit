# KMS Composite Setup (Bookworm/Trixie)

## Overview

Full KMS (vc4-kms-v3d) requires **two** configuration points for composite output:

1. **config.txt** - Enable the composite connector
2. **cmdline.txt** - Set the video mode for userspace applications

Both are required! Without the cmdline parameter, graphical apps won't find a display.

## Quick Setup

### /boot/firmware/config.txt
```ini
[all]
dtoverlay=vc4-kms-v3d,composite=1
```

### /boot/firmware/cmdline.txt (append to existing line)
```
video=Composite-1:720x480@60ie
```

**Important:** cmdline.txt must be a single line. Append the video parameter, don't create a new line.

## Video Mode Syntax

```
video=Composite-1:<width>x<height>@<refresh><flags>
```

### Available Modes

| Mode | Parameter | Notes |
|------|-----------|-------|
| 480i (NTSC) | `720x480@60ie` | Most common, 60Hz interlaced |
| 240p (NTSC) | `720x240@60e` | Progressive, for retro games |
| 576i (PAL) | `720x576@50ie` | PAL interlaced |
| 288p (PAL) | `720x288@50e` | PAL progressive |

### Flags
- `i` = interlaced
- `e` = enable (force connector on even if not detected)

The `e` flag is important - it forces the composite output active even without hotplug detection.

## Color Mode (tv_mode)

You can also set the color encoding in cmdline.txt:

```
video=Composite-1:720x480@60ie,tv_mode=PAL
```

### tv_mode values
- `NTSC` - Standard NTSC (3.58 MHz)
- `NTSC-J` - Japanese NTSC (no pedestal)
- `NTSC-443` - NTSC with PAL subcarrier
- `PAL` - Standard PAL (use with 480i for PAL60-like output)
- `PAL-M` - Brazilian PAL
- `PAL-N` - Argentine PAL
- `SECAM` - French/Russian

**Note:** Setting `tv_mode=PAL` with a 480i mode gives PAL color encoding on NTSC timing, which is similar to PAL60 (though subcarrier frequency may differ slightly from true PAL60).

## Complete Example

### config.txt
```ini
dtparam=audio=on
dtoverlay=vc4-kms-v3d,composite=1
max_framebuffers=2
disable_overscan=1
```

### cmdline.txt
```
console=serial0,115200 console=tty1 root=PARTUUID=xxx rootfstype=ext4 fsck.repair=yes rootwait video=Composite-1:720x480@60ie,tv_mode=PAL
```

## Runtime Mode Switching (KMS)

Unlike FKMS (which uses tvservice), KMS mode switching requires DRM tools:

```bash
# Using kms-switch (from crt-toolkit)
kms-switch 240p
kms-switch 480i

# Using modetest directly
modetest -M vc4 -s <connector>:720x240
```

**Limitation:** KMS mode changes require holding the DRM master. The `kms-switch` tool uses a daemon to maintain the mode.

## Comparison: KMS vs FKMS

| Feature | KMS | FKMS |
|---------|-----|------|
| Composite enable | `dtoverlay=...,composite=1` | `enable_tvout=1` |
| Mode at boot | cmdline.txt `video=` | `sdtv_mode=` |
| Runtime switch | modetest/kms-switch | tvservice |
| PAL60 runtime | Limited (tv_mode) | tweakvec (full) |
| RetroPie compat | Limited | Full |

## Troubleshooting

### Black screen / No output
1. Ensure both config.txt AND cmdline.txt are configured
2. Add the `e` flag to force enable: `720x480@60ie`
3. Check `/sys/class/drm/` for `card*-Composite-1`

### Apps can't find display
The cmdline.txt `video=` parameter is required for userspace apps to use the display. Without it, SDL/RetroArch may fail to initialize.

### Wrong colors
Add `tv_mode=PAL` or `tv_mode=NTSC` to cmdline.txt video parameter.

### Mode won't change at runtime
KMS requires a process to hold DRM master. Use `kms-switch` from crt-toolkit which runs a background daemon.
