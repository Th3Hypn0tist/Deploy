#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "${TARGET_DIR}/../lib/config.sh"
source "${TARGET_DIR}/../lib/ui.sh"
source "${TARGET_DIR}/../lib/repo.sh"
source "${TARGET_DIR}/../lib/b-selectah.sh"
source "${TARGET_DIR}/../lib/unit-selectah.sh"
source "${TARGET_DIR}/../lib/transport.sh"
source "${TARGET_DIR}/../lib/schema.sh"
source "${TARGET_DIR}/../lib/deploy.sh"
source "${TARGET_DIR}/../lib/site-root.sh"

DOMAIN="aigm.fi"
TARGET_NAME="Style"
TRANSPORT="ftp"

REPO_URL="https://github.com/Th3Hypn0tist/Style.git"
LOCAL_REPO="${HOME}/AIGM/Style"

define_units() {
    deploy_unit_add \
        "Style" \
        "." \
        "$(site_target "/style")" \
        ".git;.git/**;Contracts;Contracts/**;README.md"
}

deploy_target_main
