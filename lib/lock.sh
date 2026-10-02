# shellcheck shell=bash

SAFEDEPLOY_REMOTE_ROOT=""
SAFEDEPLOY_PRIVATE_DIR=""
SAFEDEPLOY_ATTEMPTS_DIR=""
SAFEDEPLOY_RELEASE_METADATA_DIR=""
SAFEDEPLOY_LOCK_FILE=""
SAFEDEPLOY_OWNER_FILE=""

SAFEDEPLOY_LOCK_HELD=false
SAFEDEPLOY_LOCK_ATTEMPT_ID=""
SAFEDEPLOY_LOCK_FD=9

remote_lock_error() {
    local message="$1"

    printf 'Remote lock error: %s\n' "$message" >&2
    return 1
}

remote_value_contains_control_character() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ [[:cntrl:]] ]]
}

clear_remote_lock_context() {
    SAFEDEPLOY_LOCK_HELD=false
    SAFEDEPLOY_LOCK_ATTEMPT_ID=""
}

canonicalize_remote_root() {
    local requested_root="$1"
    local canonical_root=""

    if [[ -z "$requested_root" || "$requested_root" != /* ]]; then
        remote_lock_error "The application root must be an absolute path."
        return 1
    fi

    canonical_root="$(
        cd -P -- "$requested_root" &&
        pwd -P
    )" || {
        remote_lock_error \
            "Unable to resolve application root: ${requested_root}"
        return 1
    }

    if [[ "$canonical_root" == "/" ]]; then
        remote_lock_error \
            "The filesystem root cannot be used as an application root."
        return 1
    fi

    SAFEDEPLOY_REMOTE_ROOT="$canonical_root"
    SAFEDEPLOY_PRIVATE_DIR="${canonical_root}/.safedeploy"
    SAFEDEPLOY_ATTEMPTS_DIR="${SAFEDEPLOY_PRIVATE_DIR}/attempts"
    SAFEDEPLOY_RELEASE_METADATA_DIR="${SAFEDEPLOY_PRIVATE_DIR}/releases"
    SAFEDEPLOY_LOCK_FILE="${SAFEDEPLOY_PRIVATE_DIR}/deploy.lock"
    SAFEDEPLOY_OWNER_FILE="${SAFEDEPLOY_PRIVATE_DIR}/owner.json"

    return 0
}

prepare_private_directory() {
    local directory_path="$1"

    if [[ -L "$directory_path" ]]; then
        remote_lock_error \
            "Managed directory must not be a symbolic link: ${directory_path}"
        return 1
    fi

    if [[ -e "$directory_path" && ! -d "$directory_path" ]]; then
        remote_lock_error \
            "Managed path exists but is not a directory: ${directory_path}"
        return 1
    fi

    if [[ ! -d "$directory_path" ]]; then
        if ! (
            umask 077
            mkdir -p -- "$directory_path"
        ); then
            remote_lock_error \
                "Unable to create managed directory: ${directory_path}"
            return 1
        fi
    fi

    if [[ ! -O "$directory_path" ]]; then
        remote_lock_error \
            "Managed directory is not owned by the deploy user: ${directory_path}"
        return 1
    fi

    if ! chmod 700 "$directory_path"; then
        remote_lock_error \
            "Unable to secure managed directory: ${directory_path}"
        return 1
    fi

    return 0
}

prepare_remote_lock_layout() {
    local directory_path=""
    local -a private_directories=(
        "$SAFEDEPLOY_PRIVATE_DIR"
        "$SAFEDEPLOY_ATTEMPTS_DIR"
        "$SAFEDEPLOY_RELEASE_METADATA_DIR"
    )

    if [[ -z "$SAFEDEPLOY_REMOTE_ROOT" ]]; then
        remote_lock_error "The canonical application root is not configured."
        return 1
    fi

    for directory_path in "${private_directories[@]}"; do
        prepare_private_directory "$directory_path" || return 1
    done

    if [[ -L "$SAFEDEPLOY_LOCK_FILE" ]]; then
        remote_lock_error \
            "Lock file must not be a symbolic link: ${SAFEDEPLOY_LOCK_FILE}"
        return 1
    fi

    if [[ -e "$SAFEDEPLOY_LOCK_FILE" &&
          ! -f "$SAFEDEPLOY_LOCK_FILE" ]]; then
        remote_lock_error \
            "Lock path exists but is not a regular file: ${SAFEDEPLOY_LOCK_FILE}"
        return 1
    fi

    if ! (
        umask 077
        : >> "$SAFEDEPLOY_LOCK_FILE"
    ); then
        remote_lock_error \
            "Unable to create or open lock file: ${SAFEDEPLOY_LOCK_FILE}"
        return 1
    fi

    if [[ ! -O "$SAFEDEPLOY_LOCK_FILE" ]]; then
        remote_lock_error \
            "Lock file is not owned by the deploy user."
        return 1
    fi

    if ! chmod 600 "$SAFEDEPLOY_LOCK_FILE"; then
        remote_lock_error "Unable to secure the lock file."
        return 1
    fi

    if [[ -L "$SAFEDEPLOY_OWNER_FILE" ]]; then
        remote_lock_error "Owner metadata must not be a symbolic link."
        return 1
    fi

    if [[ -e "$SAFEDEPLOY_OWNER_FILE" &&
          ! -f "$SAFEDEPLOY_OWNER_FILE" ]]; then
        remote_lock_error \
            "Owner metadata exists but is not a regular file."
        return 1
    fi

    return 0
}

remote_process_start_ticks() {
    if [[ -r "/proc/$$/stat" ]]; then
        awk '{ print $22 }' "/proc/$$/stat"
        return $?
    fi

    printf '%s\n' "unknown"
}

remote_boot_id() {
    if [[ -r /proc/sys/kernel/random/boot_id ]]; then
        cat /proc/sys/kernel/random/boot_id
        return $?
    fi

    printf '%s\n' "unknown"
}

write_owner_metadata() {
    local operation="$1"
    local environment_name="$2"
    local actor="$3"
    local controller_id="$4"

    local owner_temp=""
    local started_at=""
    local process_start_ticks=""
    local boot_id=""

    started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || {
        remote_lock_error "Unable to generate the lock start time."
        return 1
    }

    process_start_ticks="$(remote_process_start_ticks)" || {
        remote_lock_error "Unable to read the remote process start identity."
        return 1
    }

    boot_id="$(remote_boot_id)" || {
        remote_lock_error "Unable to read the remote boot identity."
        return 1
    }

    owner_temp="$(
        umask 077
        mktemp "${SAFEDEPLOY_PRIVATE_DIR}/owner.json.tmp.XXXXXX"
    )" || {
        remote_lock_error "Unable to create temporary owner metadata."
        return 1
    }

    if ! jq -n \
        --argjson schema_version 1 \
        --arg attempt_id "$SAFEDEPLOY_LOCK_ATTEMPT_ID" \
        --arg operation "$operation" \
        --arg environment "$environment_name" \
        --arg actor "$actor" \
        --arg controller_id "$controller_id" \
        --argjson pid "$$" \
        --arg boot_id "$boot_id" \
        --arg start_ticks "$process_start_ticks" \
        --arg started_at "$started_at" \
        --arg canonical_root "$SAFEDEPLOY_REMOTE_ROOT" \
        '{
            schema_version: $schema_version,
            attempt_id: $attempt_id,
            operation: $operation,
            environment: $environment,
            actor: $actor,
            controller_id: $controller_id,
            remote_process: {
                pid: $pid,
                boot_id: $boot_id,
                start_ticks: $start_ticks
            },
            started_at: $started_at,
            canonical_root: $canonical_root
        }' > "$owner_temp"; then
        rm -f -- "$owner_temp"
        remote_lock_error "Unable to construct owner metadata."
        return 1
    fi

    if ! chmod 600 "$owner_temp"; then
        rm -f -- "$owner_temp"
        remote_lock_error "Unable to secure temporary owner metadata."
        return 1
    fi

    if ! mv -f -- "$owner_temp" "$SAFEDEPLOY_OWNER_FILE"; then
        rm -f -- "$owner_temp"
        remote_lock_error "Unable to commit owner metadata."
        return 1
    fi

    return 0
}

read_existing_owner_summary() {
    if [[ ! -f "$SAFEDEPLOY_OWNER_FILE" ]]; then
        printf '%s\n' "owner metadata unavailable"
        return 0
    fi

    if ! jq -r '
        "attempt_id=" + (.attempt_id // "unknown") +
        " operation=" + (.operation // "unknown") +
        " controller_id=" + (.controller_id // "unknown")
    ' "$SAFEDEPLOY_OWNER_FILE" 2>/dev/null; then
        printf '%s\n' "owner metadata unreadable"
    fi
}

acquire_deploy_lock() {
    local attempt_id="$1"
    local operation="$2"
    local environment_name="$3"
    local actor="$4"
    local controller_id="$5"
    local owner_summary=""

    clear_remote_lock_context

    if [[ -z "$SAFEDEPLOY_LOCK_FILE" ]]; then
        remote_lock_error "The remote lock layout is not configured."
        return 1
    fi

    if ! exec 9>"$SAFEDEPLOY_LOCK_FILE"; then
        remote_lock_error "Unable to open the deployment lock."
        return 1
    fi

    if ! flock -n "$SAFEDEPLOY_LOCK_FD"; then
        owner_summary="$(read_existing_owner_summary)"
        exec 9>&-

        printf 'Deployment lock is already held: %s\n' \
            "$owner_summary" >&2
        return 75
    fi

    SAFEDEPLOY_LOCK_HELD=true
    SAFEDEPLOY_LOCK_ATTEMPT_ID="$attempt_id"

    if ! write_owner_metadata \
        "$operation" \
        "$environment_name" \
        "$actor" \
        "$controller_id"; then
        flock -u "$SAFEDEPLOY_LOCK_FD" || true
        exec 9>&-
        clear_remote_lock_context
        return 1
    fi

    return 0
}

release_deploy_lock() {
    local failed=0
    local owner_attempt_id=""

    if [[ "$SAFEDEPLOY_LOCK_HELD" != true ]]; then
        return 0
    fi

    if [[ -e "$SAFEDEPLOY_OWNER_FILE" ||
        -L "$SAFEDEPLOY_OWNER_FILE" ]]; then
            if [[ -L "$SAFEDEPLOY_OWNER_FILE" ||
            ! -f "$SAFEDEPLOY_OWNER_FILE" ]]; then
                remote_lock_error \
                    "Owner metadata changed to an unsafe file type."
                failed=1
            elif ! owner_attempt_id="$(
                jq -er '
                    .attempt_id |
                    select(type == "string")
                ' "$SAFEDEPLOY_OWNER_FILE"
            )"; then
                remote_lock_error \
                    "Owner metadata cannot be validated during cleanup."
                failed=1
            elif [[ "$owner_attempt_id" != \
                    "$SAFEDEPLOY_LOCK_ATTEMPT_ID" ]]; then
                remote_lock_error \
                    "Refusing to remove owner metadata belonging to another attempt."
                failed=1
            elif ! rm -f -- "$SAFEDEPLOY_OWNER_FILE"; then
                remote_lock_error "Unable to remove owned metadata."
                failed=1
            fi
    fi

    if ! flock -u "$SAFEDEPLOY_LOCK_FD"; then
        remote_lock_error "Unable to release the deployment lock."
        failed=1
    fi

    if ! exec 9>&-; then
        remote_lock_error "Unable to close the deployment lock descriptor."
        failed=1
    fi

    clear_remote_lock_context

    return "$failed"
}
