#!/usr/bin/env bash
# =============================================================================
# post-install.sh — Linux Mint Post-Installation Script
# =============================================================================
# Purpose  : Set up a data-engineering & software-development environment on a
#            fresh Linux Mint installation.
# Usage    : bash post-install.sh
# Idempotent: safe to run multiple times — already-installed steps are skipped.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
step "Checking prerequisites"

# Ensure we are NOT running as root (we will use sudo where needed)
if [[ "${EUID}" -eq 0 ]]; then
    error "Do not run this script as root. Run it as your normal user."
    exit 1
fi

# Ensure sudo is available and credentials are cached
if ! sudo -v; then
    error "sudo access is required. Please configure sudo for your user."
    exit 1
fi

# Keep sudo alive for the duration of the script
(while true; do sudo -v; sleep 55; done) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null; exit' EXIT INT TERM

# Ensure required tools are present before we begin
for tool in curl wget jq; do
    if ! command -v "${tool}" &>/dev/null; then
        info "Installing missing prerequisite: ${tool}"
        sudo apt-get install -y "${tool}"
    fi
done

success "Prerequisites satisfied"

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------
step "Creating ~/apps/ directory structure"

APPS_DIR="${HOME}/apps"
mkdir -p "${APPS_DIR}"
success "${APPS_DIR} is ready"

# ---------------------------------------------------------------------------
# Helper — create a .desktop entry
# ---------------------------------------------------------------------------
# Usage: create_desktop_entry <AppName> <exec_path> <icon_path> [<categories>]
create_desktop_entry() {
    local name="${1}"
    local exec_path="${2}"
    local icon_path="${3}"
    local categories="${4:-Application}"

    local desktop_dir="${HOME}/.local/share/applications"
    mkdir -p "${desktop_dir}"

    local desktop_file="${desktop_dir}/${name,,}.desktop"  # lowercase name

    cat > "${desktop_file}" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Exec=${exec_path}
Icon=${icon_path}
Categories=${categories}
Terminal=false
StartupNotify=true
EOF

    chmod +x "${desktop_file}"
    success "Desktop entry created: ${desktop_file}"
}

# ---------------------------------------------------------------------------
# Helper — fetch latest GitHub release asset URL
# ---------------------------------------------------------------------------
# Usage: get_github_release_url <owner/repo> <pattern>
#   Returns the browser_download_url of the first asset matching <pattern>.
get_github_release_url() {
    local repo="${1}"
    local pattern="${2}"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r ".assets[] | select(.name | test(\"${pattern}\")) | .browser_download_url" \
        | head -n1
}

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
step "Updating system packages"
sudo apt-get update -y
sudo apt-get upgrade -y
success "System is up to date"

# ---------------------------------------------------------------------------
# 2. System & media codecs
# ---------------------------------------------------------------------------
step "Installing media codecs and restricted extras"

sudo apt-get install -y \
    mint-meta-codecs \
    ubuntu-restricted-extras \
    libavcodec-extra

success "Media codecs installed"

# ---------------------------------------------------------------------------
# 3. Proprietary graphics driver prompt
# ---------------------------------------------------------------------------
step "Checking for proprietary graphics drivers"

if command -v ubuntu-drivers &>/dev/null; then
    RECOMMENDED=$(ubuntu-drivers devices 2>/dev/null \
        | grep recommended \
        | awk '{print $NF}' \
        | head -n1 || true)
    if [[ -n "${RECOMMENDED}" ]]; then
        warn "Recommended driver detected: ${RECOMMENDED}"
        read -r -p "Install recommended graphics driver '${RECOMMENDED}'? [y/N] " _resp
        if [[ "${_resp}" =~ ^[Yy]$ ]]; then
            sudo ubuntu-drivers autoinstall
            success "Graphics driver installed. A reboot is recommended."
        else
            info "Skipping graphics driver installation."
        fi
    else
        info "No additional proprietary graphics drivers recommended."
    fi
else
    warn "ubuntu-drivers utility not found; skipping graphics driver check."
fi

# ---------------------------------------------------------------------------
# 4. PostgreSQL — via official apt repository
# ---------------------------------------------------------------------------
step "Installing PostgreSQL via official repository"

PG_KEYRING="/usr/share/keyrings/postgresql-archive-keyring.gpg"

if ! dpkg -l postgresql &>/dev/null 2>&1; then
    # Add the official PostgreSQL signing key
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | sudo gpg --dearmor -o "${PG_KEYRING}"

    # Add the apt repository
    echo "deb [signed-by=${PG_KEYRING}] https://apt.postgresql.org/pub/repos/apt \
$(lsb_release -cs)-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y postgresql postgresql-contrib
    success "PostgreSQL installed"

    # Start and enable the service
    sudo systemctl enable --now postgresql

    # Create a local database role matching the current OS user
    PG_USER="${USER}"
    PG_DB="${USER}"
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" \
            | grep -q 1; then
        sudo -u postgres createuser --superuser "${PG_USER}"
        success "PostgreSQL role '${PG_USER}' created"
    else
        info "PostgreSQL role '${PG_USER}' already exists"
    fi

    if ! sudo -u postgres psql -lqt | cut -d\| -f1 | grep -qw "${PG_DB}"; then
        sudo -u postgres createdb -O "${PG_USER}" "${PG_DB}"
        success "PostgreSQL database '${PG_DB}' created"
    else
        info "PostgreSQL database '${PG_DB}' already exists"
    fi
else
    info "PostgreSQL already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 5. Telegram
# ---------------------------------------------------------------------------
step "Installing Telegram Desktop"

TELEGRAM_DIR="${APPS_DIR}/telegram"

if [[ ! -f "${TELEGRAM_DIR}/Telegram" ]]; then
    mkdir -p "${TELEGRAM_DIR}"

    info "Fetching latest Telegram download URL…"
    # Official Telegram always publishes the latest at this stable URL
    TELEGRAM_URL="https://telegram.org/dl/desktop/linux"

    TMP_TG=$(mktemp --suffix=.tar.xz)
    wget -q --show-progress -O "${TMP_TG}" "${TELEGRAM_URL}"

    info "Extracting Telegram…"
    tar -xJf "${TMP_TG}" -C "${TELEGRAM_DIR}" --strip-components=1
    rm -f "${TMP_TG}"

    create_desktop_entry \
        "Telegram" \
        "${TELEGRAM_DIR}/Telegram" \
        "${TELEGRAM_DIR}/telegram.png" \
        "Network;InstantMessaging;"

    success "Telegram installed to ${TELEGRAM_DIR}"
else
    info "Telegram already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 6. Zen Browser
# ---------------------------------------------------------------------------
step "Installing Zen Browser"

ZEN_DIR="${APPS_DIR}/zen"

if [[ ! -f "${ZEN_DIR}/zen" ]]; then
    mkdir -p "${ZEN_DIR}"

    info "Fetching latest Zen Browser release URL from GitHub…"
    # Zen Browser publishes Linux tarballs on GitHub
    ZEN_URL=$(get_github_release_url "zen-browser/desktop" "linux-x86_64\\.tar\\.bz2$")

    if [[ -z "${ZEN_URL}" ]]; then
        # Fallback: try generic linux tarball pattern
        ZEN_URL=$(get_github_release_url "zen-browser/desktop" "linux.*\\.tar\\.gz$")
    fi

    if [[ -z "${ZEN_URL}" ]]; then
        warn "Could not determine Zen Browser download URL — skipping."
    else
        # Determine compression from URL before creating temp file
        if [[ "${ZEN_URL}" == *.tar.bz2 ]]; then
            TMP_ZEN=$(mktemp --suffix=.tar.bz2)
        else
            TMP_ZEN=$(mktemp --suffix=.tar.gz)
        fi
        wget -q --show-progress -O "${TMP_ZEN}" "${ZEN_URL}"

        info "Extracting Zen Browser…"
        if [[ "${ZEN_URL}" == *.tar.bz2 ]]; then
            tar -xjf "${TMP_ZEN}" -C "${ZEN_DIR}" --strip-components=1
        else
            tar -xzf "${TMP_ZEN}" -C "${ZEN_DIR}" --strip-components=1
        fi
        rm -f "${TMP_ZEN}"

        # The binary may be named 'zen' or 'zen-browser'
        ZEN_BIN="${ZEN_DIR}/zen"
        [[ ! -f "${ZEN_BIN}" ]] && ZEN_BIN="${ZEN_DIR}/zen-browser"

        create_desktop_entry \
            "Zen Browser" \
            "${ZEN_BIN}" \
            "${ZEN_DIR}/browser/chrome/icons/default/default128.png" \
            "Network;WebBrowser;"

        success "Zen Browser installed to ${ZEN_DIR}"
    fi
else
    info "Zen Browser already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 7. Zed Editor
# ---------------------------------------------------------------------------
step "Installing Zed Editor"

ZED_BIN="${HOME}/.local/bin/zed"

if [[ ! -f "${ZED_BIN}" ]]; then
    info "Running official Zed standalone installer…"
    curl -fsSL https://zed.dev/install.sh | bash

    # The installer places the binary at ~/.local/bin/zed; create a desktop entry
    ZED_ICON="${HOME}/.local/share/zed/icons/zed.png"
    create_desktop_entry \
        "Zed" \
        "${ZED_BIN}" \
        "${ZED_ICON}" \
        "Development;TextEditor;"

    success "Zed Editor installed"
else
    info "Zed Editor already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 8. Discord
# ---------------------------------------------------------------------------
step "Installing Discord"

DISCORD_DIR="${APPS_DIR}/discord"

if [[ ! -f "${DISCORD_DIR}/Discord" ]]; then
    mkdir -p "${DISCORD_DIR}"

    info "Fetching latest Discord Linux tarball…"
    # Discord's stable endpoint always redirects to the latest version
    DISCORD_URL="https://discord.com/api/download?platform=linux&format=tar.gz"

    TMP_DISCORD=$(mktemp --suffix=.tar.gz)
    wget -q --show-progress --content-disposition -O "${TMP_DISCORD}" "${DISCORD_URL}"

    info "Extracting Discord…"
    tar -xzf "${TMP_DISCORD}" -C "${DISCORD_DIR}" --strip-components=1
    rm -f "${TMP_DISCORD}"

    create_desktop_entry \
        "Discord" \
        "${DISCORD_DIR}/Discord" \
        "${DISCORD_DIR}/discord.png" \
        "Network;InstantMessaging;"

    success "Discord installed to ${DISCORD_DIR}"
else
    info "Discord already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 9. DBeaver Community Edition
# ---------------------------------------------------------------------------
step "Installing DBeaver Community Edition"

DBEAVER_DIR="${APPS_DIR}/dbeaver"

if [[ ! -f "${DBEAVER_DIR}/dbeaver" ]]; then
    mkdir -p "${DBEAVER_DIR}"

    info "Fetching latest DBeaver release URL from GitHub…"
    DBEAVER_URL=$(get_github_release_url "dbeaver/dbeaver" "dbeaver-ce-.*-linux\\.gtk\\.x86_64\\.tar\\.gz$")

    if [[ -z "${DBEAVER_URL}" ]]; then
        warn "Could not determine DBeaver download URL — skipping."
    else
        TMP_DB=$(mktemp --suffix=.tar.gz)
        wget -q --show-progress -O "${TMP_DB}" "${DBEAVER_URL}"

        info "Extracting DBeaver…"
        tar -xzf "${TMP_DB}" -C "${DBEAVER_DIR}" --strip-components=1
        rm -f "${TMP_DB}"

        create_desktop_entry \
            "DBeaver" \
            "${DBEAVER_DIR}/dbeaver" \
            "${DBEAVER_DIR}/dbeaver.png" \
            "Development;Database;"

        success "DBeaver installed to ${DBEAVER_DIR}"
    fi
else
    info "DBeaver already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 10. VS Code — official Microsoft apt repository
# ---------------------------------------------------------------------------
step "Installing Visual Studio Code"

if ! command -v code &>/dev/null; then
    info "Adding Microsoft GPG key and apt repository for VS Code…"

    VSCODE_KEYRING="/usr/share/keyrings/microsoft-archive-keyring.gpg"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | sudo gpg --dearmor -o "${VSCODE_KEYRING}"

    echo "deb [arch=amd64 signed-by=${VSCODE_KEYRING}] \
https://packages.microsoft.com/repos/vscode stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y code
    success "Visual Studio Code installed"
else
    info "VS Code already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 11. Spotify — official apt repository
# ---------------------------------------------------------------------------
step "Installing Spotify"

if ! command -v spotify &>/dev/null; then
    info "Adding Spotify GPG key and apt repository…"

    SPOTIFY_KEYRING="/usr/share/keyrings/spotify-archive-keyring.gpg"
    curl -fsSL https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg \
        | sudo gpg --dearmor -o "${SPOTIFY_KEYRING}"

    echo "deb [signed-by=${SPOTIFY_KEYRING}] https://repository.spotify.com stable non-free" \
        | sudo tee /etc/apt/sources.list.d/spotify.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y spotify-client
    success "Spotify installed"
else
    info "Spotify already installed — skipping"
fi

# ---------------------------------------------------------------------------
# 12. Python development environment
# ---------------------------------------------------------------------------
step "Setting up Python development environment"

# Install pip and venv
sudo apt-get install -y python3-venv python3-pip

# Create the shared virtual-environments directory
PYTHON_ENVS_DIR="${HOME}/development/python_envs"
mkdir -p "${PYTHON_ENVS_DIR}"
success "Python envs directory ready: ${PYTHON_ENVS_DIR}"

# Detect which shell config file to use
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL}")" == "zsh" ]]; then
    SHELL_RC="${HOME}/.zshrc"
else
    SHELL_RC="${HOME}/.bashrc"
fi

# Insert the helper function only once
if ! grep -q "# >>> venv-helper >>>" "${SHELL_RC}" 2>/dev/null; then
    info "Adding venv helper function to ${SHELL_RC}…"
    cat >> "${SHELL_RC}" <<'SHELL_SNIPPET'

# >>> venv-helper >>>
# Helper function to create and activate Python virtual environments.
# Usage:
#   mkenv <env_name>          — create a new venv and activate it
#   mkenv <env_name> activate — activate an existing venv
PYTHON_ENVS_DIR="${HOME}/development/python_envs"

mkenv() {
    local env_name="${1:-}"
    local action="${2:-create}"

    if [[ -z "${env_name}" ]]; then
        echo "Usage: mkenv <env_name> [activate]"
        echo "Existing environments:"
        ls -1 "${PYTHON_ENVS_DIR}" 2>/dev/null || echo "  (none)"
        return 1
    fi

    local env_path="${PYTHON_ENVS_DIR}/${env_name}"

    if [[ "${action}" == "activate" ]]; then
        if [[ ! -d "${env_path}" ]]; then
            echo "Environment '${env_name}' not found in ${PYTHON_ENVS_DIR}"
            return 1
        fi
        # shellcheck disable=SC1090
        source "${env_path}/bin/activate"
        echo "Activated: ${env_path}"
    else
        if [[ ! -d "${env_path}" ]]; then
            python3 -m venv "${env_path}"
            echo "Created: ${env_path}"
        else
            echo "Environment '${env_name}' already exists — activating."
        fi
        # shellcheck disable=SC1090
        source "${env_path}/bin/activate"
        echo "Activated: ${env_path}"
    fi
}

# Quick alias: list all managed environments
alias lsenvs='ls -1 "${PYTHON_ENVS_DIR}"'
# <<< venv-helper <<<
SHELL_SNIPPET
    success "Venv helper function added to ${SHELL_RC}"
else
    info "Venv helper function already present in ${SHELL_RC} — skipping"
fi

# ---------------------------------------------------------------------------
# 13. Update desktop database
# ---------------------------------------------------------------------------
step "Refreshing application menu"
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "${HOME}/.local/share/applications/" 2>/dev/null || true
fi
success "Application menu refreshed"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║        Post-installation setup complete! 🎉              ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Apps installed to:${NC}  ~/apps/"
echo -e "  ${CYAN}Python envs dir:${NC}   ~/development/python_envs/"
echo -e "  ${CYAN}Shell helper in:${NC}   ${SHELL_RC}"
echo -e "  ${CYAN}Usage:${NC}             mkenv my-project"
echo ""
warn "A reboot is recommended to apply all changes (especially graphics drivers)."
echo ""
