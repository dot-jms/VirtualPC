#!/bin/bash
# Runs ONCE automatically when the codespace is first created (postCreateCommand).
set -e

echo "Installing desktop + gaming stack — this takes several minutes the first time..."

### Clear any apt lock a background auto-update might be holding
sudo killall apt apt-get dpkg 2>/dev/null || true
sudo dpkg --configure -a

### Non-interactive installs (skips the hidden keyboard-layout prompt that can freeze installs)
export DEBIAN_FRONTEND=noninteractive

### Enable 32-bit arch, install desktop + VNC stack
# NOTE: tigervnc, NOT tightvnc — tightvnc has no GLX support, which causes
# "glXChooseVisual failed" crashes with Steam later.
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y dbus-x11 dbus python3-websockify novnc xfce4 xfce4-goodies \
    tigervnc-standalone-server wget pciutils bubblewrap \
    libgl1-mesa-dri libgl1-mesa-dri:i386 libglx-mesa0 libglx-mesa0:i386 \
    mesa-utils mesa-vulkan-drivers:i386 pulseaudio vlc

### VNC password + startup script
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

### Start dbus now (also happens on every start via start.sh)
sudo service dbus start 2>/dev/null || (sudo mkdir -p /run/dbus && sudo dbus-daemon --system --fork)

### Expand /dev/shm — default 64MB makes Chromium-based apps (Steam/Discord) crash-loop/flicker
sudo mount -t tmpfs -o size=2G tmpfs /dev/shm

### --- Steam ---
wget -q https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb -O /tmp/steam.deb
sudo apt install -y /tmp/steam.deb
rm /tmp/steam.deb

sudo chmod u+s /usr/bin/bwrap
find ~/.local/share/Steam -name "bwrap" -exec sudo chmod u+s {} + 2>/dev/null || true

# IMPORTANT: search PATH excluding /usr/local/bin, or this wrapper ends up
# calling itself forever on a rerun (100% CPU, no window, ever).
REAL_STEAM_BIN=$(PATH=/usr/games:/usr/bin:/bin command -v steam)
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

### --- Discord ---
wget -q -O /tmp/discord.deb "https://discord.com/api/download?platform=linux&format=deb"
sudo apt-get update && sudo apt-get install -y /tmp/discord.deb
rm /tmp/discord.deb

REAL_DISCORD_BIN=$(PATH=/usr/games:/usr/bin:/bin command -v discord)
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

### --- Firefox (real deb from Mozilla, not the missing firefox-esr / snap stub) ---
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
echo -e "Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000" | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
sudo apt update
sudo apt install -y firefox

echo ""
echo "Setup finished! The desktop will start automatically."
