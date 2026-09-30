#!/usr/bin/env bash

_transport_validate_remote_path() {
    local path="$1"

    [[ "${path}" == /* ]] || {
        echo "ERROR: remote path must be absolute: ${path}" >&2
        return 1
    }

    [[ "${path}" != "/" ]] || {
        echo "ERROR: refusing deployment target '/'" >&2
        return 1
    }

    [[ "${path}" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
        echo "ERROR: unsupported characters in remote path: ${path}" >&2
        return 1
    }

    [[ "${path}" != *"/../"* && "${path}" != */.. && "${path}" != *"/./"* ]] || {
        echo "ERROR: unsafe remote path: ${path}" >&2
        return 1
    }
}

_transport_validate_remote_name() {
    local name="$1"

    [[ -n "${name}" ]] || {
        echo "ERROR: remote filename is empty" >&2
        return 1
    }

    [[ "${name}" != */* && "${name}" != *".."* ]] || {
        echo "ERROR: unsafe remote filename: ${name}" >&2
        return 1
    }

    [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "ERROR: unsupported characters in remote filename: ${name}" >&2
        return 1
    }
}

_transport_join_remote() {
    local root="${TRANSPORT_REMOTE_ROOT}"
    local target="$1"

    [[ "${root}" == /* ]] || {
        echo "ERROR: transport remote_root must be absolute: ${root}" >&2
        return 1
    }

    root="${root%/}"
    [[ -z "${root}" ]] && root=""

    target="/${target#/}"
    RESOLVED_REMOTE_PATH="${root}${target}"

    _transport_validate_remote_path "${RESOLVED_REMOTE_PATH}"
}

_transport_build_ssh() {
    SSH_CMD=(ssh -p "${TRANSPORT_PORT}")
    SCP_CMD=(scp -P "${TRANSPORT_PORT}")

    case "${TRANSPORT_AUTH}" in
        password)
            command -v sshpass >/dev/null 2>&1 || {
                echo "ERROR: sshpass is required for SCP password authentication" >&2
                return 1
            }
            SSH_CMD=(sshpass -p "${TRANSPORT_PASSWORD}" "${SSH_CMD[@]}")
            SCP_CMD=(sshpass -p "${TRANSPORT_PASSWORD}" "${SCP_CMD[@]}")
            ;;
        key)
            [[ -f "${TRANSPORT_IDENTITY_FILE}" ]] || {
                echo "ERROR: SCP identity file not found: ${TRANSPORT_IDENTITY_FILE}" >&2
                return 1
            }
            SSH_CMD+=(-i "${TRANSPORT_IDENTITY_FILE}" -o BatchMode=yes)
            SCP_CMD+=(-i "${TRANSPORT_IDENTITY_FILE}")
            ;;
        agent)
            SSH_CMD+=(-o BatchMode=yes)
            ;;
        *)
            echo "ERROR: unsupported SCP auth mode: ${TRANSPORT_AUTH}" >&2
            return 1
            ;;
    esac
}

_transport_shell_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

_transport_ftp_script_header() {
    local host="${TRANSPORT_HOST//\\/\\\\}"
    host="${host//\"/\\\"}"

    local user="${TRANSPORT_USER//\\/\\\\}"
    user="${user//\"/\\\"}"

    local pass="${TRANSPORT_PASSWORD//\\/\\\\}"
    pass="${pass//\"/\\\"}"

    cat <<EOF
set ftp:ssl-allow no
set net:max-retries 2
set net:timeout 15
set cmd:fail-exit yes
open -p "${TRANSPORT_PORT}" -u "${user}","${pass}" "ftp://${host}"
EOF
}

transport_remote_exists() {
    local target="$1"

    _transport_join_remote "${target}"
    local remote="${RESOLVED_REMOTE_PATH}"

    case "${TRANSPORT}" in
        ftp)
            command -v lftp >/dev/null 2>&1 || {
                echo "ERROR: lftp is required for FTP deployments" >&2
                return 2
            }

            {
                _transport_ftp_script_header
                printf 'cls -d "%s"\n' "${remote//\"/\\\"}"
                printf 'bye\n'
            } | lftp >/dev/null 2>&1
            ;;
        scp)
            command -v ssh >/dev/null 2>&1 || {
                echo "ERROR: ssh is required for SCP deployments" >&2
                return 2
            }

            _transport_build_ssh
            local quoted
            quoted="$(_transport_shell_quote "${remote}")"

            "${SSH_CMD[@]}" \
                "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
                "test -e ${quoted}"
            ;;
        *)
            echo "ERROR: unsupported transport: ${TRANSPORT}" >&2
            return 2
            ;;
    esac
}

transport_list_remote() {
    local target="$1"

    _transport_join_remote "${target}"
    local remote="${RESOLVED_REMOTE_PATH}"

    case "${TRANSPORT}" in
        ftp)
            command -v lftp >/dev/null 2>&1 || {
                echo "ERROR: lftp is required for FTP deployments" >&2
                return 1
            }

            {
                _transport_ftp_script_header
                printf 'cls -la "%s"\n' "${remote//\"/\\\"}"
                printf 'bye\n'
            } | lftp
            ;;
        scp)
            command -v ssh >/dev/null 2>&1 || {
                echo "ERROR: ssh is required for SCP deployments" >&2
                return 1
            }

            _transport_build_ssh
            local quoted
            quoted="$(_transport_shell_quote "${remote}")"

            "${SSH_CMD[@]}" \
                "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
                "ls -la ${quoted}"
            ;;
        *)
            echo "ERROR: unsupported transport: ${TRANSPORT}" >&2
            return 1
            ;;
    esac
}

transport_sync_tree() {
    local stage_dir="$1"
    local target="$2"
    local preserve_rules="${3:-}"

    _transport_join_remote "${target}"
    local remote="${RESOLVED_REMOTE_PATH}"

    case "${TRANSPORT}" in
        ftp)
            _transport_ftp_sync "${stage_dir}" "${remote}" "${preserve_rules}"
            ;;
        scp)
            _transport_scp_sync "${stage_dir}" "${remote}" "${preserve_rules}"
            ;;
        *)
            echo "ERROR: unsupported transport: ${TRANSPORT}" >&2
            return 1
            ;;
    esac
}

_transport_ftp_sync() {
    local stage_dir="$1"
    local remote="$2"
    local preserve_rules="$3"

    command -v lftp >/dev/null 2>&1 || {
        echo "ERROR: lftp is required for FTP deployments" >&2
        return 1
    }

    local mirror_cmd='mirror --reverse --delete --verbose'
    local rule

    IFS=';' read -r -a _preserve <<< "${preserve_rules}"
    for rule in "${_preserve[@]}"; do
        [[ -n "${rule}" ]] || continue
        local escaped="${rule//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        mirror_cmd+=" --exclude-glob \"${escaped}\""
    done

    local source="${stage_dir%/}/"
    local source_escaped="${source//\\/\\\\}"
    source_escaped="${source_escaped//\"/\\\"}"

    local remote_escaped="${remote%/}/"
    remote_escaped="${remote_escaped//\\/\\\\}"
    remote_escaped="${remote_escaped//\"/\\\"}"

    {
        _transport_ftp_script_header
        printf 'mkdir -p "%s"\n' "${remote//\"/\\\"}"
        printf '%s "%s" "%s"\n' "${mirror_cmd}" "${source_escaped}" "${remote_escaped}"
        printf 'bye\n'
    } | lftp
}

_transport_scp_sync() {
    local stage_dir="$1"
    local remote="$2"
    local preserve_rules="$3"

    command -v ssh >/dev/null 2>&1 || {
        echo "ERROR: ssh is required for SCP deployments" >&2
        return 1
    }

    command -v scp >/dev/null 2>&1 || {
        echo "ERROR: scp is required for SCP deployments" >&2
        return 1
    }

    _transport_build_ssh

    local stamp="$$"
    local new_path="${remote}.deploy-new-${stamp}"
    local old_path="${remote}.deploy-old-${stamp}"

    local q_remote q_new q_old
    q_remote="$(_transport_shell_quote "${remote}")"
    q_new="$(_transport_shell_quote "${new_path}")"
    q_old="$(_transport_shell_quote "${old_path}")"

    "${SSH_CMD[@]}" "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
        "rm -rf ${q_new} ${q_old} && mkdir -p ${q_new}"

    "${SCP_CMD[@]}" -r \
        "${stage_dir}/." \
        "${TRANSPORT_USER}@${TRANSPORT_HOST}:${new_path}/"

    local rule parent q_src q_dst q_parent
    IFS=';' read -r -a _preserve <<< "${preserve_rules}"

    for rule in "${_preserve[@]}"; do
        [[ -n "${rule}" ]] || continue

        if [[ "${rule}" == /* || "${rule}" == *".."* || "${rule}" == *[\*\?\[]* ]]; then
            echo "ERROR: preserve rule must be a literal relative path: ${rule}" >&2
            return 1
        fi

        parent="$(dirname -- "${rule}")"
        q_src="$(_transport_shell_quote "${remote}/${rule}")"
        q_dst="$(_transport_shell_quote "${new_path}/${rule}")"
        q_parent="$(_transport_shell_quote "${new_path}/${parent}")"

        "${SSH_CMD[@]}" "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
            "if [ -e ${q_src} ]; then mkdir -p ${q_parent} && cp -a ${q_src} ${q_dst}; fi"
    done

    "${SSH_CMD[@]}" "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
        "if [ -e ${q_remote} ]; then mv ${q_remote} ${q_old}; fi && mv ${q_new} ${q_remote} && rm -rf ${q_old}"
}

transport_upload_file() {
    local local_file="$1"
    local target="$2"
    local remote_name="$3"

    [[ -f "${local_file}" ]] || {
        echo "ERROR: upload source file missing: ${local_file}" >&2
        return 1
    }

    _transport_validate_remote_name "${remote_name}"
    _transport_join_remote "${target}"

    local remote_dir="${RESOLVED_REMOTE_PATH%/}"
    local remote_file="${remote_dir}/${remote_name}"

    case "${TRANSPORT}" in
        ftp)
            command -v lftp >/dev/null 2>&1 || {
                echo "ERROR: lftp is required for FTP uploads" >&2
                return 1
            }

            {
                _transport_ftp_script_header
                printf 'mkdir -p "%s"\n' "${remote_dir//\"/\\\"}"
                printf 'put "%s" -o "%s"\n' \
                    "${local_file//\"/\\\"}" \
                    "${remote_file//\"/\\\"}"
                printf 'bye\n'
            } | lftp
            ;;
        scp)
            _transport_build_ssh
            local q_dir
            q_dir="$(_transport_shell_quote "${remote_dir}")"

            "${SSH_CMD[@]}" \
                "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
                "mkdir -p ${q_dir}"

            "${SCP_CMD[@]}" \
                "${local_file}" \
                "${TRANSPORT_USER}@${TRANSPORT_HOST}:${remote_file}"
            ;;
        *)
            echo "ERROR: unsupported transport: ${TRANSPORT}" >&2
            return 1
            ;;
    esac
}

transport_remove_file() {
    local target="$1"
    local remote_name="$2"

    _transport_validate_remote_name "${remote_name}"
    _transport_join_remote "${target}"

    local remote_dir="${RESOLVED_REMOTE_PATH%/}"
    local remote_file="${remote_dir}/${remote_name}"

    case "${TRANSPORT}" in
        ftp)
            {
                _transport_ftp_script_header
                printf 'rm "%s"\n' "${remote_file//\"/\\\"}"
                printf 'bye\n'
            } | lftp
            ;;
        scp)
            _transport_build_ssh
            local q_file
            q_file="$(_transport_shell_quote "${remote_file}")"

            "${SSH_CMD[@]}" \
                "${TRANSPORT_USER}@${TRANSPORT_HOST}" \
                "rm -f ${q_file}"
            ;;
        *)
            echo "ERROR: unsupported transport: ${TRANSPORT}" >&2
            return 1
            ;;
    esac
}
