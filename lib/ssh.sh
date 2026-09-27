# shellcheck shell=bash

SAFEDEPLOY_SSH_CONTROL_DIR=""
SAFEDEPLOY_SSH_CONTROL_PATH=""
SAFEDEPLOY_SSH_OPTIONS=()

ssh_error() {
    local message="$1"

    printf 'SSH error: %s\n' "$message" >&2
    return 1
}

encode_ssh_argument() {
    local value="$1"
    local encoded=""

    encoded="$(
        printf '%s' "$value" |
            base64 |
            tr -d '\r\n'
    )" || {
        ssh_error "Unable to encode a remote argument."
        return 1
    }

    if [[ ! "$encoded" =~ ^[a-zA-Z0-9+/=]*$ ]]; then
        ssh_error "Argument encoding produced an unexpected value."
        return 1
    fi

    # The x prefix ensures an empty value still occupies one shell argument.
    printf 'x%s' "$encoded"
}

emit_remote_argument_decoder() {
    cat <<'REMOTE_BOOTSTRAP'
set -Eeuo pipefail
IFS=$'\n\t'

if ! command -v base64 >/dev/null 2>&1; then
    printf '%s\n' "Remote target requires base64." >&2
    exit 127
fi

_sd_decoder=()

if printf '' | base64 --decode >/dev/null 2>&1; then
    _sd_decoder=(base64 --decode)
elif printf '' | base64 -d >/dev/null 2>&1; then
    _sd_decoder=(base64 -d)
elif printf '' | base64 -D >/dev/null 2>&1; then
    _sd_decoder=(base64 -D)
else
    printf '%s\n' "Unable to determine the remote base64 decode option." >&2
    exit 127
fi

_sd_decoded_arguments=()

for _sd_encoded_argument in "$@"; do
    if [[ "$_sd_encoded_argument" != x* ]]; then
        printf '%s\n' "Invalid encoded remote argument." >&2
        exit 2
    fi

    _sd_payload="${_sd_encoded_argument#x}"

    _sd_decoded="$(
        if ! printf '%s' "$_sd_payload" |
            "${_sd_decoder[@]}"; then
            exit 1
        fi

        # The marker preserves trailing newlines through command substitution.
        printf '\001'
    )" || {
        printf '%s\n' "Unable to decode a remote argument." >&2
        exit 2
    }

    _sd_decoded="${_sd_decoded%$'\001'}"
    _sd_decoded_arguments+=("$_sd_decoded")
done

set -- "${_sd_decoded_arguments[@]}"

unset _sd_decoder
unset _sd_decoded_arguments
unset _sd_encoded_argument
unset _sd_payload
unset _sd_decoded
REMOTE_BOOTSTRAP
}

initialize_ssh() {
    local temp_root="${TMPDIR:-/tmp}"
    local control_template=""

    if ! command -v ssh >/dev/null 2>&1; then
        ssh_error "The local ssh command is required."
        return 1
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        ssh_error "The local base64 command is required."
        return 1
    fi

    if ! command -v tr >/dev/null 2>&1; then
        ssh_error "The local tr command is required."
        return 1
    fi

    if ! command -v mktemp >/dev/null 2>&1; then
        ssh_error "The local mktemp command is required."
        return 1
    fi

    if [[ -n "$SAFEDEPLOY_SSH_CONTROL_DIR" ]]; then
        ssh_error "SSH has already been initialized."
        return 1
    fi

    if [[ "$temp_root" != /* ||
          ! -d "$temp_root" ||
          ! -w "$temp_root" ]]; then
        temp_root="/tmp"
    fi

    temp_root="${temp_root%/}"
    control_template="${temp_root}/safedeploy-ssh.XXXXXX"

    SAFEDEPLOY_SSH_CONTROL_DIR="$(
        umask 077
        mktemp -d "$control_template"
    )" || {
        SAFEDEPLOY_SSH_CONTROL_DIR=""
        ssh_error "Unable to create a private SSH control directory."
        return 1
    }

    if ! chmod 700 "$SAFEDEPLOY_SSH_CONTROL_DIR"; then
        ssh_error "Unable to secure the SSH control directory."
        return 1
    fi

    SAFEDEPLOY_SSH_CONTROL_PATH="${SAFEDEPLOY_SSH_CONTROL_DIR}/control"

    SAFEDEPLOY_SSH_OPTIONS=(
        -T
        -o "BatchMode=yes"
        -o "PasswordAuthentication=no"
        -o "KbdInteractiveAuthentication=no"
        -o "StrictHostKeyChecking=yes"
        -o "ConnectTimeout=${SSH_CONNECT_TIMEOUT_SECONDS}"
        -o "ServerAliveInterval=${SSH_SERVER_ALIVE_INTERVAL_SECONDS}"
        -o "ServerAliveCountMax=${SSH_SERVER_ALIVE_COUNT_MAX}"
        -o "ControlMaster=auto"
        -o "ControlPersist=60"
        -o "ControlPath=${SAFEDEPLOY_SSH_CONTROL_PATH}"
    )

    return 0
}

cleanup_ssh() {
    local failed=0

    if [[ -z "$SAFEDEPLOY_SSH_CONTROL_DIR" ]]; then
        return 0
    fi

    if [[ -S "$SAFEDEPLOY_SSH_CONTROL_PATH" ]]; then
        if ! ssh \
            -S "$SAFEDEPLOY_SSH_CONTROL_PATH" \
            -O exit \
            -- "$REMOTE_HOST" \
            >/dev/null 2>&1; then
            failed=1
        fi
    fi

    if [[ -e "$SAFEDEPLOY_SSH_CONTROL_PATH" ||
          -L "$SAFEDEPLOY_SSH_CONTROL_PATH" ]]; then
        if ! rm -f -- "$SAFEDEPLOY_SSH_CONTROL_PATH"; then
            failed=1
        fi
    fi

    if [[ -d "$SAFEDEPLOY_SSH_CONTROL_DIR" ]]; then
        if ! rmdir -- "$SAFEDEPLOY_SSH_CONTROL_DIR"; then
            failed=1
        fi
    fi

    SAFEDEPLOY_SSH_CONTROL_DIR=""
    SAFEDEPLOY_SSH_CONTROL_PATH=""
    SAFEDEPLOY_SSH_OPTIONS=()

    return "$failed"
}

ssh_run_script() {
    local script_path="$1"
    local encoded_argument=""
    local remote_command="bash -s --"
    local pipeline_status=0
    local -a encoded_arguments=()

    shift

    if [[ ! -f "$script_path" ||
          ! -r "$script_path" ||
          -L "$script_path" ]]; then
        ssh_error \
            "Remote script must be a readable regular file and not a symlink: ${script_path}"
        return 1
    fi

    if [[ -z "$SAFEDEPLOY_SSH_CONTROL_DIR" ]]; then
        ssh_error "SSH has not been initialized."
        return 1
    fi

    while (( $# > 0 )); do
        encoded_argument="$(encode_ssh_argument "$1")" || return 1
        encoded_arguments+=("$encoded_argument")
        shift
    done

    for encoded_argument in "${encoded_arguments[@]}"; do
        remote_command="${remote_command} ${encoded_argument}"
    done

    {
        emit_remote_argument_decoder
        cat -- "$script_path"
    } |
        ssh \
            "${SAFEDEPLOY_SSH_OPTIONS[@]}" \
            -- "$REMOTE_HOST" \
            "$remote_command" ||
        pipeline_status=$?

    return "$pipeline_status"
}

ssh_check_connectivity() {
    local remote_script="${SAFEDEPLOY_ROOT}/remote/check-prerequisites.sh"
    local ssh_status=0

    ssh_run_script "$remote_script" "$REMOTE_PATH" >/dev/null ||
        ssh_status=$?

    if (( ssh_status != 0 )); then
        log_event \
            "ERROR" \
            "$CLI_OPERATION" \
            "ssh-preflight" \
            "failed" \
            "$ssh_status" \
            "SSH connectivity or remote prerequisite validation failed." ||
            return 1

        return "$ssh_status"
    fi

    log_event \
        "INFO" \
        "$CLI_OPERATION" \
        "ssh-preflight" \
        "success" \
        0 \
        "SSH connectivity and remote prerequisites validated." ||
        return 1

    return 0
}