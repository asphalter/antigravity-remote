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

# 3. Dynamic On-Demand Installation and Auto-Update of Google Antigravity IDE
FALLBACK_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"

check_and_update_antigravity() {
    local installed_ver="none"
    if [ -f /opt/antigravity/version.txt ]; then
        installed_ver=$(cat /opt/antigravity/version.txt | tr -d '[:space:]')
    fi
    echo "[App-Manager] Current local version: ${installed_ver}"

    local remote_url=""
    echo "[App-Manager] Querying latest Google Antigravity release (5s timeout)..."
    remote_url=$(curl -sL -m 5 "https://antigravity.google/download/?os=linux" 2>/dev/null | grep -o 'https://edgedl.me.gvt1.com/edgedl/release2/[^"]*linux-x64/Antigravity%20IDE\.tar\.gz' | head -n 1 || true)

    if [ -z "$remote_url" ]; then
        if [ "$installed_ver" = "none" ]; then
            echo "[App-Manager] Notice: Download page query timed out. Using verified baseline release URL..."
            remote_url="$FALLBACK_URL"
        else
            echo "[App-Manager] Online check unavailable (offline/timeout). Continuing with installed version (${installed_ver})."
            return 0
        fi
    fi

    local remote_ver
    remote_ver=$(echo "$remote_url" | sed -E 's|.*/stable/([^/]+)/.*|\1|')
    echo "[App-Manager] Latest available online version: ${remote_ver}"

    if [ "$remote_ver" != "$installed_ver" ]; then
        if [ "$installed_ver" = "none" ]; then
            echo "[App-Manager] Initial installation required. Downloading Antigravity IDE ${remote_ver}..."
        else
            echo "[App-Manager] New release detected (${remote_ver} != ${installed_ver})! Downloading update..."
        fi

        echo "[App-Manager] Fetching: ${remote_url}..."
        if curl -fSL -m 300 "$remote_url" -o /tmp/antigravity-download.tar.gz; then
            echo "[App-Manager] Extracting binaries to staging directory..."
            rm -rf /opt/antigravity-staging
            mkdir -p /opt/antigravity-staging
            if tar -xzf /tmp/antigravity-download.tar.gz -C /opt/antigravity-staging --strip-components=1; then
                echo "$remote_ver" > /opt/antigravity-staging/version.txt
                chmod +x /opt/antigravity-staging/antigravity-ide 2>/dev/null || true

                # Atomic swap: old → backup, staging → live, clean backup
                rm -rf /opt/antigravity-old
                if [ -d /opt/antigravity ] && [ "$installed_ver" != "none" ]; then
                    mv /opt/antigravity /opt/antigravity-old
                else
                    rm -rf /opt/antigravity
                fi
                mv /opt/antigravity-staging /opt/antigravity
                rm -rf /opt/antigravity-old

                # Ensure launcher wrapper script is in place
                printf '#!/bin/bash\nexec /opt/antigravity/antigravity-ide --no-sandbox --disable-gpu --disable-dev-shm-usage "$@"\n' > /usr/local/bin/antigravity
                chmod +x /usr/local/bin/antigravity
                ln -sf /usr/local/bin/antigravity /usr/local/bin/antigravity-ide

                echo "[App-Manager] Antigravity IDE ${remote_ver} installed and ready!"
                echo "[App-Manager] Note: Workspaces, settings, and agent conversations in /home/antigravity remain 100% intact."
            else
                echo "[App-Manager] ERROR: Extraction failed!"
                rm -rf /opt/antigravity-staging
                if [ "$installed_ver" = "none" ]; then
                    echo "[App-Manager] FATAL: Initial install failed, cannot start IDE."
                    exit 1
                fi
            fi
            rm -f /tmp/antigravity-download.tar.gz
        else
            echo "[App-Manager] ERROR: Download failed!"
            rm -f /tmp/antigravity-download.tar.gz
            if [ "$installed_ver" = "none" ]; then
                echo "[App-Manager] FATAL: Initial download failed, cannot start IDE."
                exit 1
            fi
        fi
    else
        echo "[App-Manager] Application is already at latest version (${installed_ver}). No download required."
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
    if [ -f /etc/antigravity/scripts/openbox-autostart ]; then
        cp /etc/antigravity/scripts/openbox-autostart /home/antigravity/.config/openbox/autostart
    else
        cp /etc/antigravity/openbox-autostart /home/antigravity/.config/openbox/autostart
    fi
    chmod +x /home/antigravity/.config/openbox/autostart
fi
chown -R antigravity:antigravity /home/antigravity/.config/openbox

# 5b. Pre-configure Agent review & auto-execution policy in state.vscdb
# Granular environment variables:
#   TERMINAL_AUTO_EXECUTION: eager (default: execute terminal commands autonomously) vs off
#   ARTIFACT_REVIEW_POLICY:  always (default: ask confirmation for implementation plans) vs turbo
term_env="${TERMINAL_AUTO_EXECUTION:-eager}"
art_env="${ARTIFACT_REVIEW_POLICY:-always}"

if [ -n "$term_env" ] || [ -n "$art_env" ]; then
    python3 -c '
import sqlite3, os, base64

db_dir = "/home/antigravity/.config/Antigravity IDE/User/globalStorage"
db_path = os.path.join(db_dir, "state.vscdb")
os.makedirs(db_dir, exist_ok=True)

term_env = os.environ.get("TERMINAL_AUTO_EXECUTION", "eager")
art_env = os.environ.get("ARTIFACT_REVIEW_POLICY", "always")

# Terminal Auto-Execution Policy:
# Default: EAGER (autonomous command execution)
term_eager = True
if term_env.lower() in ("false", "0", "off"):
    term_eager = False
elif term_env.lower() in ("true", "1", "eager", "auto"):
    term_eager = True

# Artifact / Implementation Plan Review Policy:
# Default: ALWAYS (asks confirmation before proceeding with implementation plans)
art_always = True
if art_env.lower() in ("turbo", "false", "auto"):
    art_always = False
elif art_env.lower() in ("always", "true"):
    art_always = True

term_val = "EAM=" if term_eager else "EAE="
art_val = "EAE=" if art_always else "EAI="

part1 = b"\n>\n\x18permission_grants_global\x12\"\n ChZleGVjdXRlX3VybChsb2NhbGhvc3Qp"
part2 = b"\n0\n&terminalAutoExecutionPolicySentinelKey\x12\x06\n\x04" + term_val.encode()
part3 = b"\n)\n\x1fartifactReviewPolicySentinelKey\x12\x06\n\x04" + art_val.encode()

agent_prefs_b64 = base64.b64encode(part1 + part2 + part3).decode()

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (\"antigravityUnifiedStateSync.agentPreferences\", ?)", (agent_prefs_b64,))
    conn.commit()
    conn.close()
    term_desc = "Autonomous (EAGER)" if term_eager else "Ask Confirmation (OFF)"
    art_desc = "Ask Confirmation (ALWAYS)" if art_always else "Auto-Proceed (TURBO)"
    print(f"[Init] Agent policies configured: Terminal = {term_desc}, Implementation Plans = {art_desc}")
except Exception as e:
    print(f"[Init] Warning: Could not update state.vscdb: {e}")
' 2>/dev/null || true
    chown -R antigravity:antigravity "/home/antigravity/.config/Antigravity IDE" 2>/dev/null || true
fi

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
if [ -d /usr/share/kasmvnc/www ]; then
    echo "[Init] Customizing KasmVNC Web UI with Antigravity branding..."
    if [ -f /etc/antigravity/scripts/brand_kasmvnc.py ]; then
        python3 /etc/antigravity/scripts/brand_kasmvnc.py || true
    else
        python3 /etc/antigravity/brand_kasmvnc.py || true
    fi
fi

# 8. Start KasmVNC Server (port 8080, no built-in auth — secure via external proxy, display :1)
echo "[KasmVNC] Starting VNC/Web server on port 8080 (Desktop Name: Antigravity)..."
runuser -u antigravity -- vncserver :1 -desktop Antigravity -geometry 1920x1080 -depth 24 -websocketPort 8080 -SecurityTypes None -DisableBasicAuth

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
