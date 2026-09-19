# Antigravity Remote v4 — Web-Native Desktop Environment

A centralized, containerized development environment running **Google Antigravity IDE** on a headless server (`10.1.0.20`), seamlessly accessible from any modern web browser client (Windows, Linux, macOS, tablets) using standard HTML5 Canvas and WebSocket protocols, eliminating the need for local desktop clients or X11 forwarding.

---

## 1. System Architecture

Built on **Debian 12 Bookworm**, the stack integrates:
- **Google Antigravity IDE Desktop**: Native Electron application with complete IDE capabilities, extensions, and agent support.
- **Boot-Time Auto-Update**: Checks for new Google releases at startup and updates the core application binaries in-place while keeping user data and conversations 100% intact.
- **KasmVNC Server**: Next-generation VNC server with integrated web server, ultra-low-latency WebP compression, differential screen rect-encoding, bidirectional clipboard, and web file manager.
- **Openbox**: Ultra-lightweight window manager (~15 MB RAM) configured for borderless, maximized fullscreen execution.
- **Podman-in-Podman (Rootless)**: Enables running and building `podman` containers directly inside the IDE terminal.
- **Single-Port Exposure (8080)**: Exposes a single HTTP port to the host, ready to be secured behind any reverse proxy, VPN, or tunnel of your choice (e.g., Cloudflare Tunnel, Caddy, Nginx, Tailscale, WireGuard).

```
┌────────────────────────────────────────────────────────────────────────┐
│                              SERVER HOST                               │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐      │
│  │                     antigravity-remote                          │      │
│  │                                                              │      │
│  │  Debian 12 Bookworm                                          │      │
│  │  ┌────────────────────────────────────────────────────────┐  │      │
│  │  │ Antigravity IDE (Desktop GUI, Electron)                │  │      │
│  │  │   --no-sandbox, borderless maximized fullscreen        │  │      │
│  │  └───────────────────────────┬────────────────────────────┘  │      │
│  │                              │ X11 display :1                │      │
│  │  ┌───────────────────────────▼────────────────────────────┐  │      │
│  │  │ Openbox (Ultra-lightweight WM, ~15MB RAM)              │  │      │
│  │  └───────────────────────────┬────────────────────────────┘  │      │
│  │                              │                               │      │
│  │  ┌───────────────────────────▼────────────────────────────┐  │      │
│  │  │ KasmVNC Server (Web-Native HTML5/WebSocket)            │  │      │
│  │  │   - Dynamic resolution (1080p, 4K UHD, live resize)    │  │      │
│  │  │   - Auth disabled (-SecurityTypes None)                │  │      │
│  │  │   - Integrated Web File Manager (Upload/Download)      │  │      │
│  │  │   - Bidirectional web clipboard                        │  │      │
│  │  │   - Web port HTTP: 8080                                │  │      │
│  │  └───────────────────────────┬────────────────────────────┘  │      │
│  │                              │ 8080                          │      │
│  │  + Boot-time auto-update     │                               │      │
│  │  + Podman-in-Podman rootless │                               │      │
│  │  + 16 GB RAM / 8 CPU cores   │                               │      │
│  │  + Persistent volume: /home/antigravity                      │      │
│  │  └───────────────────────────┼───────────────────────────────┘      │
│                                 │ Port 8080                            │
│                                 ▼                                      │
│                     ┌───────────────────────┐                          │
│                     │  Reverse Proxy /      │                          │
│                     │  Tunnel / VPN         │                          │
│                     │  (user-managed)       │                          │
│                     └───────────────────────┘                          │
│                                 ▲                                      │
│                                 │ Auth (MFA / SSO / VPN)               │
│                        ┌────────┴────────┐                             │
│                        │ Browser Client  │                             │
│                        │ (1080p or 4K)    │                             │
│                        └─────────────────┘                             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Key Features

### Boot-Time Auto-Update & Data Preservation
On container startup, `entrypoint.sh` queries `https://antigravity.google/download/?os=linux` with a non-blocking 5-second safety timeout:
- If a newer release is published compared to `/opt/antigravity/version.txt`, it downloads and extracts the update into a staging directory, then atomically swaps it into place — ensuring the live installation is never left in a partial state.
- If already up-to-date, the check finishes in under 0.3s and the IDE boots instantly without re-downloading.
- If offline, it gracefully falls back to the installed version without blocking.
- **Data Safety Guarantee**: Updates strictly touch application binaries in `/opt/antigravity/`. All **agent conversations and transcripts** (`~/.gemini/`), **IDE settings and state** (`~/.config/Antigravity IDE`), **installed extensions** (`~/.antigravity-ide/`), and **workspaces** reside on the persistent volume `/home/antigravity` and are **never modified or lost**.

### Dynamic Resolution (4K UHD & 1080p)
KasmVNC dynamically adapts the virtual X11 resolution to match your browser viewport dimensions. Whether connecting from a 1080p laptop or a 4K workstation, the desktop scales smoothly with crystal-clear text rendering.

### Integrated Web File Manager
Slide open the KasmVNC control bar (left-edge handle or `Ctrl+Alt+Shift`):
- **Upload**: Drag-and-drop or browse files from your local device directly into `/home/antigravity`.
- **Download**: Browse container files and download them to your local device.

### Network Security
Local container authentication is intentionally disabled (`-SecurityTypes None -DisableBasicAuth`) to provide friction-free access within the trusted network. When exposing port 8080 to the internet, you should place it behind an authenticated reverse proxy, VPN, or tunnel that enforces your access control policies (MFA, SSO, IP allowlists, etc.).

---

## 3. Quick Start

### Launch with Script
To build the image and start the container with a single command:

```bash
cd 20260919-Antigravity_Remote
./run_env.sh
```

To bind to a custom host port (e.g. 9090):
```bash
ANTIGRAVITY_PORT=9090 ./run_env.sh
```

### Browser Access
Navigate in your browser to:
```
http://localhost:8080/
```
The Antigravity IDE interface will render immediately in fullscreen.

---

## 4. Deploying with Systemd Quadlet

Quadlet files allow managing the container as a native `systemd` service, providing auto-restart on boot and user-level isolation.

### Local Rootless Deployment
```bash
./deploy.sh --local
```

### Remote Server Deployment
```bash
./deploy.sh antigravity@10.1.0.20
```

### Service Management
```bash
# Check service status
systemctl --user status antigravity-remote.service

# View live container logs
journalctl --user -u antigravity-remote.service -f

# Restart service
systemctl --user restart antigravity-remote.service

# Stop service
systemctl --user stop antigravity-remote.service
```

---

## 5. Repository Layout

| File | Purpose |
| :--- | :--- |
| `Containerfile` | Debian 12, KasmVNC 1.5, Openbox, English system locale, baseline IDE install |
| `kasmvnc.yaml` | KasmVNC configuration (WebP, port 8080, dynamic resize, no auth) |
| `openbox-rc.xml` | Window manager configuration for borderless, maximized fullscreen |
| `openbox-autostart` | Resilient autostart loop for Antigravity IDE |
| `entrypoint.sh` | Container bootstrap, auto-update check (5s timeout), and service startup |
| `containers-storage.conf` | fuse-overlayfs configuration for nested Podman |
| `run_env.sh` | Interactive build and launch script with ANSI styling |
| `deploy.sh` | Automatic systemd Quadlet deployment script |
| `quadlet/` | Rootless Quadlet definitions (`antigravity-remote.container`, `antigravity-home.volume`) |
| `quadlet-rootful/` | Rootful Quadlet definitions for system-wide deployments |

---

## 6. Useful Container Commands

```bash
# Open an interactive bash shell as antigravity user
podman exec -it -u antigravity antigravity-remote bash

# Test rootless Podman-in-Podman (nested container execution)
podman exec -u antigravity antigravity-remote podman run --rm alpine echo "Podman OK"

# Monitor resource consumption (16 GB RAM / 8 CPU cores)
podman stats antigravity-remote
```
