#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/packages.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/functions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/core.sh"

main "$@"
