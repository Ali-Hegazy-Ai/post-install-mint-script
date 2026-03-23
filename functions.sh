#!/usr/bin/env bash

init_colors() {
  if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    local ncolors
    ncolors="$(tput colors 2>/dev/null || echo 0)"
    if [[ "${ncolors}" -ge 8 ]]; then
      RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"; BOLD="$(tput bold)"; NC="$(tput sgr0)"
      return
    fi
  fi
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
}

log_info() { printf "%b[INFO]%b %s\n" "${CYAN}" "${NC}" "$*"; }
log_warn() { printf "%b[WARN]%b %s\n" "${YELLOW}" "${NC}" "$*"; }
log_error() { printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$*" >&2; }
log_success() { printf "%b[OK]%b %s\n" "${GREEN}" "${NC}" "$*"; }
log_debug() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    printf "%b[DEBUG]%b %s\n" "${CYAN}" "${NC}" "$*"
  fi
  return 0
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN]"
    printf " %q" "$@"
    printf "\n"
    return 0
  fi
  "$@"
}

run_shell() {
  local cmd="${1}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] bash -c %q\n" "${cmd}"
    return 0
  fi
  bash -c "${cmd}"
}

run_as_target_user() {
  local cmd=("$@")
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] sudo -u %q" "${MINT_POSTINSTALL_USER}"
    printf " %q" "${cmd[@]}"
    printf "\n"
    return 0
  fi
  sudo -u "${MINT_POSTINSTALL_USER}" "${cmd[@]}"
}

ensure_state_file() {
  [[ -n "${STATE_FILE}" ]] || STATE_FILE="${MINT_POSTINSTALL_HOME}/.mint-postinstall-state"
  if [[ ! -f "${STATE_FILE}" ]]; then
    run_cmd touch "${STATE_FILE}"
    [[ "${DRY_RUN}" -eq 1 ]] || run_cmd chown "${MINT_POSTINSTALL_USER}:${MINT_POSTINSTALL_USER}" "${STATE_FILE}"
  fi
}

state_has() {
  local key="${1}"
  [[ -f "${STATE_FILE}" ]] && grep -Fxq "${key}" "${STATE_FILE}"
}

state_mark() {
  local key="${1}"
  state_has "${key}" && return 0
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] state mark: %s\n" "${key}"
    return 0
  fi
  printf "%s\n" "${key}" >> "${STATE_FILE}"
  run_cmd chown "${MINT_POSTINSTALL_USER}:${MINT_POSTINSTALL_USER}" "${STATE_FILE}"
}

confirm_action() {
  local prompt="${1}"
  local default_no="${2:-1}"
  local response
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  if [[ "${default_no}" -eq 1 ]]; then
    read -r -p "${prompt} [y/N] " response
    [[ "${response}" =~ ^[Yy]$ ]]
  else
    read -r -p "${prompt} [Y/n] " response
    [[ ! "${response}" =~ ^[Nn]$ ]]
  fi
}

is_pkg_installed() {
  dpkg -s "${1}" >/dev/null 2>&1
}

load_machine_profile() {
  TOTAL_RAM="$(free -m | awk '/Mem:/ {print $2}')"
  [[ -z "${TOTAL_RAM}" ]] && TOTAL_RAM=0
  if [[ "${TOTAL_RAM}" -lt "${MIN_LOW_RAM_MB}" ]]; then
    log_warn "Detected low RAM (${TOTAL_RAM}MB). Enabling low-end install behavior."
    LOW_END=1
  fi
}

apt_update_once() {
  if [[ "${NO_UPDATE}" -eq 1 ]]; then
    log_warn "Skipping apt update due to --no-update"
    return 0
  fi
  if [[ "${APT_UPDATED}" -eq 1 && "${PENDING_REPO_REFRESH}" -eq 0 ]]; then
    log_debug "apt metadata already refreshed"
    return 0
  fi
  log_info "Refreshing apt package metadata"
  run_cmd apt-get -o Acquire::Retries="${APT_RETRIES}" update -y
  APT_UPDATED=1
  PENDING_REPO_REFRESH=0
}

write_file_if_missing() {
  local path="${1}"
  local content="${2}"
  if [[ -f "${path}" ]] && cmp -s "${path}" <(printf "%s\n" "${content}"); then
    return 0
  fi
  run_shell "printf %q \"${content}\" >/dev/null" >/dev/null 2>&1 || true
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] write %s -> %s\n" "${content}" "${path}"
    return 0
  fi
  printf "%s\n" "${content}" > "${path}"
}

configure_apt_speedups() {
  local translations_conf="/etc/apt/apt.conf.d/99translations"
  local dpkg_conf="/etc/dpkg/dpkg.cfg.d/02apt-speedup"
  write_file_if_missing "${translations_conf}" 'Acquire::Languages "none";'
  write_file_if_missing "${dpkg_conf}" 'force-unsafe-io'
  state_mark "apt_speedups_configured"
}

install_apt_packages() {
  local pkgs=("$@")
  local to_install=()
  local pkg
  for pkg in "${pkgs[@]}"; do
    if is_pkg_installed "${pkg}"; then
      log_debug "Package already installed: ${pkg}"
    else
      to_install+=("${pkg}")
    fi
  done

  if [[ "${#to_install[@]}" -eq 0 ]]; then
    log_info "All requested packages already installed"
    return 0
  fi

  local batch_size="${BATCH_SIZE_DEFAULT}"
  if [[ "${LOW_END}" -eq 1 || "${TOTAL_RAM}" -lt "${MIN_LOW_RAM_MB}" ]]; then
    batch_size="${BATCH_SIZE_LOW_RAM}"
  fi

  local i=0
  local total="${#to_install[@]}"
  while [[ "${i}" -lt "${total}" ]]; do
    local batch=("${to_install[@]:i:batch_size}")
    log_info "Installing package batch (${i}/${total}): ${batch[*]}"
    if [[ "${NO_INSTALL_RECOMMENDS}" -eq 1 ]]; then
      run_cmd apt-get -o Acquire::Retries="${APT_RETRIES}" install -y --no-install-recommends "${batch[@]}"
    else
      run_cmd apt-get -o Acquire::Retries="${APT_RETRIES}" install -y "${batch[@]}"
    fi
    i=$((i + batch_size))
  done
}

ensure_gpg_key() {
  local url="${1}"
  local keyring="${2}"
  if [[ -s "${keyring}" ]]; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  run_cmd curl -fL --retry 3 --max-redirs 5 --proto '=https' --proto-redir '=https' --tlsv1.2 -o "${tmp}" "${url}"
  run_cmd gpg --dearmor -o "${keyring}" "${tmp}"
  run_cmd chmod 0644 "${keyring}"
  run_cmd rm -f "${tmp}"
}

ensure_repo_line() {
  local file="${1}"
  local line="${2}"
  if [[ -f "${file}" ]] && grep -Fxq "${line}" "${file}"; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] add repo line to %s: %s\n" "${file}" "${line}"
  else
    printf "%s\n" "${line}" > "${file}"
  fi
  PENDING_REPO_REFRESH=1
}

create_desktop_entry() {
  local name="${1}"
  local exec_path="${2}"
  local icon_path="${3}"
  local categories="${4:-Application}"
  local desktop_dir="${MINT_POSTINSTALL_HOME}/.local/share/applications"
  local desktop_file="${desktop_dir}/${name,,}.desktop"

  run_cmd mkdir -p "${desktop_dir}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] create desktop entry: %s\n" "${desktop_file}"
    return 0
  fi

  cat > "${desktop_file}" <<EOT
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Exec=${exec_path}
Icon=${icon_path}
Categories=${categories}
Terminal=false
StartupNotify=true
EOT
  run_cmd chmod +x "${desktop_file}"
  run_cmd chown "${MINT_POSTINSTALL_USER}:${MINT_POSTINSTALL_USER}" "${desktop_file}"
}

maybe_wait_jobs() {
  local max="${1:-${MAX_JOBS}}"
  if [[ "${LOW_END}" -eq 1 ]]; then
    max=1
  fi
  while [[ "$(jobs -rp | wc -l)" -ge "${max}" ]]; do
    wait -n 2>/dev/null || wait
  done
}

run_background_limited() {
  local max="${1:-${MAX_JOBS}}"
  shift
  maybe_wait_jobs "${max}"
  "$@" &
}

set_git_identity_defaults() {
  local gitconfig="${MINT_POSTINSTALL_HOME}/.gitconfig"
  if [[ -f "${gitconfig}" ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf "[DRY-RUN] create %s\n" "${gitconfig}"
    return 0
  fi
  cat > "${gitconfig}" <<'EOT'
[init]
  defaultBranch = main
[pull]
  rebase = false
EOT
  run_cmd chown "${MINT_POSTINSTALL_USER}:${MINT_POSTINSTALL_USER}" "${gitconfig}"
}
