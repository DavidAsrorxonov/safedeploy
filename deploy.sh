#!/usr/bin/env bash

if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "safedeploy requires Bash." >&2
    exit 2
fi

if (( BASH_VERSINFO[0] < 3 ||
      (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2) )); then
    printf '%s\n' "safedeploy requires Bash 3.2 or newer." >&2
    exit 2
fi

set -Eeuo pipefail
IFS=$'\n\t'

SAFEDEPLOY_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd -P
)" || {
    printf '%s\n' "Unable to determine the safedeploy directory." >&2
    exit 1
}

readonly SAFEDEPLOY_ROOT
readonly SAFEDEPLOY_LIB_DIR="${SAFEDEPLOY_ROOT}/lib"
readonly SAFEDEPLOY_CONFIG_DIR="${SAFEDEPLOY_ROOT}/config"

main() {
    printf '%s\n' "safedeploy: CLI parser is not implemented yet." >&2
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi