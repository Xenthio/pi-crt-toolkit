#!/bin/bash
#
# Pi CRT Toolkit - RetroPie runcommand-onend.sh
# Runs AFTER an emulator exits
#
# This script:
# 1. Kills any background mode watcher
# 2. Reverts to 480i for EmulationStation
#

# Log for debugging
echo "[$(date +%T)] runcommand-onend triggered" >> /tmp/crt-runcommand.log

# Kill background mode watcher if running
if [[ -f /tmp/crt-mode-watcher.pid ]]; then
    kill $(cat /tmp/crt-mode-watcher.pid) 2>/dev/null
    rm -f /tmp/crt-mode-watcher.pid
fi

# Small delay for emulator to fully exit
sleep 0.5

# Revert to 480i for EmulationStation
# ES looks better in 480i, and menus are designed for it
TOOLKIT_DIR="/opt/crt-toolkit"
if [[ -f "$TOOLKIT_DIR/lib/video.sh" ]]; then
    source "$TOOLKIT_DIR/lib/video.sh"
    set_mode_480i 2>/dev/null
    echo "[$(date +%T)] Restored 480i mode" >> /tmp/crt-runcommand.log
fi

exit 0
