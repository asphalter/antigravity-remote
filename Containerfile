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

# 3. Dynamic download and baseline installation of Google Antigravity IDE Desktop
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

# 4. Configure non-root 'antigravity' user (UID 1000) and subuid/subgid mapping
RUN useradd -m -u 1000 -s /bin/bash antigravity \
    && echo "antigravity ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/antigravity \
    && chmod 0440 /etc/sudoers.d/antigravity \
    && usermod -aG ssl-cert antigravity 2>/dev/null || true \
    && echo "antigravity:100000:65536" > /etc/subuid \
    && echo "antigravity:100000:65536" > /etc/subgid

# 5. Default nested Podman configuration
RUN mkdir -p /etc/containers \
    && printf '[containers]\ncgroups = "disabled"\nnetns = "host"\n\n[engine]\ncgroup_manager = "cgroupfs"\n' > /etc/containers/containers.conf

# 6. Prepare configuration staging directory
RUN mkdir -p /etc/antigravity

# 7. Copy configuration files and startup scripts
COPY containers-storage.conf /etc/antigravity/containers-storage.conf
COPY kasmvnc.yaml /etc/antigravity/kasmvnc.yaml
COPY openbox-rc.xml /etc/antigravity/openbox-rc.xml
COPY openbox-autostart /etc/antigravity/openbox-autostart
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /etc/antigravity/openbox-autostart

# 8. Expose KasmVNC Web UI port (HTML5/WebSocket)
EXPOSE 8080

# Working directory
WORKDIR /home/antigravity

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
