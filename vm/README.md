# Gen5W IVI Virtual Machine

QEMU-based VM for the LGE Gen5W IVI head unit (2022 Kia Cerato AU, BD_PE.AUS.S5W_L).

Boots the real automotive kernel (4.1.27-abl) with a BusyBox rootfs for firmware analysis, exploit development, and testing.

## Prerequisites

```bash
brew install qemu e2fsprogs
```

## Quick Start

The main tool is `vm_boot_au.py`. It has two phases:

### 1. Prepare (one-time setup)

Extracts the kernel from the encrypted iasImage, builds a BusyBox/ext4 rootfs disk, and sets up the workspace.

```bash
python3 vm_boot_au.py prepare --container /path/to/iasImage.encrypted
```

This creates a `bootable/` directory with `bzImage`, `rootfs.img`, and the init overlay.

If you already have the extracted `bzImage` and `busybox` binary in this repo, you can skip extraction and just build the disk:

```bash
python3 vm_boot_au.py prepare --bzimage bzImage --busybox busybox
```

### 2. Run

```bash
python3 vm_boot_au.py run
```

Options:
- `--sdhci-compat` — patch SDHCI PCI ID table in guest RAM for SD card emulation
- `--display` — QEMU display mode (default: none for serial-only)
- `--timeout` — auto-shutdown timer in seconds

The VM boots to a root shell on the serial console. Press `Ctrl-A X` to exit QEMU.

## Files

| File | Description |
|------|-------------|
| `vm_boot_au.py` | Main VM launcher (prepare + run) adapted for AU firmware |
| `bzImage` | Extracted AU kernel 4.1.27-abl (from iasImage) |
| `busybox` | Static x86-64 BusyBox for the guest rootfs |
| `rootfs-overlay/` | Init script and BusyBox for the ext4 rootfs |
| `run_qemu_vm.sh` | Simple shell launcher (Alpine kernel + automotive rootfs) |
| `start_ivi.sh` | GUI launcher with EGL/DRM shim and touch bridge |
| `prepare.json` | Build metadata and SHA-256 hashes |

## Architecture

- **Host**: macOS (Apple Silicon or Intel) with QEMU TCG
- **Guest**: x86-64, Intel Apollo Lake SoC emulation
- **Kernel**: 4.1.27-abl (automotive Linux, from encrypted firmware)
- **Rootfs**: Minimal BusyBox ext4 image (generated at prepare time)
- **Console**: Serial on stdio (115200 baud equivalent)

## Platform Details

- **IVI**: LGE Gen5W (HKMC Premium AVN 2.1)
- **OS**: OpenEmbedded 1.0 "mango"
- **glibc**: 2.25
- **systemd**: 225
- **Target**: BD_PE.AUS.S5W_L (Australian spec)
