# PAL60 Options on Raspberry Pi

## Summary

| Method | Works On | Runtime? | True PAL60? |
|--------|----------|----------|-------------|
| tweakvec | FKMS, Legacy | ✅ Yes | ✅ Yes |
| cmdline tv_mode=PAL | KMS | ❌ Boot only | ⚠️ Approx |
| DRM TV mode property | KMS | ✅ Yes | ⚠️ No (PAL-M) |
| sdtv_mode=4 | FKMS, Legacy | ❌ Boot only | ❌ No (wrong freq) |

## What is PAL60?

PAL60 combines:
- **525 lines** (NTSC line count) at **60Hz**
- **PAL color encoding** with **4.43 MHz subcarrier**

This is used by:
- PAL game consoles running 60Hz games (NTSC games on PAL consoles)
- Multi-standard TVs displaying NTSC timing with PAL color
- US/Japan consoles connected to PAL TVs

## Method Details

### 1. tweakvec (Best for FKMS)

tweakvec directly manipulates the VideoCore VEC (Video Encoder Core) registers via `/dev/mem`.

```bash
sudo python3 /opt/crt-toolkit/lib/tweakvec/tweakvec.py --preset PAL60
```

**What it does:**
- Sets `VecVideoStandard.PAL_M` (525-line with phase alternation)  
- Overrides subcarrier frequency to `FrequencyPreset.PAL` (4,433,618.75 Hz)

**Pros:**
- True PAL60
- Runtime switching
- Works on FKMS and Legacy

**Cons:**
- Requires Python 3
- Needs root/sudo
- Only works on FKMS/Legacy (not KMS)

### 2. Kernel cmdline tv_mode (KMS only)

On kernel 5.10+, you can set TV mode via cmdline.txt:

```
video=Composite-1:720x480@60i,tv_mode=PAL
```

**Available modes:** NTSC, NTSC-J, NTSC-443, PAL, PAL-M, PAL-N, SECAM

**Important:** This sets PAL color encoding on whatever line standard is specified. With `720x480@60i`, you get:
- 480i/60Hz timing (NTSC-like)
- PAL color encoding

This is close to PAL60 but may not be exactly 4.43 MHz depending on kernel version.

**Pros:**
- No external tools needed
- Set once at boot

**Cons:**
- Boot-time only (requires reboot to change)
- Only on KMS driver
- Exact subcarrier frequency unclear

### 3. DRM "TV mode" Property (KMS runtime)

On KMS, you can change color mode at runtime via DRM property:

```bash
modetest -M vc4 -w 46:32:3  # Set connector 46 property 32 (TV mode) to 3 (PAL)
```

Property values:
- 0 = NTSC
- 1 = NTSC-443
- 2 = NTSC-J
- 3 = PAL
- 4 = PAL-M
- 5 = PAL-N
- 6 = SECAM
- 7 = Mono

**Limitation:** Setting PAL (3) on a 480i mode gives PAL color but the kernel may not set the exact PAL60 subcarrier frequency. PAL-M (4) is closer in spirit but uses 3.58 MHz.

### 4. sdtv_mode in config.txt (Boot only)

```ini
sdtv_mode=4  # PAL-M
```

| Value | Standard | Lines | Subcarrier |
|-------|----------|-------|------------|
| 0 | NTSC | 525 | 3.58 MHz |
| 1 | NTSC-J | 525 | 3.58 MHz |
| 2 | PAL | 625 | 4.43 MHz |
| 3 | PAL-M | 525 | 3.58 MHz |
| 16 | NTSC 240p | 525 | 3.58 MHz |
| 18 | PAL 288p | 625 | 4.43 MHz |

**Problem:** PAL-M (mode 3) has 525 lines but uses 3.58 MHz subcarrier, not 4.43 MHz. This gives incorrect colors compared to true PAL60.

## Recommendation

### For FKMS (Recommended setup):
1. Use `sdtv_mode=0` (NTSC) at boot
2. Apply PAL60 at runtime via tweakvec before launching games
3. This gives true PAL60 with correct 4.43 MHz subcarrier

### For KMS:
1. Use `video=Composite-1:720x480@60i,tv_mode=PAL` in cmdline.txt
2. This is boot-time only
3. Not as accurate as tweakvec but close enough for most TVs

## Technical Details

### PAL60 VEC Register Values (from tweakvec)

```python
# PAL60 = PAL-M standard + PAL subcarrier frequency
standard = VecVideoStandard.PAL_M  # 525-line, phase alternation
fsc = FrequencyPreset.PAL          # 4,433,618.75 Hz

# This is written to VEC config0 and freq registers
```

### Subcarrier Frequencies

| Standard | Frequency |
|----------|-----------|
| NTSC | 3,579,545.45 Hz (227.5 × fH) |
| PAL | 4,433,618.75 Hz (283.7516 × fH) |
| PAL-M | 3,575,611.89 Hz (227.25 × fH) |
| PAL60 | 4,433,618.75 Hz (PAL freq on NTSC timing) |

The key difference is PAL60 uses PAL's subcarrier on NTSC line timing, which only tweakvec can achieve at runtime.
