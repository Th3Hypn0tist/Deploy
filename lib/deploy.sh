#!/usr/bin/env bash

DEPLOY_UNIT_NAMES=()
DEPLOY_UNIT_SOURCES=()
DEPLOY_UNIT_TARGETS=()
DEPLOY_UNIT_EXCLUDES=()
DEPLOY_UNIT_PRESERVES=()
DEPLOY_SELECTED_UNITS=()

deploy_unit_add() {
    local name="$1"
    local source="$2"
    local target="$3"
    local excludes="${4:-}"
    local preserves="${5:-}"

    [[ -n "${name}" ]] || {
        echo "ERROR: deployment unit name is empty" >&2
        return 1
    }

    [[ -n "${source}" ]] || {
        echo "ERROR: deployment unit source is empty: ${name}" >&2
        return 1
    }

    [[ "${source}" != /* && "${source}" != *".."* ]] || {
        echo "ERROR: deployment source must be repo-relative: ${source}" >&2
        return 1
    }

    [[ "${target}" == /* ]] || {
        echo "ERROR: deployment target must be absolute: ${target}" >&2
        return 1
    }

    DEPLOY_UNIT_NAMES+=("${name}")
    DEPLOY_UNIT_SOURCES+=("${source}")
    DEPLOY_UNIT_TARGETS+=("${target}")
    DEPLOY_UNIT_EXCLUDES+=("${excludes}")
    DEPLOY_UNIT_PRESERVES+=("${preserves}")
}

_deploy_validate_rule() {
    local rule="$1"
    local kind="$2"

    [[ -n "${rule}" ]] || return 0

    [[ "${rule}" != /* && "${rule}" != *".."* && "${rule}" != *$'\n'* ]] || {
        echo "ERROR: unsafe ${kind} rule: ${rule}" >&2
        return 1
    }
}

_deploy_remove_stage_rule() {
    local stage="$1"
    local rule="$2"

    _deploy_validate_rule "${rule}" "exclude/preserve"

    local matches=()
    shopt -s nullglob dotglob
    matches=( "${stage}"/${rule} )
    shopt -u nullglob dotglob

    if (( ${#matches[@]} > 0 )); then
        rm -rf -- "${matches[@]}"
    fi
}

_deploy_make_stage() {
    local source="$1"
    local excludes="$2"
    local preserves="$3"

    DEPLOY_STAGE_DIR="$(mktemp -d)"
    cp -a "${source}/." "${DEPLOY_STAGE_DIR}/"

    local rule
    IFS=';' read -r -a _exclude_array <<< "${excludes}"
    for rule in "${_exclude_array[@]}"; do
        [[ -n "${rule}" ]] || continue
        _deploy_remove_stage_rule "${DEPLOY_STAGE_DIR}" "${rule}"
    done

    IFS=';' read -r -a _preserve_array <<< "${preserves}"
    for rule in "${_preserve_array[@]}"; do
        [[ -n "${rule}" ]] || continue
        _deploy_remove_stage_rule "${DEPLOY_STAGE_DIR}" "${rule}"
    done
}

_deploy_run_unit() {
    local index="$1"

    local name="${DEPLOY_UNIT_NAMES[$index]}"
    local source_rel="${DEPLOY_UNIT_SOURCES[$index]}"
    local target="${DEPLOY_UNIT_TARGETS[$index]}"
    local excludes="${DEPLOY_UNIT_EXCLUDES[$index]}"
    local preserves="${DEPLOY_UNIT_PRESERVES[$index]}"
    local source="${LOCAL_REPO}/${source_rel}"

    [[ -d "${source}" ]] || {
        echo "ERROR: deployment source directory missing: ${source}" >&2
        return 1
    }

    echo
    echo "----------------------------------------------------------------"
    echo "Deploy:    ${name}"
    echo "Target:    ${TARGET_NAME}"
    echo "Domain:    ${DOMAIN}"
    echo "Transport: ${TRANSPORT}"
    echo "Branch:    ${SELECTED_BRANCH}"
    echo "Source:    ${source}/"
    echo "Remote:    ${TRANSPORT_REMOTE_ROOT%/}${target}"
    [[ -n "${excludes}" ]] && echo "Exclude:   ${excludes}"
    [[ -n "${preserves}" ]] && echo "Preserve:  ${preserves}"
    echo "----------------------------------------------------------------"

    if [[ "${DEPLOY_ACTION:-interactive}" != "init-code" ]]; then
        if transport_remote_exists "${target}"; then
            if ! confirm_yes_no "Target exists. Overwrite?" "${DEPLOY_OVERWRITE_DEFAULT}"; then
                echo "Skipped: ${name}"
                return 0
            fi
        else
            exists_rc=$?
            if (( exists_rc == 2 )); then
                return 1
            fi
        fi
    fi

    _deploy_make_stage "${source}" "${excludes}" "${preserves}"
    trap 'rm -rf -- "${DEPLOY_STAGE_DIR:-}"' RETURN

    transport_sync_tree "${DEPLOY_STAGE_DIR}" "${target}" "${preserves}"

    rm -rf -- "${DEPLOY_STAGE_DIR}"
    DEPLOY_STAGE_DIR=""
    trap - RETURN

    echo "Complete: ${name}"
}

_deploy_select_all() {
    DEPLOY_SELECTED_UNITS=()

    local i
    for i in "${!DEPLOY_UNIT_NAMES[@]}"; do
        DEPLOY_SELECTED_UNITS+=("${i}")
    done
}

_deploy_run_selected() {
    local i
    for i in "${DEPLOY_SELECTED_UNITS[@]}"; do
        _deploy_run_unit "${i}"
    done
}

deploy_target_main() {
    : "${DOMAIN:?target missing DOMAIN}"
    : "${TARGET_NAME:?target missing TARGET_NAME}"
    : "${TRANSPORT:?target missing TRANSPORT}"
    : "${REPO_URL:?target missing REPO_URL}"
    : "${LOCAL_REPO:?target missing LOCAL_REPO}"

    case "${TRANSPORT}" in
        ftp|scp) ;;
        *)
            echo "ERROR: TRANSPORT must be ftp or scp" >&2
            return 1
            ;;
    esac

    local deploy_root
    deploy_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

    # Existing deploy.json contract. The package never rewrites this file.
    config_load_transport \
        "${deploy_root}/deploy.json" \
        "${DOMAIN}" \
        "${TRANSPORT}"

    repo_ensure "${REPO_URL}" "${LOCAL_REPO}"

    local action="${DEPLOY_ACTION:-interactive}"

    case "${action}" in
        validate-init|init-db)
            SELECTED_BRANCH="$(git -C "${LOCAL_REPO}" branch --show-current || true)"
            [[ -n "${SELECTED_BRANCH}" ]] || {
                echo "ERROR: ${TARGET_NAME} repo is on a detached HEAD; Init requires a selected branch" >&2
                return 1
            }
            ;;
        *)
            branch_select "${LOCAL_REPO}"
            repo_use_branch "${LOCAL_REPO}" "${SELECTED_BRANCH}"
            ;;
    esac

    DEPLOY_UNIT_NAMES=()
    DEPLOY_UNIT_SOURCES=()
    DEPLOY_UNIT_TARGETS=()
    DEPLOY_UNIT_EXCLUDES=()
    DEPLOY_UNIT_PRESERVES=()
    DEPLOY_SELECTED_UNITS=()
    schema_reset

    define_units

    if declare -F define_schema >/dev/null 2>&1; then
        define_schema
    fi

    case "${action}" in
        interactive)
            unit_select
            _deploy_run_selected
            ;;
        all)
            _deploy_select_all
            _deploy_run_selected
            ;;
        validate-init)
            # Root Init phase 2: no deploy, no DB mutation.
            schema_validate_init_all
            ;;
        init-db)
            # Root Init phase 3: DB mutation only, after every target passed preflight.
            schema_init_all
            ;;
        migration)
            # Explicit DB-only operation. Never deploy code here.
            schema_migration_menu
            ;;
        *)
            echo "ERROR: unsupported deploy action: ${action}" >&2
            return 2
            ;;
    esac

    echo
    echo "${TARGET_NAME} ${action} complete."
    echo "Branch: ${SELECTED_BRANCH}"
}
