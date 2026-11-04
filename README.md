# 2022 Kia Cerato AU — IVI Security Research & Jailbreak

Reverse engineering, vulnerability research and jailbreak tooling for the LGE Gen5W IVI head unit (HKMC Premium AVN 2.1) in the 2022 Kia Cerato (BD_PE.AUS.S5W_L.001.001.260319).

This is authorized security research on a personally-owned vehicle.

---

## System Overview

| Component | Detail |
|-----------|--------|
| **Platform** | LGE Gen5W IVI (HKMC Premium AVN 2.1) |
| **SoC** | Intel Apollo Lake x86-64 |
| **OS** | OpenEmbedded 1.0 "mango" |
| **Kernel** | Linux 4.1.27-abl |
| **Libc** | glibc 2.25 |
| **Init** | systemd 225 (+SMACK) |
| **Display** | Weston 1.10.0 (Wayland IVI Shell) |
| **Media** | GStreamer 1.8.3 + lightmediascanner 0.5.1 |
| **Bluetooth** | `vbtd` — custom HKMC daemon (not BlueZ), serial UART |
| **GUI** | Qt 5.x (QML/Wayland) |
| **Crypto** | mbedTLS (in AppUpgrade), `/dev/keystore` hardware keystore |

**Everything runs as root.** No privilege separation, no seccomp, no AppArmor/SELinux. The rootfs is read-only ext4 but trivially remountable (`mount -o remount,rw /`).

Full system analysis: **[FINDINGS.md](FINDINGS.md)** — firmware structure, filesystem layout, boot sequence, services, credentials, udev rules, and software version inventory.

---

## Physical Access Constraints

The car has **no WiFi and no network interfaces**. Available attack surface:

| Interface | Access |
|-----------|--------|
| **USB-A port** | Media playback, firmware update |
| **Bluetooth** | PBAP contacts, HFP audio, A2DP |
| **Touchscreen** | Engineer mode UI |

**Not available**: No serial console, no SSH, no ADB, no JTAG, no WiFi, no USB-C, no ethernet. Any exploit must be triggerable through USB insertion, Bluetooth, or the touchscreen.

Full attack surface analysis: **[LGE_Gen5W_IVI_Security_Briefing.md](LGE_Gen5W_IVI_Security_Briefing.md)**

---

## Jailbreak Target: `secure_console_disable`

The security gate in `/lib/systemd/esinit` controls all debug access:

```
DEFAULT: touch /tmp/secure_console_disable  (debug ON)
     ↓
IF micom reports secure_console=1:
     rm /tmp/secure_console_disable          (debug OFF)
     rm /dev/ttyS2                           (remove serial)
```

When `/tmp/secure_console_disable` **exists** (debug mode):
- Root shell via `/bin/sh`
- Dropbear SSH on port 22
- Serial console on ttyS2 @ 115200
- Debug logging, permissive firewall

When **absent** (production): nologin shell, no SSH, no serial.

The jailbreak patches `esinit` line 478 to skip the `rm` command, making debug mode persist across boots.

Full jailbreak walkthrough: **[JAILBREAK_INSTRUCTIONS.md](JAILBREAK_INSTRUCTIONS.md)**

---

## Engineer Mode

PINs extracted via reverse engineering of `AppEngineerMode` (SHA-256 hash comparison, no salt):

| Mode | PIN | Access |
|------|-----|--------|
| **Dealer** | `2400` | Dealer diagnostics |
| **Engineer** | `19491003` | Full engineer diagnostics, IP config, logging |

AU variant alternate PIN: `19190301`

**There is no firmware update option in engineer mode.** The Settings "Update" button is for FOTA (disabled). USB updates are triggered automatically by `AppDMClient` when a USB stick with the right file layout is inserted.

How the update is actually triggered: **[LAUNCH_ANALYSIS.md](LAUNCH_ANALYSIS.md)**

---

## Vulnerability Summary

3 zero-day vulnerabilities discovered, 4 confirmed unpatched CVEs, 6 exploitation enablers. Full report: **[exploits/VULNERABILITY_REPORT.md](exploits/VULNERABILITY_REPORT.md)**

### Zero-Days (lms_asf.so) — USB-triggered, no user interaction

| ID | Type | CWE | Severity | PoC |
|----|------|-----|----------|-----|
| **ZD-ASF-1** | Heap Over-Read | CWE-125 | High | `exploits/asf/crash_heap_overread.wma` |
| **ZD-ASF-2** | Integer Underflow → ~4GB Heap Overflow | CWE-191 | High | `exploits/asf/crash_int_underflow.wma` |
| **ZD-ASF-3** | Missing Return Value Check | CWE-252 | Medium | `exploits/asf/crash_sign_extension.wma` |

All three are in LGE's custom `lms_asf.so` ASF/WMA parser plugin — not in any upstream library. Triggered by placing a crafted `.wma` file on a USB stick. lightmediascanner auto-scans it as root with no sandboxing. **Confirmed crashing the real IVI hardware** (daemon enters silent crash loop).

Detailed write-up: **[exploits/ZERODAY_ASF_REPORT.md](exploits/ZERODAY_ASF_REPORT.md)**

### Confirmed Unpatched CVEs

| CVE | Library | Type | Trigger |
|-----|---------|------|---------|
| **CVE-2021-3405** | libebml 1.3.4 | Heap Overflow | USB `.mkv` file |
| **CVE-2023-52339** | libebml 1.3.4 | Integer Overflow → BOF | USB `.mkv` file |
| **CVE-2019-13615** | libebml 1.3.4 | Heap Over-Read | USB `.mkv` file |
| **CVE-2023-26246** | AppDMClient | Firmware Signature Bypass | USB firmware files |

PoC files for libebml: `exploits/mkv/`. Firmware chain exploit: `exploits/` (3 variants).

### Patched / Not Exploitable

- **CVE-2018-14054** (libmp4v2): Patched in OE revision -r4
- **CVE-2018-14326** (libmp4v2): Partially patched (1M element cap)
- **BlueBorne**: `CONFIG_BT is not set` — no kernel Bluetooth stack
- **usb-automount command injection**: Uses `mount()` syscall, not `system()`. See **[exploits/RE_FINDINGS_usb_automount.md](exploits/RE_FINDINGS_usb_automount.md)**
- **ID3 tag parser**: Bounded MIME copy, all malloc sizes checked

### Exploitation Enablers

| Enabler | Impact |
|---------|--------|
| **No KASLR** | `CONFIG_RANDOMIZE_BASE is not set` — all addresses fixed |
| **KALLSYMS_ALL=y** | `/proc/kallsyms` exposes every kernel symbol |
| **DEVKMEM=y** | Direct kernel memory read/write via `/dev/kmem` |
| **CONFIG_MODULES=y** | Loadable kernel modules post-exploitation |
| **Root everywhere** | All services run as uid 0, no MAC |
| **glibc 2.25** | Pre-tcache — classic fastbin corruption applies |

---

## Exploit Strategy

Prioritized attack plan: **[EXPLOIT_STRATEGY.md](EXPLOIT_STRATEGY.md)**

### Priority 1: ASF Zero-Days via USB `.wma`
True zero-days, no CVE, no patch. Heap over-read + integer underflow compound to heap overflow. glibc 2.25 + no ASLR = ideal conditions. PoC files built and hardware-confirmed.

### Priority 2: libebml Heap Overflow via USB `.mkv`
CVE-2021-3405, unpatched. Heap overflow in `EbmlString::ReadData()`. PoC files built.

### Priority 3: Firmware Update Chain
Patched re-encrypted rootfs exploiting TOCTOU in `DecryptToPIPE` — data is streamed to extraction **before** RSA signature check completes. Even if RSA fails, the rootfs is already written.

### Priority 4: TOCTOU USB Gadget
Raspberry Pi Zero 2 W as USB mass storage gadget — serves genuine files during `checkHash`, swaps to modified files during extraction. See **[TOCTOU_ATTACK_PLAN.md](TOCTOU_ATTACK_PLAN.md)**.

---

## Firmware Encryption (Fully Broken)

All firmware files use AES-128-CBC with a hardcoded key shared across all LGE HKMC units:

| Parameter | Value |
|-----------|-------|
| **Key** | `60a93d70f73302a63e5ed0d0ea38be22` |
| **IV** | `SHA256(basename + int32_signed(payload_size))[:32]` per file |
| **Trailer** | 0x4024-byte TE2 footer with integrity hash |
| **Integrity** | `SHA256(IV_bytes \|\| metadata[36:])` at metadata[4:36] |

Tool: `exploits/tools/xcrypt.py` — encrypt, decrypt, and test firmware files.

```bash
python3 exploits/tools/xcrypt.py -d HU/images/mango-rootfs.tar.gz -o rootfs.dec
python3 exploits/tools/xcrypt.py -e rootfs-patched.tar.gz -o rootfs-reencrypted.tar.gz
python3 exploits/tools/xcrypt.py -t HU/images/mango-rootfs.tar.gz  # test only
```

---

## Jailbreak Deployment

Two approaches documented:

### A. Patched AppUpgrade Binary (CVE-2023-26246)
4 bytes patched in AppUpgrade to NOP/JMP over RSA verification. Rootfs modified with secure_console bypass, known root password, and persistence service.

Deploy instructions: **[DEPLOY_INSTRUCTIONS.md](DEPLOY_INSTRUCTIONS.md)**

### B. DecryptToPIPE Pipe-Before-Verify
Re-encrypted rootfs with reused TE2 trailer. Exploits the fact that `DecryptToPIPE` streams decrypted data via pipe before RSA check completes.

Test instructions: **[TEST_INSTRUCTIONS.md](TEST_INSTRUCTIONS.md)**

### Rootfs Patches Applied

| Patch | File | Effect |
|-------|------|--------|
| Secure console bypass | `/lib/systemd/esinit` line 478 | `rm /tmp/secure_console_disable` commented out |
| Known root password | `/etc/shadow.Global` | `root` / `cerato2022` |
| Persistent shell service | `jailbreak-shell.service` | socat on port 4444 after boot |
| Immediate payload | `/etc/smack-relabel-ro.sh` | Executes during SMACK relabeling |

---

## QEMU Virtual Machine

Boots the real automotive kernel (4.1.27-abl) inside QEMU with a BusyBox rootfs for analysis and testing.

### Prerequisites

```bash
brew install qemu e2fsprogs python3
pip3 install pycryptodome
```

### Setup

1. **Obtain firmware** — copy the update USB contents into `HU/images/` (gitignored)
2. **Prepare the VM**:
   ```bash
   cd vm
   # From encrypted iasImage:
   python3 vm_boot_au.py prepare --container /path/to/iasImage.encrypted
   # Or use the pre-extracted kernel:
   python3 vm_boot_au.py prepare --bzimage bzImage --busybox busybox
   ```
3. **Boot**:
   ```bash
   python3 vm_boot_au.py run
   ```
   Boots to root shell. `Ctrl-A X` to exit.

Options: `--sdhci-compat` (SD card emulation), `--display sdl` (graphical), `--timeout N`

### IVI GUI

```bash
bash start_ivi.sh          # Boot full IVI graphical environment
bash start_engineer.sh     # Switch to engineer mode (auto-enters PIN)
bash start_home.sh         # Switch back to home screen
```

VM details: **[vm/README.md](vm/README.md)**

---

## Project Structure

```
├── README.md                        # This file
├── FINDINGS.md                      # Full firmware analysis (system identity, boot
│                                    #   sequence, services, credentials, CVE inventory)
├── EXPLOIT_STRATEGY.md              # Prioritized attack vectors with exploit approaches
├── LGE_Gen5W_IVI_Security_Briefing.md  # Security research briefing and attack surface
├── JAILBREAK_INSTRUCTIONS.md        # Re-encrypted rootfs jailbreak walkthrough
├── DEPLOY_INSTRUCTIONS.md           # Patched AppUpgrade deployment to USB
├── TEST_INSTRUCTIONS.md             # DecryptToPIPE exploit test procedure
├── TOCTOU_ATTACK_PLAN.md            # Pi Zero USB gadget race condition attack
├── LAUNCH_ANALYSIS.md               # AppDMClient launchAppUpgrade flow analysis
│
├── exploits/
│   ├── VULNERABILITY_REPORT.md      # Master vulnerability report (all findings)
│   ├── EXPLOIT_FINDINGS.md          # LMS id3.so APIC heap overflow analysis
│   ├── ZERODAY_ASF_REPORT.md        # lms_asf.so zero-day detailed write-up
│   ├── RE_FINDINGS_usb_automount.md # usb-automount RE (ruled out injection)
│   ├── README.md                    # Exploit quick-start and USB layout
│   ├── tools/xcrypt.py              # AES firmware encryption/decryption
│   ├── asf/                         # ASF/WMA zero-day PoC files + generator
│   │   ├── crash_heap_overread.wma
│   │   ├── crash_heap_overread_v2.wma
│   │   ├── crash_int_underflow.wma
│   │   ├── crash_sign_extension.wma
│   │   └── asf_zeroday_poc.py
│   ├── mkv/                         # MKV/libebml CVE PoC files + generator
│   │   ├── poc_cve2021_3405_title.mkv
│   │   ├── poc_cve2021_3405_codec.mkv
│   │   ├── poc_cve2023_52339.mkv
│   │   ├── clean_reference.mkv
│   │   └── craft_mkv_poc.py
│   ├── bluetooth/                   # Bluetooth PBAP/HFP phone emulator (macOS)
│   │   └── bt_phone_emulator.swift
│   ├── gstreamer/                   # GStreamer pipeline analysis
│   ├── payload/                     # Shellcode and payload binaries
│   └── assemble_usb.sh             # Build exploit USB stick
│
├── vm/                              # QEMU virtual machine
│   ├── vm_boot_au.py                # Main VM launcher (prepare + run)
│   ├── bzImage                      # Extracted AU kernel 4.1.27-abl
│   ├── busybox                      # Static x86-64 BusyBox
│   ├── rootfs-overlay/              # Init script for guest rootfs
│   ├── run_qemu_vm.sh               # Simple shell launcher
│   └── README.md                    # VM-specific documentation
│
├── HU/                              # Head unit firmware (large files gitignored)
│   ├── images/                      # Encrypted firmware images
│   └── firmware/                    # Peripheral firmware, xcrypt.py
│
├── start_ivi.sh                     # Boot IVI GUI in QEMU
├── start_engineer.sh                # Switch to engineer mode (auto-PIN)
└── start_home.sh                    # Switch back to home screen
```

---

## Key Findings Summary

| Finding | Detail |
|---------|--------|
| **Encryption** | Fully broken — hardcoded AES key shared across all HKMC units |
| **Zero-days** | 3 in lms_asf.so (heap overread, int underflow, missing check) |
| **Unpatched CVEs** | 3 libebml + 1 firmware chain = 4 total |
| **ASLR** | Disabled (`CONFIG_RANDOMIZE_BASE is not set`) |
| **Privileges** | Everything runs as root, no MAC enforcement |
| **SSH** | Hardcoded LGE dev RSA key from 2018 baked into rootfs |
| **Root password** | SHA-512 hash in `shadow.Global`, shared across all units |
| **Firmware signing** | RSA-2048 via Teruten, but TOCTOU in DecryptToPIPE |
| **USB automount** | Safe — uses `mount()` syscall, not `system()` |
| **Kernel BT** | `CONFIG_BT` not set — all kernel BT CVEs inapplicable |

---

## Current Status

- **ASF zero-day PoCs**: Built and confirmed crashing on real hardware (USB)
- **MKV CVE PoCs**: Built, untested on hardware
- **Firmware update exploit**: Built (2 approaches), needs hardware testing
- **TOCTOU gadget**: Planned, requires Pi Zero 2 W hardware
- **Bluetooth**: macOS blocks incoming RFCOMM — PBAP contact delivery doesn't work from macOS
- **Code execution**: Not yet achieved — crashes confirmed, RCE payload in progress

---

## Credentials Reference

| Credential | Value |
|------------|-------|
| Engineer PIN | `19491003` |
| Dealer PIN | `2400` |
| AES firmware key | `60a93d70f73302a63e5ed0d0ea38be22` |
| Root password (jailbreak) | `cerato2022` |
| RSA public key | `/app/share/AppUpgrade/teruten5_pub.key` |
| SSH authorized key | `rsa-key-20181102` (LGE dev key, in rootfs) |
