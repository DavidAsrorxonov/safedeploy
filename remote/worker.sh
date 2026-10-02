#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

remote_worker_error() {
    local message="$1"

    printf 'Remote worker error: %s\n' "$message" >&2
    return 1
}

validate_worker_text() {
    local field_name="$1"
    local value="$2"
    local maximum_length="$3"
    local LC_ALL=C

    if [[ -z "$value" ]]; then
        remote_worker_error "${field_name} must not be empty."
        return 2
    fi

    if (( ${#value} > maximum_length )); then
        remote_worker_error "${field_name} is too long."
        return 2
    fi

    if [[ "$value" =~ [[:cntrl:]] ]]; then
        remote_worker_error \
            "${field_name} must not contain control character."
        return 2
    fi

    return 0
}

validate_worker_arguments() {
    local remote_path="$1"
    local attempt_id="$2"
    local operation="$3"
    local environment_name="$4"
    local actor="$5"
    local controller_id="$6"
    local LC_ALL=C

    if [[ "$remote_path" != /* || "$remote_path" == "/" ]]; then
        remote_worker_error \
            "The remote application path must be an absolute non-root path."
        return 2
    fi

    if [[ ! "$attempt_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$ ]]; then
        remote_worker_error "The attempt ID has an invalid format."
        return 2
    fi

    case "$operation" in
        deploy|rollback)
            ;;
        *)
            remote_worker_error \
                "Unsupported mutating operation: ${operation}"
            return 2
            ;;
    esac

    if [[ ! "$environment_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        remote_worker_error "The environment name has an invalid format."
        return 2
    fi

    validate_worker_text "actor" "$actor" 256 || return $?
    validate_worker_text "controller_id" "$controller_id" 256 || return $?

    return 0
}

remote_worker_on_exit() {
    local original_status="$1"
    local cleanup_status=0

    trap - EXIT INT TERM

    release_deploy_lock || cleanup_status=$?

    if (( original_status == 0 && cleanup_status != 0 )); then
        original_status="$cleanup_status"
    fi

    exit "$original_status"
}

remote_worker_main() {
    local remote_path="${1:-}"
    local attempt_id="${2:-}"
    local operation="${3:-}"
    local environment_name="${4:-}"
    local actor="${5:-}"
    local controller_id="${6:-}"
    local lock_status=0

    if (( $# != 6 )); then
        remote_worker_error \
            "Remote worker expects exactly six arguments."
        return 2
    fi

    validate_worker_arguments \
        "$remote_path" \
        "$attempt_id" \
        "$operation" \
        "$environment_name" \
        "$actor" \
        "$controller_id" || return $?

    trap 'remote_worker_on_exit "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    canonicalize_remote_root "$remote_path" || return 1
    prepare_remote_lock_layout || return 1

    acquire_deploy_lock \
        "$attempt_id" \
        "$operation" \
        "$environment_name" \
        "$actor" \
        "$controller_id" || lock_status=$?

    if (( lock_status != 0 )); then
        return "$lock_status"
    fi

    if ! jq -cn \
        --arg attempt_id "$attempt_id" \
        --arg operation "$operation" \
        --arg canonical_root "$SAFEDEPLOY_REMOTE_ROOT" \
        '{
            event: "lock_acquired",
            attempt_id: $attempt_id,
            operation: $operation,
            canonical_root: $canonical_root
        }'; then
        remote_worker_error "Unable to report lock acquisition."
        return 1
    fi

    # Currently this verifies the worker and lock lifecycle only.

    return 0
}

remote_worker_main "$@"
