#!/usr/bin/env bash

repo_ensure() {
    local repo_url="$1"
    local repo_dir="$2"

    if [[ -d "${repo_dir}/.git" ]]; then
        return 0
    fi

    if [[ -e "${repo_dir}" && ! -d "${repo_dir}/.git" ]]; then
        echo "ERROR: local repo path exists but is not a git repository: ${repo_dir}" >&2
        return 1
    fi

    mkdir -p "$(dirname -- "${repo_dir}")"
    git clone "${repo_url}" "${repo_dir}"
}

repo_use_branch() {
    local repo_dir="$1"
    local branch="$2"

    local current
    current="$(git -C "${repo_dir}" branch --show-current || true)"

    if [[ "${current}" != "${branch}" ]]; then
        echo
        echo "Branch changed: ${current:-<detached>} -> ${branch}"
        echo "Resetting deployment working tree to origin/${branch}..."

        git -C "${repo_dir}" switch -C "${branch}" "origin/${branch}"
        git -C "${repo_dir}" reset --hard "origin/${branch}"
        git -C "${repo_dir}" clean -fd
    else
        echo
        echo "Branch unchanged: ${branch}"
        echo "Updating from origin/${branch}..."

        git -C "${repo_dir}" switch "${branch}"
        git -C "${repo_dir}" pull --ff-only origin "${branch}"
    fi
}
