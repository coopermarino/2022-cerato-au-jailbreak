#!/bin/bash
# start_ivi.sh — Boot the LGE Gen5W IVI head unit (BD_PE.AUS.S5W_L) in QEMU
# Runs AppHomeScreen with EGL/DRM shim and touch input bridge

SP="/private/tmp/claude-501/-Users-coopermarino-Downloads-NaU-2022-Cerato-AU/cad71f24-4da9-4fef-a12f-9b1edfa745c6/scratchpad"
QEMU="/opt/homebrew/bin/qemu-system-x86_64"
SERIAL_PORT=5556
MONITOR_PORT=5555

# ── Preflight ──────────────────────────────────────────────────────
for f in "$SP/alpine_extracted/boot/vmlinuz-virt" \
         "$SP/alpine_extracted/boot/initramfs-virt" \
         "$SP/rootfs_disk.img" \
         "$SP/dri_disk.img" \
         "$SP/gui_disk.img" \
         "$SP/bridge_disk.img"; do
    if [ ! -f "$f" ]; then
        echo "MISSING: $f"
        exit 1
    fi
done

# Kill any previous instance
pkill -f "qemu-system-x86_64.*tcp::${SERIAL_PORT}" 2>/dev/null
sleep 2

# ── Start QEMU ─────────────────────────────────────────────────────
echo "[1/3] Starting QEMU..."
$QEMU \
    -accel tcg,thread=multi \
    -cpu Nehalem \
    -smp 2 \
    -m 1G \
    -kernel "$SP/alpine_extracted/boot/vmlinuz-virt" \
    -initrd "$SP/alpine_extracted/boot/initramfs-virt" \
    -append "console=ttyS0 quiet mitigations=off" \
    -drive file="$SP/rootfs_disk.img",format=raw,if=virtio,cache=unsafe \
    -drive file="$SP/dri_disk.img",format=raw,if=virtio,cache=unsafe \
    -drive file="$SP/gui_disk.img",format=raw,if=virtio,cache=unsafe \
    -drive file="$SP/bridge_disk.img",format=raw,if=virtio,cache=unsafe \
    -device virtio-gpu-pci \
    -vga none \
    -display cocoa \
    -usb -device usb-tablet \
    -serial tcp::${SERIAL_PORT},server,nowait \
    -monitor tcp::${MONITOR_PORT},server,nowait \
    &
QEMU_PID=$!
echo "    QEMU PID: $QEMU_PID"

# ── Wait for Alpine boot ──────────────────────────────────────────
echo "[2/3] Waiting for Alpine to boot..."
sleep 15

# ── Boot IVI via single serial connection ─────────────────────────
# All commands run in the Alpine shell. The chroot command blocks the
# Alpine shell so only the IVI getty handles subsequent serial I/O.
echo "[3/3] Booting IVI system..."
(
cat << 'CMDS'
modprobe ext4
modprobe uinput
modprobe evdev
sleep 2
mkdir -p /mnt/root
mount /dev/vda /mnt/root
chroot /mnt/root /bin/sh /qemu_init.sh
CMDS
sleep 60
) | nc localhost $SERIAL_PORT >/dev/null 2>&1 &
NC_PID=$!

echo ""
echo "========================================"
echo "  IVI Head Unit Starting"
echo "========================================"
echo "  QEMU PID:       $QEMU_PID"
echo "  Serial console: nc localhost $SERIAL_PORT"
echo "  QEMU monitor:   nc localhost $MONITOR_PORT"
echo ""
echo "  The home screen will appear in ~45 seconds."
echo "  Move the mouse in the QEMU window to see the cursor."
echo "  Click to interact with the touchscreen."
echo "========================================"
echo ""
echo "  Waiting for boot to complete..."

# Wait for AppHomeScreen to appear
for i in $(seq 1 60); do
    if (printf '\nps\n'; sleep 1) | nc -w 2 localhost $SERIAL_PORT 2>/dev/null | grep -q AppHomeScreen; then
        echo "  AppHomeScreen is running!"
        break
    fi
    sleep 2
done

# Clean up the boot nc connection
kill $NC_PID 2>/dev/null
echo "  Done. Serial console ready: nc localhost $SERIAL_PORT"
