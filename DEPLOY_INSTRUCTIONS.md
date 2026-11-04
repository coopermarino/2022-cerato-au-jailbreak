# CVE-2023-26246 Jailbreak Deployment

## What was patched

**AppUpgrade binary** — 4 bytes changed to bypass RSA signature verification:

| File Offset | Original | Patched | What it does |
|---|---|---|---|
| `0x1fc2eb` | `75 07` (JNE) | `90 90` (NOP) | Skip error branch in checkHash verify function 1 |
| `0x1fc465` | `74 13` (JE) | `EB 13` (JMP) | Always jump to success in checkHash verify function 2 |
| `0x70066f` | `75 07` (JNE) | `90 90` (NOP) | Same, duplicate code copy |
| `0x7007e9` | `74 13` (JE) | `EB 13` (JMP) | Same, duplicate code copy |

Both functions call mbedTLS RSA verification at `0x213874`. The patches make
`checkHash` return 0 (success) regardless of the RSA signature result.

**Rootfs modifications** (inside mango-rootfs.tar.gz):
- esinit: secure_console_disable persists on boot
- shadow.Global: root password set to `cerato2022`
- AppUpgrade in rootfs: same 4 patches (for persistence after jailbreak)
- jailbreak-shell.service: socat on port 4444 (needs network to reach)
- smack-relabel-ro.sh: immediate payload execution during update

## Files produced

| File | Purpose |
|---|---|
| `AppUpgrade.patched` | Encrypted patched AppUpgrade for USB root |
| `mango-rootfs-patched-encrypted.tar.gz` | Re-encrypted modified rootfs |
| `2022_Cerato_AU.ver.patched` | Updated .ver with new CRC32/sizes |

## USB Deployment

**IMPORTANT: Back up the original USB first!**

```bash
# 1. Mount the USB (KIAUSB)

# 2. Back up originals (if not already done)
cp /Volumes/KIAUSB/AppUpgrade ~/Desktop/AppUpgrade.orig
cp /Volumes/KIAUSB/2022_Cerato_AU.ver ~/Desktop/2022_Cerato_AU.ver.orig

# 3. Deploy patched files
cp AppUpgrade.patched /Volumes/KIAUSB/AppUpgrade
cp mango-rootfs-patched-encrypted.tar.gz /Volumes/KIAUSB/HU/images/mango-rootfs.tar.gz
cp 2022_Cerato_AU.ver.patched /Volumes/KIAUSB/2022_Cerato_AU.ver

# 4. Eject safely
diskutil eject /Volumes/KIAUSB
```

## Testing in the car

1. Insert USB into the car's USB-A port
2. Wait for "Start entertainment system update" popup
3. Accept the update
4. Watch for progress — if it gets past "Checking files" → the bypass worked!
5. Full update takes 10-30 minutes

## What could go wrong

### AppDMClient rejects patched AppUpgrade (most likely failure)
AppDMClient (on the currently installed rootfs) also RSA-verifies AppUpgrade
before running it (CVE-2023-26244). If the 2024 firmware patched this CVE,
AppDMClient will reject our modified AppUpgrade and the update won't start.

**Symptoms**: Update fails immediately or very early, no hash check phase.

**Fallback**: TOCTOU attack with Pi Zero USB gadget (see TOCTOU_ATTACK_PLAN.md).

### Patched AppUpgrade runs but something else fails
The update process has many stages. If checkHash is bypassed but another
verification catches the modifications, the update rolls back safely (A/B
partition scheme preserves the current system).

## Restore original

```bash
cp ~/Desktop/AppUpgrade.orig /Volumes/KIAUSB/AppUpgrade
cp ~/Desktop/2022_Cerato_AU.ver.orig /Volumes/KIAUSB/2022_Cerato_AU.ver
cp mango-rootfs.tar.gz.encrypted.bak /Volumes/KIAUSB/HU/images/mango-rootfs.tar.gz
```

## After successful jailbreak

The head unit will reboot with the modified rootfs:
- Secure console is disabled
- Root password: `cerato2022`
- Engineer mode debug features (IpConfigShell etc.) should now work
- The patched AppUpgrade persists in the rootfs for future updates

**Network access note**: The socat shell on port 4444 requires network
connectivity. Since this car has no WiFi, you'll need to:
- Use Bluetooth (if RFCOMM is available)
- Connect a USB ethernet adapter
- Or use engineer mode's IpConfigShell with secure_console disabled
