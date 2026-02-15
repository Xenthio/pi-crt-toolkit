# Pi CRT Toolkit - FKMS vs KMS

## Quick Summary

| Feature | FKMS | KMS |
|---------|------|-----|
| Mode switching | tvservice (easy) | modetest (complex) |
| PAL60 color | tweakvec ✓ | Limited (PAL-M only) |
| RetroPie compat | Excellent | Poor |
| Overscan adjust | config.txt (pixel-perfect) | DRM props (soft scaling) |
| Recommended for CRT | **Yes** | No |

## Why FKMS is Better for CRT

### 1. tvservice Mode Switching
FKMS keeps the legacy `tvservice` command working:
```bash
tvservice -c "NTSC 4:3 P"   # 240p
tvservice -c "NTSC 4:3"     # 480i
```
KMS requires complex DRM/modetest commands and a daemon to hold the mode.

### 2. PAL60 Support via tweakvec
PAL60 = PAL color encoding (4.43 MHz) on 525-line NTSC timing.
- Required for US/Japan consoles on PAL TVs
- Only tweakvec can set this at runtime
- tweakvec only works on FKMS/Legacy (needs /dev/mem access to VEC registers)
- KMS has no equivalent (closest is PAL-M with wrong subcarrier frequency)

### 3. RetroPie Compatibility
RetroPie's RetroArch was built for FKMS:
- Video driver checks card0 first (GPU render node on KMS)
- Composite on KMS is card1, but RetroArch doesn't find it
- FKMS uses dispmanx stack that RetroPie expects

### 4. Pixel-Perfect Overscan
FKMS allows overscan adjustment via config.txt:
```
overscan_left=16
overscan_right=16
```
These are true pixel offsets - no interpolation/blur.

KMS only offers DRM margin properties which use soft scaling (blurry).

## Configuration

### FKMS Setup (/boot/config.txt or /boot/firmware/config.txt)
```ini
[pi4]
dtoverlay=vc4-fkms-v3d
max_framebuffers=2

[all]
dtoverlay=vc4-fkms-v3d
enable_tvout=1
sdtv_mode=0
sdtv_aspect=1
audio_pwm_mode=2
```

### KMS Setup (if you must)
```ini
[pi4]
dtoverlay=vc4-kms-v3d,composite

[all]
# In cmdline.txt:
# video=Composite-1:720x480i vc4.tv_norm=PAL
```

## Mode Switching Scripts

The toolkit provides runcommand scripts for RetroPie that:
1. Set PAL60 color via tweakvec before game launch
2. Monitor RetroArch resolution and switch 240p/480i dynamically
3. Revert to 480i when returning to EmulationStation

See `/opt/crt-toolkit/retropie/` for the scripts.

## Without tweakvec

If you can't use tweakvec (e.g., on KMS), your color options are:

| sdtv_mode | Standard | Lines | Subcarrier |
|-----------|----------|-------|------------|
| 0 | NTSC | 525 | 3.58 MHz |
| 2 | PAL | 625 | 4.43 MHz |
| 4 | PAL-M | 525 | 3.58 MHz |

None of these give true PAL60 (525 lines with 4.43 MHz subcarrier).
PAL-M (sdtv_mode=4) is closest but has wrong color due to 3.58 MHz.

**Bottom line**: Use FKMS + tweakvec for proper CRT support.
