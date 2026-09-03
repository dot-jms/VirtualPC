#!/bin/bash
# Runs EVERY time the codespace starts (postStartCommand) — this is what actually
# brings the desktop back up, since VNC/websockify are running processes that
# die whenever the codespace stops and don't come back on their own.

sudo service dbus start 2>/dev/null || (sudo mkdir -p /run/dbus && sudo dbus-daemon --system --fork)
sudo mount -t tmpfs -o size=2G tmpfs /dev/shm 2>/dev/null || true

vncserver -kill :1 2>/dev/null || true
vncserver :1
websockify --web=/usr/share/novnc/ 6080 localhost:5901 &
