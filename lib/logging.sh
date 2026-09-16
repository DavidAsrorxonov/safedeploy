# shellcheck shell=bash

SAFEDEPLOY_LOG_FILE=""
SAFEDEPLOY_ATTEMPT_ID=""
SAFEDEPLOY_ACTOR=""
SAFEDEPLOY_RELEASE_ID=""
SAFEDEPLOY_COMMIT_SHA=""
SAFEDEPLOY_LOG_SECRETS=()

logging_error() {
    local message="$1"

    printf 'Logging error: %s\n' "$message" >&2
    return 1
}

create_attempt_id() {
    local timestamp=""

    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')" || {
        logging_error "Unable to generate an attempt timestamp."
        return 1
    }

    printf '%s-%s-%s\n' "$timestamp" "$$" "$RANDOM"
}

resolve_actor() {
    if [[ -n "${USER:-}" ]]; then
        printf '%s\n' "$USER"
        return 0
    fi

    if command -v id >/dev/null 2>&1; then
        id -un
        return $?
    fi

    printf '%s\n' "unknown"
}

register_log_secret() {
    local secret_value="$1"

    if [[ -z "$secret_value" ]]; then
        return 0
    fi

    SAFEDEPLOY_LOG_SECRETS+=("$secret_value")
}

register_default_log_secrets() {
    SAFEDEPLOY_LOG_SECRETS=()

    register_log_secret "${SLACK_WEBHOOK_URL:-}"
    register_log_secret "${REPOSITORY_URL:-}"
}

redact_literal_value() {
    local input="$1"
    local secret="$2"
    local result=""
    local prefix=""
    local remaining="$input"

    if [[ -z "$secret" ]]; then
        printf '%s' "$input"
        return 0
    fi

    while [[ "$remaining" == *"$secret"* ]]; do
        prefix="${remaining%%"$secret"*}"
        result="${result}${prefix}[REDACTED]"
        remaining="${remaining#*"$secret"}"
    done

    printf '%s%s' "$result" "$remaining"
}

redact_log_text() {
    local redacted="$1"
    local secret=""
    local index=0

    while (( index < ${#SAFEDEPLOY_LOG_SECRETS[@]} )); do
        secret="${SAFEDEPLOY_LOG_SECRETS[$index]}"
        redacted="$(redact_literal_value "$redacted" "$secret")"
        index=$(( index + 1 ))
    done

    printf '%s' "$redacted"
}

sanitize_log_message() {
    local message="$1"

    message="$(redact_log_text "$message")"

    message="${message//$'\r'/\\r}"

    message="${message//$'\r'/\\r}"
    message="${message//$'\n'/\\n}"
    message="${message//$'\t'/\\t}"
       
    printf '%s' "$message"
}

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

initialize_logging() {
    local environment_name="$1"
    local log_directory="${SAFEDEPLOY_ROOT}/logs"

    SAFEDEPLOY_ATTEMPT_ID="$(create_attempt_id)" || return 1
    SAFEDEPLOY_ACTOR="$(resolve_actor)" || SAFEDEPLOY_ACTOR="unknown"

    SAFEDEPLOY_LOG_FILE="${log_directory}/deploy-${environment_name}-${SAFEDEPLOY_ATTEMPT_ID}.log"

    if [[ -L "$log_directory" ]]; then
        logging_error "${log_directory} must not be a symbolic link."
        return 1
    fi

    if [[ -e "$log_directory" && ! -d "$log_directory" ]]; then
        logging_error "${log_directory} exists but is not a directory."
        return 1
    fi

    if ! (umask 077 && mkdir -p -- "$log_directory"); then
        logging_error "Unable to create log directory: ${log_directory}"
        return 1
    fi

    if ! chmod 700 "$log_directory"; then
        logging_error "Unable to secure log directory: ${log_directory}"
        return 1
    fi

    if [[ -e "$SAFEDEPLOY_LOG_FILE" || -L "$SAFEDEPLOY_LOG_FILE" ]]; then
        logging_error "Refusing to overwrite existing log: ${SAFEDEPLOY_LOG_FILE}"
        return 1
    fi

    if ! (
        umask 077
        set -o noclobber
        : > "$SAFEDEPLOY_LOG_FILE"
    ) 2>/dev/null; then
        logging_error "Unable to create log file: ${SAFEDEPLOY_LOG_FILE}"
        return 1
    fi

    if ! chmod 600 "$SAFEDEPLOY_LOG_FILE"; then
        logging_error "Unable to secure log file: ${SAFEDEPLOY_LOG_FILE}"
        return 1
    fi

    register_default_log_secrets

    return 0
}

log_event() {
    local level="$1"
    local action="$2"
    local phase="$3"
    local outcome="$4"
    local exit_code="$5"
    local message="$6"

    local timestamp=""
    local safe_message=""
    local environment="${CONFIG_ENVIRONMENT:-}"
    local target="${REMOTE_HOST:-}"
    local dry_run="${CLI_DRY_RUN:-false}"

    case "$level" in
        DEBUG|INFO|WARN|ERROR)
            ;;
        *)
            logging_error "Invalid log level: ${level}"
            return 1
            ;;
    esac

    if [[ ! "$exit_code" =~ ^[0-9]+$ ]]; then
        logging_error "Log exit code must be a non-negative integer."
        return 1
    fi

    if [[ -z "$SAFEDEPLOY_LOG_FILE" ]]; then
        logging_error "Logging has not been initialized."
        return 1
    fi

    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || {
        logging_error "Unable to generate an event timestamp."
        return 1
    }

    safe_message="$(sanitize_log_message "$message")"

    if ! printf \
        '{"timestamp":"%s","level":"%s","attempt_id":"%s","environment":"%s","target":"%s","action":"%s","phase":"%s","release_id":"%s","commit_sha":"%s","outcome":"%s","actor":"%s","dry_run":%s,"exit_code":%s,"message":"%s"}\n' \
        "$(json_escape "$timestamp")" \
        "$(json_escape "$level")" \
        "$(json_escape "$SAFEDEPLOY_ATTEMPT_ID")" \
        "$(json_escape "$environment")" \
        "$(json_escape "$target")" \
        "$(json_escape "$action")" \
        "$(json_escape "$phase")" \
        "$(json_escape "$SAFEDEPLOY_RELEASE_ID")" \
        "$(json_escape "$SAFEDEPLOY_COMMIT_SHA")" \
        "$(json_escape "$outcome")" \
        "$(json_escape "$SAFEDEPLOY_ACTOR")" \
        "$dry_run" \
        "$exit_code" \
        "$(json_escape "$safe_message")" \
        >> "$SAFEDEPLOY_LOG_FILE"; then
        logging_error "Unable to write log event."
        return 1
    fi

    printf '[%s] %-5s %s\n' \
        "$timestamp" \
        "$level" \
        "$safe_message" >&2

    return 0
}