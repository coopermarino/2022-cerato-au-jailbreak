#!/bin/bash
# QEMU VM for Kia Gen5W IVI head unit firmware
# Boots the automotive rootfs using Alpine Linux kernel (the automotive kernel
# lacks virtio/9p/IDE drivers needed for QEMU)
#
# Prerequisites: brew install qemu e2fsprogs
# Usage: ./run_qemu_vm.sh          # text console only
#        ./run_qemu_vm.sh --gui    # graphical display (Weston/fbdev)
#
# The VM boots Alpine's kernel with the automotive rootfs on an ext4 disk.
# After login (root, no password), the automotive rootfs is at /
# Press Ctrl-A X to exit QEMU (text mode), or close the window (GUI mode).

set -e

SCRATCHPAD="/private/tmp/claude-501/-Users-coopermarino-Downloads-NaU-2022-Cerato-AU/cad71f24-4da9-4fef-a12f-9b1edfa745c6/scratchpad"
ALPINE_KERNEL="$SCRATCHPAD/alpine_extracted/boot/vmlinuz-virt"
ALPINE_INITRAMFS="$SCRATCHPAD/alpine_extracted/boot/initramfs-virt"
ALPINE_ISO="$SCRATCHPAD/alpine-virt.iso"
DISK_IMG="$SCRATCHPAD/rootfs_disk.img"

QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-x86_64}"

if ! "$QEMU" --version &>/dev/null; then
    echo "ERROR: qemu-system-x86_64 not found. Install with: brew install qemu"
    exit 1
fi

if [ ! -f "$DISK_IMG" ]; then
    echo "ERROR: Disk image not found at $DISK_IMG"
    echo "The ext4 disk image with the automotive rootfs must be created first."
    exit 1
fi

GUI_MODE=0
if [ "$1" = "--gui" ]; then
    GUI_MODE=1
fi

echo "=== Starting QEMU VM ==="
echo "Kernel: Alpine virt $(file "$ALPINE_KERNEL" | grep -o 'version [^ ]*')"
echo "Rootfs: $DISK_IMG ($(du -sh "$DISK_IMG" | awk '{print $1}'))"
echo "CPU: Skylake-Client (Apollo Lake compatible)"
echo "Mode: $([ $GUI_MODE -eq 1 ] && echo 'GUI (Weston/fbdev)' || echo 'Text console')"
echo ""
echo "Login: root (no password)"
echo ""

if [ $GUI_MODE -eq 1 ]; then
    # GUI mode: Skylake-Client CPU, VGA display, cocoa window
    # Console on ttyS0 as well for debug
    "$QEMU" \
        -M q35 \
        -cpu Skylake-Client \
        -m 2048 \
        -kernel "$ALPINE_KERNEL" \
        -initrd "$ALPINE_INITRAMFS" \
        -append "root=/dev/vda rootfstype=ext4 console=tty0 console=ttyS0 modules=loop,squashfs,sd-mod,usb-storage,virtio-blk alpine_dev=cdrom:sr0 modloop=/boot/modloop-virt rw" \
        -cdrom "$ALPINE_ISO" \
        -drive file="$DISK_IMG",format=raw,if=virtio \
        -display cocoa \
        -vga std \
        -no-reboot \
        -serial mon:stdio \
        -net nic,model=e1000 \
        -net user,hostfwd=tcp::4444-:4444,hostfwd=tcp::2222-:22
else
    # Text-only mode
    "$QEMU" \
        -M q35 \
        -cpu Skylake-Client \
        -m 2048 \
        -kernel "$ALPINE_KERNEL" \
        -initrd "$ALPINE_INITRAMFS" \
        -append "root=/dev/vda rootfstype=ext4 console=ttyS0 modules=loop,squashfs,sd-mod,usb-storage,virtio-blk alpine_dev=cdrom:sr0 modloop=/boot/modloop-virt rw" \
        -cdrom "$ALPINE_ISO" \
        -drive file="$DISK_IMG",format=raw,if=virtio \
        -nographic \
        -no-reboot \
        -serial mon:stdio \
        -net nic,model=e1000 \
        -net user,hostfwd=tcp::4444-:4444,hostfwd=tcp::2222-:22
fi
