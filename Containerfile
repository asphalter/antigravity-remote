FROM debian:bookworm-slim

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV DISPLAY=:1

# 1. Install system utilities, X11, Openbox, Electron runtime, and Podman
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    locales \
    sudo \
    procps \
    bash \
    git \
    nano \
    # Build tools for compiling native Node addons and C extensions inside the IDE terminal
    build-essential \
    tar \
    gzip \
    xz-utils \
    # GUI, X11 & Electron / Chromium runtime dependencies \
    xauth \
    x11-xserver-utils \
    openbox \
    libgl1 \
    libgl1-mesa-dri \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libxshmfence1 \
    libxkbfile1 \
    libsecret-1-0 \
    libgtk-3-0 \
    # Podman-in-Podman (rootless container runtime) \
    podman \
    fuse-overlayfs \
    slirp4netns \
    uidmap \
    dbus-user-session \
    # Web browser for SSO / OAuth login and xdg-open \
    chromium \
    xdg-utils \
    x11-utils \
    wmctrl \
    xdotool \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# 2. Install official KasmVNC Server 1.5.0 for Debian Bookworm
RUN curl -fSL -o /tmp/kasmvncserver.deb "https://github.com/kasmtech/KasmVNC/releases/download/v1.5.0/kasmvncserver_bookworm_1.5.0_amd64.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/kasmvncserver.deb \
    && rm -f /tmp/kasmvncserver.deb \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/share/kasmvnc /usr/local/share/kasmvnc

# 3. Install FileBrowser Quantum for Web-Native File Transfer (Upload/Download)
RUN curl -fsSL -o /usr/local/bin/filebrowser "https://github.com/gtsteffaniak/filebrowser/releases/download/v1.5.6-stable/linux-amd64-filebrowser" \
    && chmod +x /usr/local/bin/filebrowser

# 4. Dynamic download and baseline installation of Google Antigravity IDE Desktop
RUN set -ex; \
    echo "Resolving dynamic download URL for Antigravity IDE (Linux x64)..."; \
    URL=$(curl -sL "https://antigravity.google/download/?os=linux" | grep -o 'https://edgedl.me.gvt1.com/edgedl/release2/[^"]*linux-x64/Antigravity%20IDE\.tar\.gz' | head -n 1); \
    if [ -z "$URL" ]; then \
        echo "Notice: URL not found on download page. Using verified fallback URL..."; \
        URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"; \
    fi; \
    VERSION=$(echo "$URL" | sed -E 's|.*/stable/([^/]+)/.*|\1|'); \
    echo "Detected version: $VERSION"; \
    echo "Downloading from: $URL"; \
    curl -fSL "$URL" -o /tmp/antigravity.tar.gz; \
    mkdir -p /opt/antigravity; \
    tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity --strip-components=1; \
    rm -f /tmp/antigravity.tar.gz; \
    echo "$VERSION" > /opt/antigravity/version.txt; \
    chmod +x /opt/antigravity/antigravity-ide; \
    printf '#!/bin/bash\nexec /opt/antigravity/antigravity-ide --no-sandbox --disable-gpu --disable-dev-shm-usage "$@"\n' > /usr/local/bin/antigravity; \
    chmod +x /usr/local/bin/antigravity; \
    ln -sf /usr/local/bin/antigravity /usr/local/bin/antigravity-ide

# 5. Customize KasmVNC Web UI branding with official Antigravity IDE assets and lock title
RUN set -ex; \
    if [ -d /opt/antigravity/resources/app ]; then \
        cp /opt/antigravity/resources/app/out/vs/platform/browserOnboarding/static/antigravity.svg /usr/share/kasmvnc/www/assets/antigravity.svg 2>/dev/null || true; \
        cp /opt/antigravity/resources/app/resources/linux/code.png /usr/share/kasmvnc/www/assets/antigravity.png 2>/dev/null || true; \
        for f in /usr/share/kasmvnc/www/assets/368_kasm_logo_only_*.png; do \
            cp /usr/share/kasmvnc/www/assets/antigravity.png "$f" 2>/dev/null || true; \
        done; \
        sed -i 's|<title>KasmVNC</title>|<title>Antigravity</title><link rel="icon" type="image/svg+xml" href="./assets/antigravity.svg"><link rel="icon" type="image/png" href="./assets/antigravity.png"><script>document.title="Antigravity";Object.defineProperty(document,"title",{get:function(){return"Antigravity"},set:function(){}});</script>|g' /usr/share/kasmvnc/www/index.html /usr/share/kasmvnc/www/vnc.html 2>/dev/null || true; \
        sed -i 's|document.title=n.detail.name+" - "+Sx|document.title="Antigravity"|g' /usr/share/kasmvnc/www/assets/ui-*.js 2>/dev/null || true; \
        sed -i 's|document.title=Sx|document.title="Antigravity"|g' /usr/share/kasmvnc/www/assets/ui-*.js 2>/dev/null || true; \
        python3 -c 'import re; [open(p, "w").write(re.sub(r"<h1 class=\"noVNC_logo\">.*?</h1>", "<h1 class=\"noVNC_logo\" style=\"background: rgba(255, 255, 255, 0.08); border-radius: 8px; padding: 10px 8px; margin: 5px 0 8px 0; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.2);\"><a href=\"https://antigravity.google\" target=\"_blank\" title=\"Google Antigravity IDE\" style=\"display: flex; align-items: center; justify-content: center; text-decoration: none; width: 100%;\"><img src=\"./assets/antigravity.png\" style=\"width: 28px; height: 28px; object-fit: contain;\" alt=\"Antigravity\"><span style=\"color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; font-size: 15px; font-weight: 600; letter-spacing: 0.5px; margin-left: 8px;\">Antigravity</span></a></h1><a href=\"/filebrowser/\" target=\"_blank\" rel=\"noopener noreferrer\" id=\"noVNC_filebrowser_link\" class=\"noVNC_button_div\" style=\"display: flex; align-items: center; padding: 8px 10px; margin: 6px 0 10px 0; background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease;\" onmouseover=\"this.style.background=\x27rgba(255, 255, 255, 0.18)\x27; this.style.borderColor=\x27rgba(255, 255, 255, 0.3)\x27;\" onmouseout=\"this.style.background=\x27rgba(255, 255, 255, 0.08)\x27; this.style.borderColor=\x27rgba(255, 255, 255, 0.12)\x27;\" onclick=\"event.preventDefault(); var u = \x27/filebrowser/\x27; if(window.location.port===\x278080\x27){ u = window.location.protocol+\x27//\x27+window.location.hostname+\x27:8081/filebrowser/\x27; } window.open(u, \x27_blank\x27, \x27noopener,noreferrer\x27);\" title=\"Open Web File Manager in a new window\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"margin-right: 10px; flex-shrink: 0; color: #60a5fa;\"><path d=\"M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z\"></path></svg><span style=\"font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;\">FileBrowser</span><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"13\" height=\"13\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\" style=\"opacity: 0.6; flex-shrink: 0;\"><path d=\"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\"></path><polyline points=\"15 3 21 3 21 9\"></polyline><line x1=\"10\" y1=\"14\" x2=\"21\" y2=\"3\"></line></svg></a>", open(p).read())) for p in ["/usr/share/kasmvnc/www/index.html", "/usr/share/kasmvnc/www/vnc.html"]]' 2>/dev/null || true; \
        touch /usr/share/kasmvnc/www/assets/.antigravity_branded 2>/dev/null || true; \
    fi

# 6. Configure non-root 'antigravity' user (UID 1000) and subuid/subgid mapping
RUN useradd -m -u 1000 -s /bin/bash antigravity \
    && echo "antigravity ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/antigravity \
    && chmod 0440 /etc/sudoers.d/antigravity \
    && usermod -aG ssl-cert antigravity 2>/dev/null || true \
    && echo "antigravity:100000:65536" > /etc/subuid \
    && echo "antigravity:100000:65536" > /etc/subgid

# 7. Default nested Podman configuration
RUN mkdir -p /etc/containers \
    && printf '[containers]\ncgroups = "disabled"\nnetns = "host"\n\n[engine]\ncgroup_manager = "cgroupfs"\n' > /etc/containers/containers.conf

<<<<<<< HEAD
# 8. Prepare configuration staging directory
RUN mkdir -p /etc/antigravity

# 9. Copy configuration files and startup scripts
=======
# 7. Prepare configuration staging directory and copy configuration
RUN mkdir -p /etc/antigravity
>>>>>>> d4017df (add KasmVNC branding to Antigravity logos)
COPY config/ /etc/antigravity/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /etc/antigravity/openbox-autostart /etc/antigravity/brand_kasmvnc.py

# 8. Customize KasmVNC Web UI branding with official Antigravity IDE assets
RUN python3 /etc/antigravity/brand_kasmvnc.py || true

# 10. Expose KasmVNC Web UI (8080) and FileBrowser (8081)
EXPOSE 8080 8081

# Working directory
WORKDIR /home/antigravity

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
