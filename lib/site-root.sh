#!/usr/bin/env bash

# Candidate site tree prefix.
# Unset -> /test
# Explicit empty -> production root
SITE_ROOT_PREFIX="${AIGM_SITE_ROOT_PREFIX-/test}"

site_root_normalize() {
    local value="${1:-}"

    if [[ -z "${value}" || "${value}" == "/" ]]; then
        printf '%s' ""
        return 0
    fi

    [[ "${value}" == /* ]] || {
        echo "ERROR: site root prefix must be absolute or empty: ${value}" >&2
        return 1
    }

    [[ "${value}" != *".."* && "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || {
        echo "ERROR: unsafe site root prefix: ${value}" >&2
        return 1
    }

    while [[ "${value}" == */ ]]; do
        value="${value%/}"
    done

    printf '%s' "${value}"
}

SITE_ROOT_PREFIX="$(site_root_normalize "${SITE_ROOT_PREFIX}")"

site_target() {
    local logical="$1"

    [[ "${logical}" == /* ]] || {
        echo "ERROR: site target must be an absolute logical path: ${logical}" >&2
        return 1
    }

    [[ "${logical}" != *".."* && "${logical}" != *$'\n'* && "${logical}" != *$'\r'* ]] || {
        echo "ERROR: unsafe site target: ${logical}" >&2
        return 1
    }

    if [[ -z "${SITE_ROOT_PREFIX}" ]]; then
        printf '%s' "${logical}"
    elif [[ "${logical}" == "/" ]]; then
        printf '%s' "${SITE_ROOT_PREFIX}"
    else
        printf '%s%s' "${SITE_ROOT_PREFIX}" "${logical}"
    fi
}
