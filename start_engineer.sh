#!/bin/bash
# start_engineer.sh — Switch the running IVI VM to AppEngineerMode
# Requires start_ivi.sh to be running first.
# Engineer PIN: 19491003 | Dealer PIN: 2400

SERIAL_PORT=5556
MONITOR_PORT=5555

if ! nc -w 1 -z localhost $SERIAL_PORT 2>/dev/null; then
    echo "ERROR: IVI VM is not running. Start it first with: bash start_ivi.sh"
    exit 1
fi

echo "Switching to AppEngineerMode..."

# Set the mode flag and kill the current app — the respawn loop
# will restart with AppEngineerMode in the same environment
(
cat << 'CMDS'

echo engineer > /tmp/ivi_mode
# Kill whichever app is running — the respawn loop will restart with engineer mode
kill $(ps | grep AppHomeScreen | grep -v grep | awk '{print $1}') 2>/dev/null
kill $(ps | grep AppEngineerMode | grep -v grep | awk '{print $1}') 2>/dev/null
echo "MODE_SET=engineer"
CMDS
sleep 8
) | nc -w 12 localhost $SERIAL_PORT 2>&1 | grep -v "^$"

echo ""
echo "  Waiting for AppEngineerMode to start..."
sleep 8

# ── Auto-enter Engineer PIN via QEMU monitor ─────────────────────
# PIN: 19491003
# Keypad layout on 1280x800 screen (from screenshot):
#   Col centers: ~500, ~685, ~860
#   Row1 (1,2,3): y~390  Row2 (4,5,6): y~480
#   Row3 (7,8,9): y~565  Row4 (Del,0,⌫): y~650
# QEMU monitor mouse_move uses absolute coords 0-32767

tap_button() {
    local x=$1 y=$2
    local ax=$(( x * 32767 / 1280 ))
    local ay=$(( y * 32767 / 800 ))
    (printf "mouse_move %d %d\n" "$ax" "$ay"; sleep 0.1) | nc -w 2 localhost $MONITOR_PORT >/dev/null 2>&1
    sleep 0.15
    (printf "mouse_button 1\n"; sleep 0.1) | nc -w 2 localhost $MONITOR_PORT >/dev/null 2>&1
    sleep 0.1
    (printf "mouse_button 0\n"; sleep 0.1) | nc -w 2 localhost $MONITOR_PORT >/dev/null 2>&1
    sleep 0.4
}

# Button coordinates (screen pixels)
B1_X=500;  B1_Y=390
B2_X=685;  B2_Y=390
B3_X=860;  B3_Y=390
B4_X=500;  B4_Y=480
B5_X=685;  B5_Y=480
B6_X=860;  B6_Y=480
B7_X=500;  B7_Y=565
B8_X=685;  B8_Y=565
B9_X=860;  B9_Y=565
B0_X=685;  B0_Y=650

echo "  Entering Engineer PIN: 19491003..."

# PIN: 1-9-4-9-1-0-0-3
tap_button $B1_X $B1_Y  # 1
tap_button $B9_X $B9_Y  # 9
tap_button $B4_X $B4_Y  # 4
tap_button $B9_X $B9_Y  # 9
tap_button $B1_X $B1_Y  # 1
tap_button $B0_X $B0_Y  # 0
tap_button $B0_X $B0_Y  # 0
tap_button $B3_X $B3_Y  # 3

echo "  PIN entered!"
echo ""
echo "========================================"
echo "  Engineer Mode"
echo "========================================"
echo "  Serial console: nc localhost $SERIAL_PORT"
echo "  Log: cat /tmp/appengineer.log"
echo ""
echo "  To go back to home screen:"
echo "    bash start_home.sh"
echo "========================================"
