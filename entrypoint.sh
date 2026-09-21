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

# 7b. Apply Antigravity branding to KasmVNC Web UI (ensures logo & title persistence across updates)
if [ -d /usr/share/kasmvnc/www ] && [ ! -f /usr/share/kasmvnc/www/assets/.antigravity_branded ]; then
    echo "[Init] Customizing KasmVNC Web UI with Antigravity branding..."
    if [ -f /opt/antigravity/resources/app/out/vs/platform/browserOnboarding/static/antigravity.svg ]; then
        cp /opt/antigravity/resources/app/out/vs/platform/browserOnboarding/static/antigravity.svg /usr/share/kasmvnc/www/assets/antigravity.svg 2>/dev/null || true
    fi
    if [ -f /opt/antigravity/resources/app/resources/linux/code.png ]; then
        cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/kasmvnc/www/assets/antigravity.png 2>/dev/null || true
        for f in /usr/share/kasmvnc/www/assets/368_kasm_logo_only_*.png; do
            cp /usr/share/kasmvnc/www/assets/antigravity.png "$f" 2>/dev/null || true
        done
    fi
    sed -i 's|<title>KasmVNC</title>|<title>Antigravity</title><link rel="icon" type="image/svg+xml" href="./assets/antigravity.svg"><link rel="icon" type="image/png" href="./assets/antigravity.png"><script>document.title="Antigravity";Object.defineProperty(document,"title",{get:function(){return"Antigravity"},set:function(){}});</script>|g' /usr/share/kasmvnc/www/index.html /usr/share/kasmvnc/www/vnc.html 2>/dev/null || true
    sed -i 's|document.title=n.detail.name+" - "+Sx|document.title="Antigravity"|g' /usr/share/kasmvnc/www/assets/ui-*.js 2>/dev/null || true
    sed -i 's|document.title=Sx|document.title="Antigravity"|g' /usr/share/kasmvnc/www/assets/ui-*.js 2>/dev/null || true
    python3 -c 'import re; [open(p, "w").write(re.sub(r"<h1 class=\"noVNC_logo\">.*?</h1>", "<h1 class=\"noVNC_logo\" style=\"background: rgba(255, 255, 255, 0.08); border-radius: 8px; padding: 10px 8px; margin: 5px 0 8px 0; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.2);\"><a href=\"https://antigravity.google\" target=\"_blank\" title=\"Google Antigravity IDE\" style=\"display: flex; align-items: center; justify-content: center; text-decoration: none; width: 100%;\"><img src=\"./assets/antigravity.png\" style=\"width: 28px; height: 28px; object-fit: contain;\" alt=\"Antigravity\"><span style=\"color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; font-size: 15px; font-weight: 600; letter-spacing: 0.5px; margin-left: 8px;\">Antigravity</span></a></h1><a href=\"/filebrowser/\" target=\"_blank\" rel=\"noopener noreferrer\" id=\"noVNC_filebrowser_link\" class=\"noVNC_button_div\" style=\"display: flex; align-items: center; padding: 8px 10px; margin: 6px 0 10px 0; background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease;\" onmouseover=\"this.style.background=\x27rgba(255, 255, 255, 0.18)\x27; this.style.borderColor=\x27rgba(255, 255, 255, 0.3)\x27;\" onmouseout=\"this.style.background=\x27rgba(255, 255, 255, 0.08)\x27; this.style.borderColor=\x27rgba(255, 255, 255, 0.12)\x27;\" onclick=\"event.preventDefault(); var u = \x27/filebrowser/\x27; if(window.location.port===\x278080\x27){ u = window.location.protocol+\x27//\x27+window.location.hostname+\x27:8081/filebrowser/\x27; } window.open(u, \x27_blank\x27, \x27noopener,noreferrer\x27);\" title=\"Open Web File Manager in a new window\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"margin-right: 10px; flex-shrink: 0; color: #60a5fa;\"><path d=\"M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z\"></path></svg><span style=\"font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;\">FileBrowser</span><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"13\" height=\"13\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"opacity: 0.6; flex-shrink: 0;\"><path d=\"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\"></path><polyline points=\"15 3 21 3 21 9\"></polyline><line x1=\"10\" y1=\"14\" x2=\"21\" y2=\"3\"></line></svg></a>", open(p).read())) for p in ["/usr/share/kasmvnc/www/index.html", "/usr/share/kasmvnc/www/vnc.html"]]' 2>/dev/null || true
    touch /usr/share/kasmvnc/www/assets/.antigravity_branded 2>/dev/null || true
fi

# 8. Start KasmVNC Server (port 8080, no built-in auth — secure via external proxy, display :1)
echo "[KasmVNC] Starting VNC/Web server on port 8080 (Desktop Name: Antigravity)..."
runuser -u antigravity -- vncserver :1 -name "Antigravity" -geometry 1920x1080 -depth 24 -websocketPort 8080 -SecurityTypes None -DisableBasicAuth

# 9. Start FileBrowser Quantum (port 8081, baseurl /filebrowser, root /home/antigravity)
echo "[FileBrowser] Starting FileBrowser Quantum on port 8081 (config: /etc/antigravity/filebrowser.yaml)..."
mkdir -p /tmp/filebrowser_cache
chown -R antigravity:antigravity /tmp/filebrowser_cache
runuser -u antigravity -- filebrowser -c /etc/antigravity/filebrowser.yaml > /tmp/filebrowser.log 2>&1 &
sleep 1
if ! pgrep -u antigravity -x filebrowser >/dev/null 2>&1; then
    echo "[FileBrowser] WARNING: FileBrowser process did not stay running! Log output:"
    cat /tmp/filebrowser.log 2>/dev/null || true
else
    echo "[FileBrowser] FileBrowser Quantum is running successfully (PID $(pgrep -u antigravity -x filebrowser))."
fi

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
