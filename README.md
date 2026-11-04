# 2022 Kia Cerato AU — IVI Jailbreak Research

Reverse engineering and jailbreak tooling for the LGE Gen5W IVI head unit (HKMC Premium AVN 2.1) in the 2022 Kia Cerato (BD_PE.AUS.S5W_L).

**Platform**: Intel x86-64 Apollo Lake · OpenEmbedded 1.0 "mango" · Kernel 4.1.27-abl · glibc 2.25 · systemd 225

## Getting Started

### Prerequisites

```bash
brew install qemu e2fsprogs python3
pip3 install pycryptodome
```

### 1. Obtain Firmware

You need the firmware update files from a genuine Kia navigation update USB. The relevant files live under `HU/images/` on the update stick:

| File | What it is |
|------|------------|
| `iasImage` | IPK container holding the boot kernel (bzImage) |
| `mango-rootfs.tar.gz` | Encrypted ext4 rootfs (~880 MB) |
| `mango-rwdata.tar.gz` | Encrypted read-write data partition |
| `.lge.upgrade.xml` | Encrypted update manifest |
| `2022_Cerato_AU.ver` | Version/CRC metadata |

Copy them into `HU/images/` in this repo (gitignored — too large to track).

### 2. Decrypt Firmware

All firmware files are AES-128-CBC encrypted. The decryption tool is `exploits/tools/xcrypt.py`:

```bash
# Decrypt the rootfs
python3 exploits/tools/xcrypt.py -d HU/images/mango-rootfs.tar.gz -o mango-rootfs.tar.gz.dec

# Decrypt rwdata
python3 exploits/tools/xcrypt.py -d HU/images/mango-rwdata.tar.gz -o mango-rwdata.tar.gz.dec

# Decrypt the update manifest
python3 exploits/tools/xcrypt.py -d HU/images/.lge.upgrade.xml -o lge.upgrade.xml

# Test decryption without writing output
python3 exploits/tools/xcrypt.py -t HU/images/mango-rootfs.tar.gz
```

Encryption details:
- **Key**: Hardcoded AES-128-CBC (`60a93d70f73302a63e5ed0d0ea38be22`)
- **IV**: SHA-256(`filename` + signed 32-bit filesize), first 16 bytes
- **Trailer**: 0x4024-byte TE2 trailer at EOF containing integrity hash

### 3. Prepare the VM

The VM boots the real automotive kernel inside QEMU with a minimal BusyBox rootfs.

```bash
cd vm

# Option A: From encrypted iasImage (extracts kernel automatically)
python3 vm_boot_au.py prepare --container /path/to/iasImage.encrypted

# Option B: Use the pre-extracted bzImage already in the repo
python3 vm_boot_au.py prepare --bzimage bzImage --busybox busybox
```

This creates `bootable/` with `bzImage`, `rootfs.img`, and the init overlay.

### 4. Run the VM

```bash
python3 vm_boot_au.py run
```

Boots to a root shell on the serial console. Press `Ctrl-A X` to exit QEMU.

Options:
- `--sdhci-compat` — Patch SDHCI PCI ID table in guest RAM (vendor 0x1022→0x1b36) for SD card emulation
- `--display sdl` — Show graphical display (default: serial-only)
- `--timeout 300` — Auto-shutdown after N seconds

### 5. Run the IVI GUI (Optional)

To boot the full IVI graphical environment with touch input:

```bash
bash start_ivi.sh
```

Then switch to engineer mode:
```bash
bash start_engineer.sh
```

Engineer PIN: `19491003` · Dealer PIN: `2400`

## Project Structure

```
├── HU/                          # Head unit firmware (gitignored large files)
│   ├── images/                  # Encrypted firmware images go here
│   └── firmware/                # Extracted firmware, xcrypt.py copy
├── vm/                          # QEMU virtual machine
│   ├── vm_boot_au.py            # Main VM launcher (prepare + run)
│   ├── bzImage                  # Extracted AU kernel 4.1.27-abl
│   ├── busybox                  # Static x86-64 BusyBox
│   ├── rootfs-overlay/          # Init script for the guest rootfs
│   ├── run_qemu_vm.sh           # Simple shell launcher
│   └── start_ivi.sh             # GUI launcher with EGL/DRM shim
├── exploits/                    # Exploit development
│   ├── tools/xcrypt.py          # AES firmware encryption/decryption
│   ├── asf/                     # ASF/WMA zero-day PoCs (lms_asf.so)
│   ├── mkv/                     # MKV/libebml CVE PoCs
│   ├── bluetooth/               # Bluetooth PBAP/HFP phone emulator
│   ├── gstreamer/               # GStreamer pipeline analysis
│   └── payload/                 # Shellcode and payloads
├── JAILBREAK_INSTRUCTIONS.md    # Firmware patching walkthrough
├── EXPLOIT_STRATEGY.md          # Attack surface analysis
├── FINDINGS.md                  # Reverse engineering findings
├── start_ivi.sh                 # Boot IVI GUI
├── start_engineer.sh            # Switch to engineer mode
└── start_home.sh                # Switch back to home screen
```

## Jailbreak Target: `secure_console_disable`

The goal is to make `/tmp/secure_console_disable` persist across boots. When this flag exists:

- **Root shell** on serial console (ttyS2 @ 115200)
- **Dropbear SSH** on port 22
- **Debug logging** enabled

On production units, `esinit` deletes this file when MICOM reports `secure_console=1`. The jailbreak patches `esinit` to skip that deletion.

See [JAILBREAK_INSTRUCTIONS.md](JAILBREAK_INSTRUCTIONS.md) for the full firmware patching workflow.

## Exploit Research

### Confirmed Vulnerabilities

**ASF/WMA Zero-Days (lms_asf.so)** — 3 bugs in the IVI's media daemon:
1. Heap over-read via crafted ASF header
2. Integer underflow in packet size calculation
3. Missing return value check leading to use of uninitialized data

PoC files in `exploits/asf/` crash the IVI's LMS daemon when played from USB (confirmed on hardware — daemon enters silent crash loop).

**MKV/libebml CVEs** — 2 known vulns in libebml 1.3.4:
- CVE-2021-3405: Heap buffer overflow
- CVE-2023-52339: Integer overflow

PoC files in `exploits/mkv/`.

### Attack Surface

The car has **no WiFi/network**. Available interfaces:
- **USB-A** port (media playback, firmware update)
- **Bluetooth** (PBAP contacts, HFP audio, A2DP)

No USB-C. No USB ethernet adapter support.

## Firmware Re-encryption

To build a modified firmware update package:

```bash
# After modifying the decrypted rootfs:
python3 exploits/tools/xcrypt.py -e mango-rootfs-patched.tar.gz -o mango-rootfs.tar.gz

# The TE2 trailer from the original file must be appended manually
# (contains RSA signature — reused from original, exploits TOCTOU in DecryptToPIPE)
```

The update mechanism streams decrypted data to extraction **before** RSA signature verification completes (TOCTOU). See [JAILBREAK_INSTRUCTIONS.md](JAILBREAK_INSTRUCTIONS.md) for details.

## Constraints

- The unit is **not jailbroken** — no SSH, no serial, no usb-pwn service
- AppUpgrade RSA bypass (CVE-2023-26246) is **patched** on this firmware
- There is **no firmware update option** in engineer mode
- All interaction must go through USB or Bluetooth
