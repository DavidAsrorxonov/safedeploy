#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd -P
)" || {
    printf '%s\n' "Unable to determine the safedeploy directory." >&2
    exit 1
}

readonly SCRIPT_DIR

exec "${SCRIPT_DIR}/deploy.sh" --rollback "$@"