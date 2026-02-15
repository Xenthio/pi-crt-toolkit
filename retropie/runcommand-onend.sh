#!/bin/bash
#
# Pi CRT Toolkit - RetroPie runcommand-onend.sh
# Runs AFTER an emulator exits
#
# This script:
# 1. Kills any background mode watcher
# 2. Reverts to 480i for EmulationStation
#

# Kill background mode watcher if running
if [[ -f /tmp/crt-mode-watcher.pid ]]; then
    kill $(cat /tmp/crt-mode-watcher.pid) 2>/dev/null
    rm -f /tmp/crt-mode-watcher.pid
fi

# Small delay for emulator to fully exit
sleep 0.5

# Revert to 480i for EmulationStation
# ES looks better in 480i, and menus are designed for it
if command -v tvservice &>/dev/null; then
    tvservice -c "NTSC 4:3" 2>/dev/null
fi

exit 0
