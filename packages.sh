#!/usr/bin/env bash

declare -a BASE_PACKAGES=(
  curl wget jq ca-certificates gnupg lsb-release
  apt-transport-https software-properties-common
  mint-meta-codecs ubuntu-restricted-extras libavcodec-extra
  timeshift gnome-disk-utility gnome-terminal btop vlc
)

declare -a DEV_PACKAGES=(
  git build-essential cmake gdb postgresql postgresql-contrib
)

declare -a OPTIONAL_PACKAGES=()

declare -a PYTHON_PACKAGES=(
  python3-venv python3-pip
)

declare -a APPS_PACKAGES=(
  gh code spotify-client
)

declare -a DOCKER_PACKAGES=(
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
)

declare -a FLATPAK_PACKAGES=(flatpak)
declare -a TWEAK_PACKAGES=(gnome-tweaks)
declare -a GIT_SSH_PACKAGES=(git openssh-client)

declare -a LOW_END_SKIP_PACKAGES=(code spotify-client)
