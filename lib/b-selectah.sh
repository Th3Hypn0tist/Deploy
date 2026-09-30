#!/usr/bin/env bash

branch_select() {
    local repo_dir="$1"

    echo
    echo "Fetching remote branches..."
    git -C "${repo_dir}" fetch --prune origin

    local current
    current="$(git -C "${repo_dir}" branch --show-current || true)"

    local branches=()
    mapfile -t branches < <(
        git -C "${repo_dir}" for-each-ref \
            --format='%(refname:strip=3)' \
            refs/remotes/origin/ \
        | grep -v '^HEAD$' \
        | sort
    )

    if (( ${#branches[@]} == 0 )); then
        echo "ERROR: no remote branches found" >&2
        return 1
    fi

    echo
    echo "BRANCH"
    echo

    local i marker
    for i in "${!branches[@]}"; do
        marker=""
        [[ "${branches[$i]}" == "${current}" ]] && marker="  * current"
        printf "  %d) %s%s\n" "$((i + 1))" "${branches[$i]}" "${marker}"
    done

    echo
    echo "  0) Cancel"
    echo

    local choice

    while true; do
        if [[ -n "${current}" ]]; then
            read -r -p "Select branch [${current}]: " choice
        else
            read -r -p "Select branch: " choice
        fi

        if [[ -z "${choice}" && -n "${current}" ]]; then
            SELECTED_BRANCH="${current}"
            return 0
        fi

        if [[ "${choice}" == "0" ]]; then
            echo "Cancelled."
            exit 0
        fi

        if [[ "${choice}" =~ ^[0-9]+$ ]] \
            && (( choice >= 1 && choice <= ${#branches[@]} )); then
            SELECTED_BRANCH="${branches[$((choice - 1))]}"
            return 0
        fi

        echo "ERROR: invalid branch selection"
    done
}
