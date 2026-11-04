#!/bin/bash
# start_home.sh — Switch the running IVI VM back to AppHomeScreen
# Requires start_ivi.sh to be running first.

SERIAL_PORT=5556

if ! nc -w 1 -z localhost $SERIAL_PORT 2>/dev/null; then
    echo "ERROR: IVI VM is not running. Start it first with: bash start_ivi.sh"
    exit 1
fi

echo "Switching to AppHomeScreen..."

(
cat << 'CMDS'

rm -f /tmp/ivi_mode
kill $(ps | grep AppEngineerMode | grep -v grep | awk '{print $1}') 2>/dev/null
kill $(ps | grep AppHomeScreen | grep -v grep | awk '{print $1}') 2>/dev/null
echo "MODE_SET=home"
CMDS
sleep 8
) | nc -w 12 localhost $SERIAL_PORT 2>&1 | grep -v "^$"

echo ""
echo "  AppHomeScreen restarting..."
echo "  Serial console: nc localhost $SERIAL_PORT"
