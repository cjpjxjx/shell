#!/bin/bash

# Monitor connectivity and kernel errors; reboot when both conditions meet.

# Resolve default gateway as target, fallback to 8.8.8.8
get_default_gateway() {
    if command -v ip > /dev/null 2>&1; then
        ip route 2>/dev/null | awk '/^default/ {print $3; exit}'
    elif command -v route > /dev/null 2>&1; then
        route -n 2>/dev/null | awk '/^0.0.0.0/ {print $2; exit}'
    fi
}

TARGET_IP="$(get_default_gateway)"
if [ -z "$TARGET_IP" ]; then
    TARGET_IP="8.8.8.8"
fi

# Kernel log keyword and monitor interval (seconds)
LOG_KEYWORD="Detected Hardware Unit Hang"
MONITOR_INTERVAL=60

# Log file (append only); only abnormal events are recorded
LOG_FILE="/var/log/network-watchdog.log"

while true
do
    # Step 1: check external connectivity
    ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "$(date): Network to $TARGET_IP is down. Checking kernel logs..." >> "$LOG_FILE"

        # Since last boot, kernel messages only
        if journalctl -b -k | grep -q "$LOG_KEYWORD"; then
            echo "$(date): CRITICAL: Found '$LOG_KEYWORD'. Rebooting..." >> "$LOG_FILE"
            /sbin/reboot
        else
            echo "$(date): Network is down, but '$LOG_KEYWORD' not found. Not rebooting." >> "$LOG_FILE"
        fi
    fi

    sleep "$MONITOR_INTERVAL"
done
