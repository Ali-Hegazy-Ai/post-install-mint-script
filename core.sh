#!/usr/bin/env bash

show_help() {
  cat <<USAGE
Usage: post-install.sh [OPTIONS]

Modes:
  --full         Install full setup (default)
  --dev          Development tools only
  --minimal      Essentials only
  --apps         GUI apps only

Performance:
  --low-end      Optimize for low-end systems
  --no-update    Skip apt-get update
  --with-recommends  Use apt install with recommended packages
  --dry-run      Print actions without executing
  --verbose      Verbose logging

Feature toggles:
  --docker | --no-docker
  --node | --no-node
  --python | --no-python
  --flatpak | --no-flatpak
  --tweaks | --no-tweaks
  --git-ssh | --no-git-ssh

Other:
  --help         Show this help
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full) MODE="full" ;;
      --dev) MODE="dev" ;;
      --minimal) MODE="minimal" ;;
      --apps) MODE="apps" ;;
      --dry-run) DRY_RUN=1 ;;
      --verbose) VERBOSE=1 ;;
      --low-end) LOW_END=1 ;;
      --no-update) NO_UPDATE=1 ;;
      --with-recommends) NO_INSTALL_RECOMMENDS=0 ;;
      --docker) ENABLE_DOCKER=1 ;;
      --no-docker) ENABLE_DOCKER=0 ;;
      --node) ENABLE_NODE=1 ;;
      --no-node) ENABLE_NODE=0 ;;
      --python) ENABLE_PYTHON=1 ;;
      --no-python) ENABLE_PYTHON=0 ;;
      --flatpak) ENABLE_FLATPAK=1; EXPLICIT_FLATPAK=1 ;;
      --no-flatpak) ENABLE_FLATPAK=0 ;;
      --tweaks) ENABLE_TWEAKS=1 ;;
      --no-tweaks) ENABLE_TWEAKS=0 ;;
      --git-ssh) ENABLE_GIT_SSH=1 ;;
      --no-git-ssh) ENABLE_GIT_SSH=0 ;;
      --help|-h) show_help; exit 0 ;;
      *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
  done
}

apply_mode_defaults() {
  case "${MODE}" in
    full)
      ENABLE_BASE=1; ENABLE_DEV=1; ENABLE_APPS=1; ENABLE_DOCKER=1; ENABLE_NODE=1; ENABLE_PYTHON=1; ENABLE_FLATPAK=1; ENABLE_TWEAKS=1; ENABLE_GIT_SSH=1
      ;;
    dev)
      ENABLE_BASE=1; ENABLE_DEV=1; ENABLE_APPS=0; ENABLE_DOCKER=1; ENABLE_NODE=1; ENABLE_PYTHON=1; ENABLE_FLATPAK=0; ENABLE_TWEAKS=0; ENABLE_GIT_SSH=1
      ;;
    minimal)
      ENABLE_BASE=1; ENABLE_DEV=0; ENABLE_APPS=0; ENABLE_DOCKER=0; ENABLE_NODE=0; ENABLE_PYTHON=0; ENABLE_FLATPAK=0; ENABLE_TWEAKS=0; ENABLE_GIT_SSH=1
      ;;
    apps)
      ENABLE_BASE=0; ENABLE_DEV=0; ENABLE_APPS=1; ENABLE_DOCKER=0; ENABLE_NODE=0; ENABLE_PYTHON=0; ENABLE_FLATPAK=0; ENABLE_TWEAKS=0; ENABLE_GIT_SSH=0
      ;;
    *) log_error "Unsupported mode: ${MODE}"; exit 1 ;;
  esac

  if [[ "${LOW_END}" -eq 1 ]]; then
    ENABLE_TWEAKS=0
    if [[ "${EXPLICIT_FLATPAK}" -eq 0 ]]; then
      ENABLE_FLATPAK=0
    fi
  fi
}

maybe_reexec_as_root() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    MINT_POSTINSTALL_USER="${USER}"
    MINT_POSTINSTALL_HOME="${HOME}"
    return 0
  fi

  if [[ "${EUID}" -ne 0 ]]; then
    local script_path
    script_path="$(readlink -f "$0")"
    MINT_POSTINSTALL_USER="${USER}" MINT_POSTINSTALL_HOME="${HOME}" exec sudo --preserve-env=MINT_POSTINSTALL_USER,MINT_POSTINSTALL_HOME bash "${script_path}" "$@"
  fi

  if [[ -z "${MINT_POSTINSTALL_USER}" ]]; then
    MINT_POSTINSTALL_USER="${SUDO_USER:-root}"
  fi
  if [[ -z "${MINT_POSTINSTALL_HOME}" ]]; then
    MINT_POSTINSTALL_HOME="$(getent passwd "${MINT_POSTINSTALL_USER}" | cut -d: -f6)"
  fi
  [[ -z "${MINT_POSTINSTALL_HOME}" ]] && MINT_POSTINSTALL_HOME="/root"
}

prepare_context() {
  init_colors
  log_info "Starting post-install with mode: ${MODE}"

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ -z "${UBUNTU_CODENAME:-}" ]]; then
    log_error "UBUNTU_CODENAME is not set in /etc/os-release."
    exit 1
  fi

  STATE_FILE="${MINT_POSTINSTALL_HOME}/.mint-postinstall-state"
  ensure_state_file
  load_machine_profile
  apply_mode_defaults
}

filter_low_end_packages() {
  local input=("$@")
  if [[ "${LOW_END}" -eq 0 ]]; then
    printf '%s\n' "${input[@]}"
    return 0
  fi

  local pkg
  for pkg in "${input[@]}"; do
    local skip=0
    local heavy
    for heavy in "${LOW_END_SKIP_PACKAGES[@]}"; do
      if [[ "${pkg}" == "${heavy}" ]]; then
        skip=1
        break
      fi
    done
    [[ "${skip}" -eq 0 ]] && printf '%s\n' "${pkg}"
  done
}

setup_system_basics() {
  log_info "Configuring apt low-end optimizations"
  configure_apt_speedups
  apt_update_once
}

install_base() {
  local filtered
  mapfile -t filtered < <(filter_low_end_packages "${BASE_PACKAGES[@]}")
  install_apt_packages "${filtered[@]}"
}

install_dev() {
  install_apt_packages "${DEV_PACKAGES[@]}"
}

install_apps() {
  local filtered
  mapfile -t filtered < <(filter_low_end_packages "${APPS_PACKAGES[@]}")
  install_apt_packages "${filtered[@]}"
}

configure_docker_repo() {
  ensure_gpg_key "https://download.docker.com/linux/ubuntu/gpg" "/usr/share/keyrings/docker-archive-keyring.gpg"
  ensure_repo_line "/etc/apt/sources.list.d/docker.list" "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed"
  else
    configure_docker_repo
    apt_update_once
    install_apt_packages "${DOCKER_PACKAGES[@]}"
  fi
  if ! id -nG "${MINT_POSTINSTALL_USER}" | grep -qw docker; then
    run_cmd usermod -aG docker "${MINT_POSTINSTALL_USER}"
  fi
}

install_node_nvm() {
  local nvm_dir="${MINT_POSTINSTALL_HOME}/.nvm"
  if [[ ! -d "${nvm_dir}" ]]; then
    if ! run_as_target_user git clone https://github.com/nvm-sh/nvm.git "${nvm_dir}"; then
      log_error "Failed to clone nvm repository into ${nvm_dir}"
      return 1
    fi
    if ! run_as_target_user git -C "${nvm_dir}" checkout "${NVM_VERSION}"; then
      log_error "Failed to checkout nvm version ${NVM_VERSION}"
      return 1
    fi
  fi
  run_as_target_user bash -lc "export NVM_DIR='${nvm_dir}'; source '${nvm_dir}/nvm.sh'; nvm install --lts; nvm alias default 'lts/*'"
}

setup_python_dev() {
  install_apt_packages "${PYTHON_PACKAGES[@]}"
  run_as_target_user mkdir -p "${MINT_POSTINSTALL_HOME}/development/python_envs"
  local rc_file
  for rc_file in "${MINT_POSTINSTALL_HOME}/.bashrc" "${MINT_POSTINSTALL_HOME}/.zshrc"; do
    [[ -f "${rc_file}" ]] || continue
    if ! grep -q "# >>> venv-helper >>>" "${rc_file}" 2>/dev/null; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf "[DRY-RUN] append venv helper to %s\n" "${rc_file}"
      else
        cat >> "${rc_file}" <<'SHELL_SNIPPET'

# >>> venv-helper >>>
PYTHON_ENVS_DIR="${HOME}/development/python_envs"
mkenv() {
  local env_name="${1:-}"
  local action="${2:-create}"
  if [[ -z "${env_name}" ]]; then
    echo "Usage: mkenv <env_name> [activate]"
    return 1
  fi
  local env_path="${PYTHON_ENVS_DIR}/${env_name}"
  if [[ "${action}" == "activate" ]]; then
    [[ -d "${env_path}" ]] || { echo "Environment not found: ${env_name}"; return 1; }
  else
    [[ -d "${env_path}" ]] || python3 -m venv "${env_path}"
  fi
  # shellcheck disable=SC1090
  source "${env_path}/bin/activate"
}
alias lsenvs='ls -1 "${PYTHON_ENVS_DIR}"'
# <<< venv-helper <<<
SHELL_SNIPPET
        run_cmd chown "${MINT_POSTINSTALL_USER}:${MINT_POSTINSTALL_USER}" "${rc_file}"
      fi
    fi
  done
}

setup_flatpak() {
  install_apt_packages "${FLATPAK_PACKAGES[@]}"
  local remotes_tmp
  remotes_tmp="$(mktemp)"
  if ! run_as_target_user flatpak remotes --columns=name >"${remotes_tmp}" 2>/dev/null; then
    run_cmd rm -f "${remotes_tmp}"
    return 0
  fi
  if ! grep -qx flathub "${remotes_tmp}"; then
    run_as_target_user flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  run_cmd rm -f "${remotes_tmp}"
}

setup_tweaks() {
  install_apt_packages "${TWEAK_PACKAGES[@]}"
  if command -v gsettings >/dev/null 2>&1; then
    run_as_target_user gsettings set org.cinnamon.desktop.effects false || true
  fi
}

setup_git_ssh() {
  install_apt_packages "${GIT_SSH_PACKAGES[@]}"
  set_git_identity_defaults
  local ssh_key="${MINT_POSTINSTALL_HOME}/.ssh/id_${SSH_KEY_TYPE}"
  if [[ ! -f "${ssh_key}" ]]; then
    if confirm_action "No SSH key found. Generate ${SSH_KEY_TYPE} key for ${MINT_POSTINSTALL_USER}?" 1; then
      run_as_target_user mkdir -p "${MINT_POSTINSTALL_HOME}/.ssh"
      run_as_target_user ssh-keygen -t "${SSH_KEY_TYPE}" -N "" -C "${MINT_POSTINSTALL_USER}@$(hostname)" -f "${ssh_key}"
      log_success "SSH key generated: ${ssh_key}"
    fi
  fi
}

cleanup_system() {
  run_cmd apt-get autoremove -y
  run_cmd apt-get clean
}

print_summary() {
  log_success "Post-installation flow completed"
  printf "\nSummary:\n"
  printf "  - Mode: %s\n" "${MODE}"
  printf "  - Dry run: %s\n" "$( [[ "${DRY_RUN}" -eq 1 ]] && echo yes || echo no )"
  printf "  - State file: %s\n" "${STATE_FILE}"
  printf "  - Target user: %s\n" "${MINT_POSTINSTALL_USER}"
  printf "  - Target home: %s\n" "${MINT_POSTINSTALL_HOME}"
  printf "\nNote: Docker group changes require logout/login.\n"
}

main() {
  parse_args "$@"
  maybe_reexec_as_root "$@"
  prepare_context

  local -a labels=()
  local -a funcs=()

  labels+=("System preparation"); funcs+=("setup_system_basics")
  if [[ "${ENABLE_BASE}" -eq 1 ]]; then labels+=("Base packages"); funcs+=("install_base"); fi
  if [[ "${ENABLE_DEV}" -eq 1 ]]; then labels+=("Development packages"); funcs+=("install_dev"); fi
  if [[ "${ENABLE_APPS}" -eq 1 ]]; then labels+=("GUI apps packages"); funcs+=("install_apps"); fi
  if [[ "${ENABLE_DOCKER}" -eq 1 ]]; then labels+=("Docker module"); funcs+=("install_docker"); fi
  if [[ "${ENABLE_NODE}" -eq 1 ]]; then labels+=("Node.js (nvm) module"); funcs+=("install_node_nvm"); fi
  if [[ "${ENABLE_PYTHON}" -eq 1 ]]; then labels+=("Python development module"); funcs+=("setup_python_dev"); fi
  if [[ "${ENABLE_FLATPAK}" -eq 1 ]]; then labels+=("Flatpak module"); funcs+=("setup_flatpak"); fi
  if [[ "${ENABLE_TWEAKS}" -eq 1 ]]; then labels+=("Desktop tweaks module"); funcs+=("setup_tweaks"); fi
  if [[ "${ENABLE_GIT_SSH}" -eq 1 ]]; then labels+=("Git + SSH module"); funcs+=("setup_git_ssh"); fi
  if [[ "${ENABLE_CLEANUP}" -eq 1 ]]; then labels+=("Cleanup"); funcs+=("cleanup_system"); fi

  local total="${#funcs[@]}"
  local i
  for ((i=0; i<total; i++)); do
    printf "\n%s[%d/%d]%s %s\n" "${BOLD}${CYAN}" "$((i+1))" "${total}" "${NC}" "${labels[i]}"
    "${funcs[i]}"
    state_mark "step_${funcs[i]}"
    log_success "Completed: ${labels[i]}"
  done

  if command -v update-desktop-database >/dev/null 2>&1; then
    run_as_target_user update-desktop-database "${MINT_POSTINSTALL_HOME}/.local/share/applications/" || true
  fi

  print_summary
}
