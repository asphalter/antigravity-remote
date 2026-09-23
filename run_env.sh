#!/bin/bash

# ==============================================================================
# run_env.sh — Launch Antigravity Remote Web Environment (KasmVNC Desktop)
#
# Usage:
#   ./run_env.sh                     # Launch on default port 8080
#   ANTIGRAVITY_PORT=9090 ./run_env.sh  # Launch on custom port
#
# Key Features:
#   - Web-Native interface (HTML5/WebSocket) via KasmVNC on port 8080
#   - Dynamic resolution adaptive to client browser (1080p, 4K UHD)
#   - Web File Manager (Upload/Download) integrated into side panel
#   - Unauthenticated container access (secure with your own reverse proxy / tunnel)
#   - Automatic update check at boot preserving all conversations and projects
#   - Rootless Podman-in-Podman container runtime
#   - Resource allocation: 16 GB RAM / 8 CPU cores
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE_NAME="${ANTIGRAVITY_IMAGE:-antigravity-remote}"
CONTAINER_NAME="${ANTIGRAVITY_CONTAINER:-antigravity-remote}"
VOLUME_NAME="${ANTIGRAVITY_VOLUME:-antigravity-home}"
HOST_PORT="${ANTIGRAVITY_PORT:-8080}"
FILEBROWSER_PORT="${ANTIGRAVITY_FB_PORT:-8081}"
TERMINAL_AUTO_EXECUTION="${TERMINAL_AUTO_EXECUTION:-eager}"
ARTIFACT_REVIEW_POLICY="${ARTIFACT_REVIEW_POLICY:-always}"

# Output styling colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Display official Antigravity ASCII banner
if [ -f "${SCRIPT_DIR}/scripts/print_banner.sh" ]; then
    "${SCRIPT_DIR}/scripts/print_banner.sh"
fi

echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Antigravity Remote — Web-Native Desktop Environment${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  IDE Port:            ${BOLD}${HOST_PORT}${NC}"
echo -e "  FileBrowser Port:    ${BOLD}${FILEBROWSER_PORT}${NC}"
echo -e "  Image:               ${BOLD}${IMAGE_NAME}${NC}"
echo -e "  Container:           ${BOLD}${CONTAINER_NAME}${NC}"
echo -e "  Home Volume:         ${BOLD}${VOLUME_NAME}${NC}"
echo -e "  Terminal Execution:  ${BOLD}${TERMINAL_AUTO_EXECUTION}${NC} (autonomous command execution)"
echo -e "  Plan Review Policy:  ${BOLD}${ARTIFACT_REVIEW_POLICY}${NC} (ask confirmation before execution)"
echo ""

# --------------------------------------------------------------------------
# 1. Build container image
# --------------------------------------------------------------------------
echo -e "${YELLOW}[1/4]${NC} Building container image ${IMAGE_NAME}..."
echo -e "       (Compiling lightweight base image; Antigravity IDE is fetched on-demand at startup)"
podman build -t "${IMAGE_NAME}" . < /dev/null
echo -e "${GREEN}[OK]${NC} Container image built successfully."
echo ""

# --------------------------------------------------------------------------
# 2. Cleanup previous container instances
# --------------------------------------------------------------------------
echo -e "${YELLOW}[2/4]${NC} Checking for existing containers..."
if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "       Existing container '${CONTAINER_NAME}' found. Removing..."
    podman rm -f "${CONTAINER_NAME}" > /dev/null 2>&1
    echo -e "${GREEN}[OK]${NC} Previous container removed."
else
    echo -e "${GREEN}[OK]${NC} No conflicting container found."
fi
echo ""

# --------------------------------------------------------------------------
# 3. Create or reuse persistent home volume
# --------------------------------------------------------------------------
echo -e "${YELLOW}[3/4]${NC} Preparing persistent volume ${VOLUME_NAME}..."
if ! podman volume exists "${VOLUME_NAME}" 2>/dev/null; then
    podman volume create "${VOLUME_NAME}" > /dev/null
    echo -e "${GREEN}[OK]${NC} Volume created successfully."
else
    echo -e "${GREEN}[OK]${NC} Existing persistent volume reused."
fi
echo ""

# --------------------------------------------------------------------------
# 4. Start container
# --------------------------------------------------------------------------
echo -e "${YELLOW}[4/4]${NC} Starting container ${CONTAINER_NAME}..."

podman run -d \
    --name "${CONTAINER_NAME}" \
    --device /dev/fuse \
    --cap-add=SYS_ADMIN --cap-add=MKNOD \
    --security-opt label=disable \
    --shm-size=2g \
    --memory=16g --cpus=8 \
    -e TERMINAL_AUTO_EXECUTION="${TERMINAL_AUTO_EXECUTION}" \
    -e ARTIFACT_REVIEW_POLICY="${ARTIFACT_REVIEW_POLICY}" \
    -v "${VOLUME_NAME}:/home/antigravity" \
    -p "${HOST_PORT}:8080" \
    -p "${FILEBROWSER_PORT}:8081" \
    "${IMAGE_NAME}" < /dev/null

echo -e "${GREEN}[OK]${NC} Container started."
echo ""

# --------------------------------------------------------------------------
# Summary and access instructions
# --------------------------------------------------------------------------
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Antigravity Remote environment is ready!${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Web Browser Access:${NC}"
echo -e "    IDE Desktop:      ${BOLD}http://localhost:${HOST_PORT}/${NC}"
echo -e "    File Manager:     ${BOLD}http://localhost:${FILEBROWSER_PORT}/filebrowser/${NC}"
echo -e "    Cloudflare Path:  ${BOLD}https://<domain>/filebrowser${NC} -> port ${FILEBROWSER_PORT}"
echo -e "    Authentication:   Disabled locally (enforce via Cloudflare Access / VPN)"
echo -e "    Resolution:       Dynamic (auto-adapts from 1080p to 4K UHD)"
echo ""
echo -e "  ${CYAN}Environment Features:${NC}"
echo -e "    ✓ Base OS: Debian 12 (Bookworm slim, English en_US.UTF-8 locale)"
echo -e "    ✓ Window Manager: Openbox (borderless fullscreen)"
echo -e "    ✓ Antigravity IDE: Electron desktop app with boot-time auto-update"
echo -e "    ✓ Container runtime: Rootless Podman-in-Podman (/dev/fuse + fuse-overlayfs)"
echo -e "    ✓ Resources: 16 GB RAM / 8 CPU cores"
echo -e "    ✓ Persistence: Volume '${VOLUME_NAME}' mounted at /home/antigravity"
echo -e "    ✓ Data Safety: Conversations, history, and workspaces preserved"
echo ""
echo -e "  ${CYAN}Management Commands:${NC}"
echo -e "    View logs:        podman logs -f ${CONTAINER_NAME}"
echo -e "    Enter shell:      podman exec -it -u antigravity ${CONTAINER_NAME} bash"
echo -e "    Stop container:   podman stop ${CONTAINER_NAME}"
echo -e "    Start container:  podman start ${CONTAINER_NAME}"
echo -e "    Remove container: podman rm -f ${CONTAINER_NAME}"
echo ""
echo -e "  ${CYAN}Health Check:${NC}"
echo -e "    curl -I http://localhost:${HOST_PORT}/"
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
