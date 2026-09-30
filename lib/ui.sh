#!/usr/bin/env bash

confirm_yes_no() {
    local prompt="$1"
    local default_yes="${2:-true}"
    local answer label

    if [[ "${default_yes}" == "true" ]]; then
        label="[Y/n]"
    else
        label="[y/N]"
    fi

    while true; do
        printf "%s %s " "${prompt}" "${label}"
        answer=""
        IFS= read -r -n 1 answer || true
        printf "\n"

        case "${answer}" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            "")
                [[ "${default_yes}" == "true" ]]
                return
                ;;
        esac
    done
}
