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
TARGET_NAME="LMTS"
TRANSPORT="ftp"

REPO_URL="https://github.com/Th3Hypn0tist/LMTS.git"
LOCAL_REPO="${HOME}/AIGM/LMTS"

define_units() {
    deploy_unit_add \
        "Benchmark" \
        "php/visualizer" \
        "/benchmark"

    deploy_unit_add \
        "Reporting" \
        "php" \
        "/lmts-report" \
        "visualizer;visualizer/**" \
        "config.php"
}

define_schema() {
    schema_component_add \
        "LMTS" \
        "schema/init.sql" \
        "schema/migrations" \
        "/lmts-report" \
        "config.php"
}

deploy_target_main
