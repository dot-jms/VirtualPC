#!/bin/bash
# Runs EVERY time the codespace starts (postStartCommand) — this is what
# actually brings the desktop back up, since VNC/websockify are running
# processes that die whenever the codespace stops.
#
# Logs to ~/start.log — if the desktop isn't loading after a restart,
# run: cat ~/start.log

LOG_FILE=~/start.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "===== start.sh running at $(date '+%H:%M:%S') ====="

echo "[1/4] Starting dbus..."
sudo service dbus start 2>/dev/null || (sudo mkdir -p /run/dbus && sudo dbus-daemon --system --fork)
echo "-> dbus OK"

echo "[2/4] Expanding /dev/shm..."
sudo mount -t tmpfs -o size=2G tmpfs /dev/shm 2>/dev/null || echo "-> already mounted, skipping"

echo "[3/4] Starting VNC server on :1..."
vncserver -kill :1 2>/dev/null || true
vncserver :1
if pgrep -x Xtigervnc > /dev/null; then
  echo "-> VNC server is running"
else
  echo "-> WARNING: VNC server does not appear to be running, check errors above"
fi

echo "[4/4] Starting websockify (VNC -> browser bridge on port 6080)..."
websockify --web=/usr/share/novnc/ 6080 localhost:5901 &
sleep 2
if pgrep -f "websockify.*6080" > /dev/null; then
  echo "-> websockify is running, port 6080 should be live"
else
  echo "-> WARNING: websockify does not appear to be running"
fi

echo "===== start.sh finished. Desktop should be reachable on port 6080. ====="
