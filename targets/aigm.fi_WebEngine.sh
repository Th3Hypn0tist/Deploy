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
TARGET_NAME="WebEngine"
TRANSPORT="ftp"

REPO_URL="https://github.com/Th3Hypn0tist/WebEngine.git"
LOCAL_REPO="${HOME}/AIGM/WebEngine"

define_units() {
    deploy_unit_add \
        "WebEngine" \
        "." \
        "$(site_target "/lib/webengine")" \
        ".git;.git/**;Contracts;Contracts/**;tests;tests/**;README.md;package.json"
}

deploy_target_main
