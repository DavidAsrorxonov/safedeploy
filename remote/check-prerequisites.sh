#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

main() {
    local remote_path="${1:-}"
    local command_name=""
    local -a required_commands=(
        bash
        base64
        chmod
        curl
        flock
        git
        jq
        mkdir
        mktemp
        mv
        timeout
    )

    if (( $# != 1 )); then
        printf '%s\n' \
            "Remote prerequisites check expects exactly one application path." >&2
            return 2
    fi

    if (( BASH_VERSINFO[0] < 3 ||
            (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2) )); then
        printf '%s\n' "Remote target requires Bash 3.2 or newer." >&2
        return 2
    fi

    for command_name in "${required_commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Missing required remote command: %s\n' \
                "$command_name" >&2
            return 1
        fi
    done

    if [[ ! -d "$remote_path" ]]; then
        printf 'Remote application root does not exist: %s\n' \
            "$remote_path" >&2
        return 1
    fi

    if [[ ! -w "$remote_path" ]]; then
        printf 'Remote application root is not writable: %s\n' \
            "$remote_path" >&2
        return 1
    fi

    printf '%s\n' "safedeploy-preflight-ok"
}

main "$@"