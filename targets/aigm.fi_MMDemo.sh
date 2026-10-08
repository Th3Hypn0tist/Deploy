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

DOMAIN="aigm.fi"
TARGET_NAME="MMDemo"
TRANSPORT="ftp"

REPO_URL="https://github.com/Th3Hypn0tist/DWH.git"
LOCAL_REPO="${HOME}/AIGM/DWH"

define_units() {
    deploy_unit_add \
        "DWH PHP" \
        "php" \
        "/test/app/dwh" \
        "README.md;tests;tests/**"

    deploy_unit_add \
        "MMDemo app" \
        "demo/app/mmdemo" \
        "/test/app/mmdemo"

    deploy_unit_add \
        "MMDemo" \
        "demo/mmdemo" \
        "/test/mmdemo"
}

define_schema() {
    :
}

deploy_target_main
