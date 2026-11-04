# AppDMClient launchAppUpgrade Flow Analysis

## Root Cause: Why Settings "Update" Button Stays Disabled

The USB firmware update is NOT triggered through Settings UI at all.
When a USB is plugged in, the flow is:

1. USB automount → D-Bus signal `UsbMount`
2. `AppDMClient` receives signal → calls `launchAppUpgrade(USB_path)`
3. `launchAppUpgrade` validates files → launches `AppUpgrade` process
4. `AppUpgrade` process does the actual update (decrypts XML, shows UI, etc.)

**The Settings "Update" button has nothing to do with USB updates.**
It's for FOTA (over-the-air) updates, which are DISABLED: `checkFOTAEnable → "FOTA DISABLE"`

## launchAppUpgrade Complete Flow (FUN_0017ff60)

### Step 1: Path Validation (line 1652)
```
Log: a_strFullPath: [ /media/usb/1/81B5-1C01 ]
```
Checks if USB path is non-empty. **PASSES** ✓

### Step 2: Path Construction
Builds several paths from USB mount point:
- `USB_PATH/.lge.upgrade.xml` — firmware config
- `USB_PATH/VarUpgrade` — variant upgrade marker
- `USB_PATH/AppUpgrade` — the updater binary itself
- `USB_PATH/AppEngineerMode` — engineer mode binary
- `USB_PATH/HU/images/startFromUsb` — reserved update marker

### Step 3: RSA Signature Verification (lines 1726-1727)
Calls `FUN_00134870` twice:
- Uses RSA public key at `/app/share/AppUpgrade/teruten5_pub.key`
- Verifies stored signature/hash via `FUN_00221040` (mbedTLS RSA)

**Results from DLT logs:**
```
errAppUpgrade = -400    ← signature check fails
errXML        = -400    ← signature check fails (also seen: -404, 0)
```

### Step 4: Flow Branch
- If BOTH errAppUpgrade == 0 AND errXML == 0:
  → "No Hash error → Normal USB Upgrade" (bypasses all verification!)
- If EITHER is non-zero (our case: -400):
  → Enters hash verification path

### Step 5: File Existence Check (line 1834) ← **THE BLOCKER**
```
Log: Dose not exist "/media/usb/1/81B5-1C01/AppUpgrade"
```
**The AppUpgrade binary was NOT on the USB!** Function returns error here.

### Step 6 (never reached): Hash Verification + Launch
If AppUpgrade existed on USB:
- Compute file hash via `FUN_0018b1f0`
- Verify hash via `FUN_00134870` (RSA check with teruten5_pub.key)
- If passes → `QProcess::execute()` + `system()` to copy and launch
- AppUpgrade gets copied to `/tmp/app/bin/` and executed

## Required USB Structure

```
KIAUSB/                          (FAT32 or NTFS, label matters less)
├── AppUpgrade                   ← 10.8 MB, THE MISSING FILE
├── .lge.upgrade.xml             ← 17.8 KB, encrypted firmware config
├── .whatsnew.tar.gz             ← 325 KB, changelog
├── 2022_Cerato_AU.ver           ← 2.6 KB, version info
└── HU/
    ├── firmware/
    │   ├── update.tar.gz        ← main firmware update
    │   ├── frontkey/             ← front panel key firmware
    │   └── modem/               ← modem firmware (au_le22, eu, eu_le22)
    └── images/
        ├── iasImage*            ← IAS boot images (multiple variants)
        ├── mango-rootfs.tar.gz  ← root filesystem
        ├── mango-rwdata.tar.gz  ← read-write data partition
        ├── new_gui.tar.gz       ← GUI resources
        ├── mustwithcopy         ← copy marker
        ├── navi_au/             ← navigation data (AU)
        └── vrau/                ← voice recognition (AU)
```

## Error Codes from FUN_00134870 (RSA Verification)
- `0`    = Verification successful
- `-100` (0xFFFFFF9C) = Public key file doesn't exist
- `-101` (0xFFFFFF9B) = Public key file can't be opened
- `-400` = RSA verification failed (from FUN_00221040)
- `-404` = Hash entry not found / file not found

## What Happens Next (Prediction)

With AppUpgrade on the USB, the flow should reach Step 6:
1. Compute hash of `USB_PATH/AppUpgrade`
2. Verify with `teruten5_pub.key`
3. Since this is the GENUINE AppUpgrade binary from the official firmware
   package, its RSA signature should verify successfully (return 0)
4. AppUpgrade gets launched!

If the RSA check at Step 6 also returns -400:
- The genuine binary's hash should match the signature
- If it still fails, the signature might be version-specific
- Alternative: try the "No Hash error" path (need both checks = 0)

## Key Addresses in AppDMClient
- `FUN_0017ff60` = launchAppUpgrade (10,902 bytes)
- `FUN_00134870` = RSA signature verification
- `FUN_0018b0b0` = QString empty check
- `FUN_0018b1f0` = File hash computation
- `FUN_00221040` = mbedTLS RSA verify core
- `DAT_0051f020` = Global context/settings object
- `/app/share/AppUpgrade/teruten5_pub.key` = RSA 2048-bit public key
