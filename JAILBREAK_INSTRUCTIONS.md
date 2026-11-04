# Head Unit Jailbreak - Re-encrypted Rootfs (Attempt 2)

## What changed from Attempt 1

Attempt 1 used a **plain gzip** rootfs (no encryption). It failed with "The update file is incomplete" because the `g_isEncryptionUpdate` global flag expects encrypted files with a TE2 trailer.

Attempt 2 uses a **properly re-encrypted** rootfs:
- AES-128-CBC encrypted with the correct key and computed IV
- Original "TE2" trailer appended (RSA signature won't verify, but data is piped to extraction BEFORE signature check)
- `.ver` file updated with new CRC32 and file size

## Encryption details

- **AES key**: `60a93d70f73302a63e5ed0d0ea38be22`
- **IV**: `7f9a61d726c8fadc7fcb211db1ce1c01` (SHA-256 of "mango-rootfs.tar.gz884550976", first 16 bytes)
- **Encrypted data**: 884,550,976 bytes (gzip padded to 16-byte boundary)
- **Trailer**: 16,420 bytes (original TE2 trailer reused)
- **Total file size**: 884,567,396 bytes

## What was modified in the rootfs

### Patch 1: Secure Console Bypass (esinit)
- **File**: `/lib/systemd/esinit` line 478
- **Change**: Commented out `/bin/rm /tmp/secure_console_disable`
- **Effect**: The secure console flag stays disabled on every boot

### Patch 2: Known Root Password (shadow.Global)
- **File**: `/etc/shadow.Global`
- **Credentials**: `root` / `cerato2022`

### Patch 3: Persistent Socat Shell Service
- **File**: `/lib/systemd/system/jailbreak-shell.service`
- **Effect**: socat listens on **port 4444** providing a root shell after boot

### Patch 4: Immediate Payload (smack-relabel-ro.sh)
- **File**: `/etc/smack-relabel-ro.sh` (appended)
- **Effect**: During SMACK relabeling, starts socat on port 4444 immediately

## How the exploit works

1. USB plugged in → AppDMClient launches AppUpgrade
2. AppUpgrade decrypts `.lge.upgrade.xml` (unchanged, original encrypted)
3. AppUpgrade reads `mango-rootfs.tar.gz` — detects encrypted format (no gzip magic)
4. `DecryptToPIPE` called with the file:
   - Seeks to file_size - 0x4024, finds "TE2" trailer magic → passes
   - Computes IV from SHA-256("mango-rootfs.tar.gz" + "884550976") → matches our encryption
   - Decrypts AES-128-CBC data → produces valid gzip stream
   - Pipes decrypted data to extraction → **rootfs extracted successfully**
   - RSA signature verification runs AFTER data is piped → even if it fails, data is already extracted
5. Patched rootfs written to `/rw_data/mnt/root/`
6. SMACK relabeling → our payload executes → socat shell on port 4444
7. After reboot with new rootfs → persistent shell service starts

## Key uncertainty: RSA signature

The reused trailer's RSA signature won't verify because:
- It was signed over the original file's data, not ours
- We don't have LGE's private key

**Why it should still work**: DecryptToPIPE streams decrypted data to stdout (pipe) as it reads. The RSA signature check (`FUN_00109d50`) runs AFTER all data is output. Even if it fails:
- The pipe already delivered valid gzip data
- AppUpgrade may not check DecryptToPIPE's exit code (common for pipe commands)
- The extraction is already complete

**Risk**: If AppUpgrade does check the exit code and rolls back, the update fails. But the A/B partition scheme means the current system is preserved.

## Testing procedure

### Step 1: Plug in USB
- Insert USB (KIAUSB) into the car's USB port
- Wait for "Start entertainment system update" popup
- **Accept the update**

### Step 2: Watch for progress
- The update takes 10-30 minutes
- If you see progress past "Extracting rootfs" → the re-encryption worked
- During SMACK relabeling (near end), socat should start on port 4444

### Step 3: Connect
```bash
socat - TCP:<car-ip>:4444
```

### Step 4: Verify
```bash
whoami                          # should say root
cat /rw_data/jailbreak_marker   # proof of payload execution
cat /log_data/jailbreak.log     # execution log
```

## Backups

- Original encrypted rootfs: `2022_Cerato_AU/mango-rootfs.tar.gz.encrypted.bak`
- Original .ver: `2022_Cerato_AU/2022_Cerato_AU.ver.bak`

## Restore original

```bash
cp mango-rootfs.tar.gz.encrypted.bak /Volumes/KIAUSB/HU/images/mango-rootfs.tar.gz
cp 2022_Cerato_AU.ver.bak /Volumes/KIAUSB/2022_Cerato_AU.ver
```
