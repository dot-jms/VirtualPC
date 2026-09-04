#!/bin/bash
# Runs ONCE automatically when the codespace is first created (postCreateCommand).
#
# Everything is also mirrored to ~/setup.log — if this looks "stuck" in the
# Creation Log view, open a second terminal (Terminal -> New Terminal) and run:
#   tail -f ~/setup.log
# to watch it live.

LOG_FILE=~/setup.log
exec > >(tee -a "$LOG_FILE") 2>&1

TOTAL_STEPS=9
STEP=0
step() {
  STEP=$((STEP+1))
  echo ""
  echo "=================================================="
  echo "[STEP $STEP/$TOTAL_STEPS] $1   ($(date '+%H:%M:%S'))"
  echo "=================================================="
}

trap 'echo ""; echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; echo "SETUP FAILED at step $STEP, line $LINENO."; echo "Check ~/setup.log for the full output above this line."; echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"' ERR

set -e

echo "Starting full setup. This normally takes 5-10 minutes total —"
echo "long gaps of no new output during 'apt install' steps are NORMAL,"
echo "it's downloading/unpacking packages, not frozen."

step "Waiting for any background apt/dpkg activity to clear"
# Fresh Ubuntu containers run 'unattended-upgrades' on first boot, which holds
# the package lock for a few minutes. A single killall can race against it
# respawning. This loop actually waits it out and prints progress, so it's
# visible that we're waiting on THIS specifically instead of looking hung.
WAIT_SECONDS=0
MAX_WAIT=300
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
  if [ "$WAIT_SECONDS" -ge "$MAX_WAIT" ]; then
    echo "-> Lock still held after ${MAX_WAIT}s, forcing it clear..."
    sudo killall apt apt-get dpkg unattended-upgrade 2>/dev/null || true
    sleep 3
    break
  fi
  echo "-> Package lock held by another process (probably unattended-upgrades on first boot), waiting... (${WAIT_SECONDS}s elapsed)"
  sleep 10
  WAIT_SECONDS=$((WAIT_SECONDS+10))
done
sudo dpkg --configure -a
echo "-> apt/dpkg is free, continuing"

step "Installing desktop + VNC stack (this is the biggest step, ~2-4 min)"
export DEBIAN_FRONTEND=noninteractive
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y dbus-x11 dbus python3-websockify novnc xfce4 xfce4-goodies \
    tigervnc-standalone-server wget pciutils bubblewrap \
    libgl1-mesa-dri libgl1-mesa-dri:i386 libglx-mesa0 libglx-mesa0:i386 \
    mesa-utils mesa-vulkan-drivers:i386 pulseaudio vlc
echo "-> desktop packages installed"

step "Configuring VNC (password + startup script)"
mkdir -p ~/.vnc
echo "vscode" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
cat << 'XEOF' > ~/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export LIBGL_ALWAYS_SOFTWARE=1
exec startxfce4
XEOF
chmod +x ~/.vnc/xstartup
echo "-> VNC configured (password: vscode)"

step "Starting dbus + expanding shared memory"
sudo service dbus start 2>/dev/null || (sudo mkdir -p /run/dbus && sudo dbus-daemon --system --fork)
sudo mount -t tmpfs -o size=2G tmpfs /dev/shm
echo "-> dbus running, /dev/shm expanded to 2G"

step "Installing Steam"
echo "Downloading Steam installer..."
wget --progress=dot:giga https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb -O /tmp/steam.deb
echo "Download complete, installing..."
sudo apt install -y /tmp/steam.deb
rm /tmp/steam.deb

sudo chmod u+s /usr/bin/bwrap
find ~/.local/share/Steam -name "bwrap" -exec sudo chmod u+s {} + 2>/dev/null || true

# IMPORTANT: search PATH excluding /usr/local/bin, or this wrapper ends up
# calling itself forever on a rerun (100% CPU, no window, ever).
REAL_STEAM_BIN=$(PATH=/usr/games:/usr/bin:/bin command -v steam)
echo "Real Steam binary resolved to: $REAL_STEAM_BIN"
sudo tee /usr/local/bin/steam-wrapped > /dev/null << EOF
#!/bin/bash
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export PRESSURE_VESSEL_SHARE_HOME=1
export STEAM_RUNTIME_PREFER_HOST_LIBRARIES=0
exec "$REAL_STEAM_BIN" -no-cef-sandbox -disable-gpu "\$@"
EOF
sudo chmod +x /usr/local/bin/steam-wrapped
sudo ln -sf /usr/local/bin/steam-wrapped /usr/local/bin/steam

for f in /usr/share/applications/steam.desktop \
         ~/Desktop/steam.desktop \
         ~/.local/share/applications/steam.desktop; do
  [ -f "$f" ] && sudo sed -i "s|^Exec=.*|Exec=/usr/local/bin/steam-wrapped %U|" "$f" 2>/dev/null
done
echo "-> Steam installed and wrapped"

step "Installing Discord"
echo "Downloading Discord installer..."
wget --progress=dot:giga -O /tmp/discord.deb "https://discord.com/api/download?platform=linux&format=deb"
echo "Download complete, installing..."
sudo apt-get update && sudo apt-get install -y /tmp/discord.deb
rm /tmp/discord.deb

REAL_DISCORD_BIN=$(PATH=/usr/games:/usr/bin:/bin command -v discord)
echo "Real Discord binary resolved to: $REAL_DISCORD_BIN"
sudo tee /usr/local/bin/discord-wrapped > /dev/null << EOF
#!/bin/bash
export DISPLAY=:1
exec "$REAL_DISCORD_BIN" --no-sandbox "\$@"
EOF
sudo chmod +x /usr/local/bin/discord-wrapped
sudo ln -sf /usr/local/bin/discord-wrapped /usr/local/bin/discord

for f in /usr/share/applications/discord.desktop \
         ~/Desktop/discord.desktop \
         ~/.local/share/applications/discord.desktop; do
  [ -f "$f" ] && sudo sed -i "s|^Exec=.*|Exec=/usr/local/bin/discord-wrapped %U|" "$f" 2>/dev/null
done
echo "-> Discord installed and wrapped"

step "Installing Firefox (Mozilla's official repo)"
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
echo -e "Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000" | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
sudo apt update
sudo apt install -y firefox
echo "-> Firefox installed"

step "Verifying everything installed correctly"
for bin in steam discord firefox vncserver websockify; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  [OK] $bin found at $(command -v "$bin")"
  else
    echo "  [MISSING] $bin was not found on PATH!"
  fi
done

step "Done"
echo "Setup finished successfully at $(date '+%H:%M:%S')."
echo "Full log saved at: $LOG_FILE"
echo "The desktop itself starts via start.sh (postStartCommand) — check the Ports tab for 6080."
