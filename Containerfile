FROM debian:bookworm-slim

# 0. Display Antigravity Remote banner at start of compilation
COPY scripts/print_banner.sh /tmp/banner.sh
RUN /tmp/banner.sh && rm -f /tmp/banner.sh

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
    netavark \
    aardvark-dns \
    catatonit \
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

# 4. Prepare Antigravity IDE launcher wrapper (binary is fetched on-demand at container start)
RUN mkdir -p /opt/antigravity \
    && printf '#!/bin/bash\nexec /opt/antigravity/antigravity-ide --no-sandbox --disable-gpu --disable-dev-shm-usage "$@"\n' > /usr/local/bin/antigravity \
    && chmod +x /usr/local/bin/antigravity \
    && ln -sf /usr/local/bin/antigravity /usr/local/bin/antigravity-ide

# 5. Configure non-root 'antigravity' user (UID 1000) and subuid/subgid mapping
RUN useradd -m -u 1000 -s /bin/bash antigravity \
    && echo "antigravity ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/antigravity \
    && chmod 0440 /etc/sudoers.d/antigravity \
    && usermod -aG ssl-cert antigravity 2>/dev/null || true \
    && echo "antigravity:100000:65536" > /etc/subuid \
    && echo "antigravity:100000:65536" > /etc/subgid

# 6. Default nested Podman configuration
RUN mkdir -p /etc/containers \
    && printf '[containers]\ncgroups = "disabled"\n\n[engine]\ncgroup_manager = "cgroupfs"\n' > /etc/containers/containers.conf \
    && printf 'unqualified-search-registries = ["docker.io"]\n' > /etc/containers/registries.conf

# 7. Prepare staging directories and copy configuration, media assets, and scripts
RUN mkdir -p /etc/antigravity /etc/antigravity/media /etc/antigravity/scripts
COPY config/ /etc/antigravity/
COPY media/ /etc/antigravity/media/
COPY scripts/ /etc/antigravity/scripts/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /etc/antigravity/scripts/openbox-autostart /etc/antigravity/scripts/brand_kasmvnc.py

# 8. Customize KasmVNC Web UI branding with official Antigravity IDE assets
RUN python3 /etc/antigravity/scripts/brand_kasmvnc.py || true

# 10. Expose KasmVNC Web UI (8080) and FileBrowser (8081)
EXPOSE 8080 8081

# Working directory
WORKDIR /home/antigravity

# Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
