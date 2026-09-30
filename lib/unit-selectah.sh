#!/usr/bin/env bash

unit_select() {
    local count="${#DEPLOY_UNIT_NAMES[@]}"

    if (( count == 0 )); then
        echo "ERROR: deployment target defines no units" >&2
        return 1
    fi

    if (( count > 8 )); then
        echo "ERROR: maximum 8 deployment units; key 9 is reserved for All" >&2
        return 1
    fi

    echo
    echo "${TARGET_NAME} DEPLOY"
    echo

    local i
    for i in "${!DEPLOY_UNIT_NAMES[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${DEPLOY_UNIT_NAMES[$i]}"
    done

    echo
    echo "  9) All"
    echo "  0) Cancel"
    echo

    local choice
    read -r -p "Select: " choice

    DEPLOY_SELECTED_UNITS=()

    case "${choice}" in
        0)
            echo "Cancelled."
            exit 0
            ;;
        9)
            for i in "${!DEPLOY_UNIT_NAMES[@]}"; do
                DEPLOY_SELECTED_UNITS+=("${i}")
            done
            ;;
        *)
            if ! [[ "${choice}" =~ ^[1-8]$ ]]; then
                echo "ERROR: invalid deployment selection: ${choice}" >&2
                return 2
            fi

            local index=$((choice - 1))
            if (( index < 0 || index >= count )); then
                echo "ERROR: deployment unit does not exist: ${choice}" >&2
                return 2
            fi

            DEPLOY_SELECTED_UNITS+=("${index}")
            ;;
    esac
}
