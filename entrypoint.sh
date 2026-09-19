#!/bin/bash
set -e

echo "=========================================================="
echo "    Initializing Antigravity Remote (KasmVNC Desktop)"
echo "=========================================================="

# 1. Ensure permissions on /dev/fuse for nested Podman
if [ -e /dev/fuse ]; then
    chmod 666 /dev/fuse 2>/dev/null || true
fi

# 2. Setup home directory and ownership for antigravity user
mkdir -p /home/antigravity
# Only fix ownership on the home dir itself — NOT recursively.
# Recursive chown would walk the entire persistent volume on every boot,
# causing multi-minute startup delays as files accumulate.
chown antigravity:antigravity /home/antigravity

# 3. Check and auto-update Antigravity IDE on startup
check_and_update_antigravity() {
    local installed_ver="none"
    if [ -f /opt/antigravity/version.txt ]; then
        installed_ver=$(cat /opt/antigravity/version.txt | tr -d '[:space:]')
    fi
    echo "[Auto-Update] Installed local version: ${installed_ver}"

    echo "[Auto-Update] Checking for online updates (5s timeout)..."
    local remote_url
    remote_url=$(curl -sL -m 5 "https://antigravity.google/download/?os=linux" 2>/dev/null | grep -o 'https://edgedl.me.gvt1.com/edgedl/release2/[^"]*linux-x64/Antigravity%20IDE\.tar\.gz' | head -n 1 || true)

    if [ -z "$remote_url" ]; then
        echo "[Auto-Update] Online check unavailable (offline or timeout). Continuing with current version (${installed_ver})."
        return 0
    fi

    local remote_ver
    remote_ver=$(echo "$remote_url" | sed -E 's|.*/stable/([^/]+)/.*|\1|')
    echo "[Auto-Update] Latest online version available: ${remote_ver}"

    if [ "$remote_ver" != "$installed_ver" ] && [ -n "$remote_ver" ]; then
        echo "[Auto-Update] New version detected (${remote_ver} != ${installed_ver})!"
        echo "[Auto-Update] Downloading update from: ${remote_url}..."
        if curl -fSL -m 180 "$remote_url" -o /tmp/antigravity-update.tar.gz 2>/dev/null; then
            echo "[Auto-Update] Extracting new version to staging directory..."
            # Atomic update: extract to staging dir, then swap directories.
            # If extraction is interrupted, /opt/antigravity remains untouched.
            rm -rf /opt/antigravity-staging
            mkdir -p /opt/antigravity-staging
            if tar -xzf /tmp/antigravity-update.tar.gz -C /opt/antigravity-staging --strip-components=1; then
                echo "$remote_ver" > /opt/antigravity-staging/version.txt
                chmod +x /opt/antigravity-staging/antigravity-ide
                # Swap: old → backup, staging → live, then clean up
                rm -rf /opt/antigravity-old
                mv /opt/antigravity /opt/antigravity-old
                mv /opt/antigravity-staging /opt/antigravity
                rm -rf /opt/antigravity-old
                echo "[Auto-Update] Antigravity IDE successfully updated to version ${remote_ver}!"
                echo "[Auto-Update] Note: Conversations (~/.gemini), history, and projects in /home/antigravity are 100% preserved."
            else
                echo "[Auto-Update] Extraction failed. Keeping current version (${installed_ver})."
                rm -rf /opt/antigravity-staging
            fi
            rm -f /tmp/antigravity-update.tar.gz
        else
            echo "[Auto-Update] Download failed. Keeping current version (${installed_ver})."
            rm -f /tmp/antigravity-update.tar.gz
        fi
    else
        echo "[Auto-Update] Application is already at latest version (${installed_ver}). No download required."
    fi
}

check_and_update_antigravity

# 4. Configure Podman storage for persistent volume
if [ ! -f /home/antigravity/.config/containers/storage.conf ]; then
    echo "[Init] Configuring Podman storage (fuse-overlayfs)..."
    mkdir -p /home/antigravity/.config/containers
    cp /etc/antigravity/containers-storage.conf /home/antigravity/.config/containers/storage.conf
    chown -R antigravity:antigravity /home/antigravity/.config
fi

# 5. Configure Openbox Window Manager (only on first boot; preserves user customizations)
echo "[Init] Configuring Openbox window manager..."
mkdir -p /home/antigravity/.config/openbox
if [ ! -f /home/antigravity/.config/openbox/rc.xml ]; then
    cp /etc/antigravity/openbox-rc.xml /home/antigravity/.config/openbox/rc.xml
fi
if [ ! -f /home/antigravity/.config/openbox/autostart ]; then
    cp /etc/antigravity/openbox-autostart /home/antigravity/.config/openbox/autostart
    chmod +x /home/antigravity/.config/openbox/autostart
fi
chown -R antigravity:antigravity /home/antigravity/.config/openbox

# 6. Configure KasmVNC Server
echo "[Init] Configuring KasmVNC server..."
mkdir -p /home/antigravity/.vnc
cp /etc/antigravity/kasmvnc.yaml /home/antigravity/.vnc/kasmvnc.yaml
cp /etc/antigravity/kasmvnc.yaml /etc/kasmvnc/kasmvnc.yaml 2>/dev/null || true

# Create dummy credential to satisfy KasmVNC's internal password validator.
# Authentication is fully disabled (-SecurityTypes None -DisableBasicAuth),
# so this password is never actually checked or used.
echo -e "antigravity\nantigravity\n" | kasmvncpasswd -u antigravity -wo /home/antigravity/.kasmpasswd 2>/dev/null || true

# Mark DE selection as completed to avoid interactive prompts
touch /home/antigravity/.vnc/.de-was-selected

# X11 session startup script for KasmVNC
cat << 'EOF' > /home/antigravity/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec openbox-session
EOF
chmod +x /home/antigravity/.vnc/xstartup
chown -R antigravity:antigravity /home/antigravity/.vnc /home/antigravity/.kasmpasswd 2>/dev/null || true

# 7. Clean up any stale X11 locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# 8. Start KasmVNC Server (port 8080, no built-in auth — secure via external proxy, display :1)
echo "[KasmVNC] Starting VNC/Web server on port 8080 (SecurityTypes: None, DisableBasicAuth)..."
runuser -u antigravity -- vncserver :1 -geometry 1920x1080 -depth 24 -websocketPort 8080 -SecurityTypes None -DisableBasicAuth

# 9. Start FileBrowser (port 8081, baseurl /filebrowser, root /home/antigravity)
echo "[FileBrowser] Starting Web File Manager on port 8081 (baseurl: /filebrowser)..."
runuser -u antigravity -- filebrowser \
    --address 0.0.0.0 \
    --port 8081 \
    --root /home/antigravity \
    --baseurl /filebrowser \
    --database /tmp/filebrowser.db \
    --noauth >/dev/null 2>&1 &

echo "=========================================================="
echo " Antigravity Remote is ACTIVE and ready!"
echo " Web IDE UI:    http://<host>:8080/"
echo " File Manager:  http://<host>:8081/filebrowser/"
echo " Resolution:    Dynamic (1080p, 4K UHD auto-fit)"
echo "=========================================================="

# Graceful shutdown cleanup trap
cleanup() {
    echo "[Shutdown] Terminating services and active processes..."
    pkill -u antigravity filebrowser 2>/dev/null || true
    pkill -9 -u antigravity Xvnc 2>/dev/null || pkill -9 -u antigravity Xkasmvnc 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Keep container running while Xvnc is active
while pgrep -u antigravity Xvnc >/dev/null 2>&1 || pgrep -u antigravity Xkasmvnc >/dev/null 2>&1; do
    sleep 2
done

echo "[Error] KasmVNC server terminated unexpectedly."
exit 1
