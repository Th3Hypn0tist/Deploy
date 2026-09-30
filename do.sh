#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ROOT_DIR}/targets"

if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "ERROR: missing target directory: ${TARGET_DIR}" >&2
    exit 1
fi

mapfile -t TARGETS < <(
    find "${TARGET_DIR}" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort
)

if (( ${#TARGETS[@]} == 0 )); then
    echo "ERROR: no deployment targets found in ${TARGET_DIR}" >&2
    exit 1
fi

preflight_shell_files() {
    local file

    while IFS= read -r -d '' file; do
        if LC_ALL=C grep -q $'\r' "${file}"; then
            echo "ERROR: CRLF detected in shell file: ${file}" >&2
            return 1
        fi

        if ! bash -n "${file}"; then
            echo "ERROR: shell syntax check failed: ${file}" >&2
            return 1
        fi
    done < <(
        find "${ROOT_DIR}/lib" "${TARGET_DIR}" \
            -maxdepth 1 -type f -name '*.sh' -print0
    )
}

preflight_shell_files

run_target() {
    local index="$1"
    local action="${2:-interactive}"

    if ! [[ "${index}" =~ ^[0-9]+$ ]] \
        || (( index < 1 || index > ${#TARGETS[@]} )); then
        echo "ERROR: invalid target number: ${index}" >&2
        return 2
    fi

    local file="${TARGETS[$((index - 1))]}"

    echo
    echo "================================================================"
    echo "TARGET: ${file}"
    echo "ACTION: ${action}"
    echo "================================================================"

    DEPLOY_ACTION="${action}" bash "${TARGET_DIR}/${file}"
}

run_all_targets() {
    local action="$1"
    local i

    for i in "${!TARGETS[@]}"; do
        run_target "$((i + 1))" "${action}"
    done
}

select_target_for_migration() {
    echo
    echo "MIGRATION TARGET"
    echo

    local i
    for i in "${!TARGETS[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${TARGETS[$i]%.sh}"
    done

    echo
    echo "  0) Cancel"
    echo

    local selected
    read -r -p "Select target: " selected

    if [[ "${selected}" == "0" ]]; then
        echo "Cancelled."
        return 0
    fi

    run_target "${selected}" "migration"
}

show_menu() {
    echo
    echo "DEPLOY"
    echo

    local i
    for i in "${!TARGETS[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${TARGETS[$i]%.sh}"
    done

    echo
    echo "  i) Init"
    echo "  g) Migration"
    echo "  m) Multi"
    echo "  a) All"
    echo "  q) Quit"
    echo
}

show_menu
read -r -p "Select: " choice

case "${choice}" in
    q|Q)
        exit 0
        ;;
    i|I)
        echo
        echo "INIT"
        echo "Deploy all targets and initialize all configured schemas."
        echo
        read -r -p "Continue? [y/N]: " answer
        case "${answer}" in
            y|Y|yes|YES|Yes)
                echo
                echo "PHASE 1/3: CODE DEPLOY"
                run_all_targets "all"

                echo
                echo "PHASE 2/3: DATABASE INIT PREFLIGHT"
                run_all_targets "validate-init"

                echo
                echo "PHASE 3/3: DATABASE INIT"
                run_all_targets "init-db"
                ;;
            *)
                echo "Cancelled."
                ;;
        esac
        ;;
    g|G)
        select_target_for_migration
        ;;
    a|A)
        run_all_targets "all"
        ;;
    m|M)
        read -r -p "Targets (numbers separated by spaces or commas): " multi
        multi="${multi//,/ }"
        read -r -a selected <<< "${multi}"

        if (( ${#selected[@]} == 0 )); then
            echo "ERROR: no targets selected" >&2
            exit 2
        fi

        for item in "${selected[@]}"; do
            run_target "${item}" "interactive"
        done
        ;;
    *)
        run_target "${choice}" "interactive"
        ;;
esac
