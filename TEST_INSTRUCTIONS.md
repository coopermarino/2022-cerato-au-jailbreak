# DecryptToPIPE Pipe-Before-Verify Jailbreak — Test Instructions

## What this exploit does

DecryptToPIPE streams decrypted firmware data to the extraction process via a
pipe BEFORE completing RSA signature verification. Our re-encrypted rootfs will:
1. Pass the TE2 trailer magic check ("TE2" is present)
2. Decrypt correctly with the known AES key (verified: first block = 1f8b gzip magic)
3. Be piped to the extraction process as valid gzip data
4. RSA signature check FAILS afterward — but the rootfs is already extracted

The A/B partition scheme means if something goes wrong, the head unit falls back
to the current partition. Low brick risk.

## Rootfs modifications (already applied)

1. **Secure console bypass**: `/lib/systemd/esinit` line 478 — deletion of
   `/tmp/secure_console_disable` commented out
2. **Root password**: `root` / `cerato2022` in `/etc/shadow.Global`
3. **Socat shell service**: `/lib/systemd/system/jailbreak-shell.service` on port 4444
4. **Immediate payload**: appended to `/etc/smack-relabel-ro.sh`

## Preparing the USB stick

**You need a USB stick formatted as exFAT or FAT32, large enough to hold all
the firmware files (about 8GB total).** The volume label should be `KIAUSB`.

### Step 1: Copy the ENTIRE genuine firmware directory

Copy everything from `2022_Cerato_AU/` to the USB root:

```bash
# Mount your USB stick (assume /Volumes/KIAUSB)
# Copy the complete firmware layout
cp -R /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/HU /Volumes/KIAUSB/
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/.lge.upgrade.xml /Volumes/KIAUSB/
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/AppUpgrade /Volumes/KIAUSB/
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/.whatsnew.tar.gz /Volumes/KIAUSB/
```

### Step 2: Replace rootfs with the patched version

```bash
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/mango-rootfs-patched-encrypted.tar.gz \
   /Volumes/KIAUSB/HU/images/mango-rootfs.tar.gz
```

### Step 3: Copy the updated .ver file

```bash
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/2022_Cerato_AU.ver /Volumes/KIAUSB/
```

### Step 4: Verify the USB layout

Your USB should have this structure:
```
KIAUSB/
├── .lge.upgrade.xml          (17,812 bytes - original, encrypted)
├── .whatsnew.tar.gz           (if present in original)
├── 2022_Cerato_AU.ver         (UPDATED with new CRC32/size for rootfs)
├── AppUpgrade                 (10,807,772 bytes - original, encrypted)
└── HU/
    ├── firmware/
    │   ├── update.tar.gz      (original)
    │   ├── modem/             (original)
    │   └── frontkey/          (original)
    └── images/
        ├── mango-rootfs.tar.gz  (884,559,556 bytes - PATCHED re-encrypted)
        ├── mango-rwdata.tar.gz  (original)
        ├── new_gui.tar.gz       (original)
        ├── iasImage*            (all original)
        ├── vrau/                (original)
        ├── vreu/                (original)
        ├── navi_au/             (original)
        └── mustwithcopy         (original)
```

### Step 5: Eject safely

```bash
diskutil eject /Volumes/KIAUSB
```

## Running the test

1. **Start the car** (engine on or ACC mode)
2. **Insert the USB** into the USB-A port
3. **Wait for the update prompt** — "Start entertainment system update" popup
4. **Accept the update**
5. **Watch the progress** — the update takes 10-30 minutes

## What to watch for

### Signs of SUCCESS:
- Update progresses past "Extracting system files" or similar
- Update bar reaches 50%+ (rootfs is the largest file)
- Head unit reboots and boots normally
- After reboot, head unit functions normally

### Signs of FAILURE (safe — A/B partition protects you):
- "Update file is incomplete" or "invalid" error early
- "Update failed" message
- Head unit reboots to the previous (working) partition
- Error -403 in logs (RSA signature failure — we don't have the private key to re-sign)

### How to verify the jailbreak worked (NO network needed):

**Method 1: Engineering Mode (immediate check)**
1. Enter engineering mode: Dealer PIN `2400`, then Engineer PIN `19491003`
2. Look for any new behavior or menus
3. The secure console flag should now persist across reboots

**Method 2: Check data partition (if you get any shell access later)**
```bash
cat /rw_data/jailbreak_marker
cat /log_data/jailbreak.log
```

**Method 3: USB serial access (if you build a USB-serial adapter)**
- The root password is now `cerato2022`
- Secure console should not be disabled on boot

## What to do if the update fails

**This is SAFE.** The A/B partition scheme means:
- If the update fails or is rejected, the head unit stays on the current partition
- If the new rootfs boots but is broken, the next reboot falls back to the old partition
- You can always reflash the original firmware from USB

### To restore original rootfs (if needed):
```bash
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/mango-rootfs.tar.gz.encrypted.bak \
   /Volumes/KIAUSB/HU/images/mango-rootfs.tar.gz
cp /Users/coopermarino/Downloads/NaU/2022_Cerato_AU/2022_Cerato_AU.ver.bak \
   /Volumes/KIAUSB/2022_Cerato_AU.ver
```

## Known uncertainties

1. **CRC32 check**: The .ver file's CRC32 for the rootfs has been updated to match
   the patched file. If AppUpgrade validates CRC32 BEFORE calling DecryptToPIPE,
   the update will fail because the CRC32 is for the encrypted file (not the
   original). This is the most likely failure mode.

2. **Exit code check**: If AppUpgrade checks DecryptToPIPE's exit code and rolls
   back on RSA failure, the extraction may be reverted. The pipe-before-verify
   theory says the data is already extracted before the exit code is checked.

3. **Partition switchover**: Even if the rootfs extracts correctly, the system may
   refuse to switch to the new partition if the overall update validation fails.

## If this approach fails: Next steps

- **TOCTOU race (most promising firmware bypass)**: Use a Raspberry Pi Zero 2 W as USB
  gadget to serve genuine (properly signed) files during verification and swap to modified
  files before extraction. This bypasses the RSA signature problem since we don't have
  the private key — the genuine file passes checkHash, then our modified file gets
  extracted. See [TOCTOU_ATTACK_PLAN.md](TOCTOU_ATTACK_PLAN.md)
- **GStreamer overflow**: Try CVE-2026-2920 WMA PoCs for memory corruption → RCE
- **libebml overflow**: Try MKV PoCs for heap overflow in PlayerEngine
