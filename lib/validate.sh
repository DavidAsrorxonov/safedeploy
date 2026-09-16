# shellcheck shell=bash

validation_error() {
    local message="$1"

    printf 'Validation error: %s\n' "$message" >&2
    return 2
}

contains_control_character() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ [[:cntrl:]] ]]
}

contains_whitespace() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ [[:space:]] ]]
}

is_decimal_integer() {
    local value="$1"
    local LC_ALL=C

    [[ "$value" =~ ^[0-9]+$ ]] && (( ${#value} <= 9 ))
}

validate_required_value() {
    local variable_name="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        validation_error "${variable_name} must not be empty."
        return 2
    fi

    if contains_control_character "$value"; then
        validation_error "${variable_name} must not contain control characters."
        return 2
    fi

    return 0
}

validate_boolean() {
    local variable_name="$1"
    local value="$2"

    case "$value" in
        true|false)
            return 0
            ;;
        *)
            validation_error \
                "${variable_name} must be either true or false; received '${value}'."
            return 2
            ;;
    esac
}

validate_integer_range() {
    local variable_name="$1"
    local value="$2"
    local minimum="$3"
    local maximum="$4"
    local numeric_value=0

    if ! is_decimal_integer "$value"; then
        validation_error \
            "${variable_name} must be a decimal integer; received '${value}'."
        return 2
    fi

    numeric_value=$((10#${value}))

    if (( numeric_value < minimum || numeric_value > maximum )); then
        validation_error \
            "${variable_name} must be between ${minimum} and ${maximum}; received '${value}'."
        return 2
    fi

    return 0
}

validate_remote_host() {
    if ! validate_required_value "REMOTE_HOST" "$REMOTE_HOST"; then
        return 2
    fi

    if [[ "$REMOTE_HOST" == -* ]]; then
        validation_error "REMOTE_HOST must not begin with a hyphen."
        return 2
    fi

    if contains_whitespace "$REMOTE_HOST"; then
        validation_error "REMOTE_HOST must not contain whitespace."
        return 2
    fi

    return 0
}

validate_repository_url() {
    if ! validate_required_value "REPOSITORY_URL" "$REPOSITORY_URL"; then
        return 2
    fi

    if [[ "$REPOSITORY_URL" == -* ]]; then
        validation_error "REPOSITORY_URL must not begin with a hyphen."
        return 2
    fi

    if contains_whitespace "$REPOSITORY_URL"; then
        validation_error "REPOSITORY_URL must not contain whitespace."
        return 2
    fi

    return 0
}

validate_remote_path() {
    if ! validate_required_value "REMOTE_PATH" "$REMOTE_PATH"; then
        return 2
    fi

    if [[ "$REMOTE_PATH" != /* ]]; then
        validation_error "REMOTE_PATH must be an absolute path."
        return 2
    fi

    if [[ "$REMOTE_PATH" == "/" ]]; then
        validation_error "REMOTE_PATH must not be the filesystem root."
        return 2
    fi

    if [[ "$REMOTE_PATH" == */ ]]; then
        validation_error "REMOTE_PATH must not end with a slash."
        return 2
    fi

    if [[ "$REMOTE_PATH" == *"//"* ]]; then
        validation_error "REMOTE_PATH must not contain repeated slashes."
        return 2
    fi

    if [[ "$REMOTE_PATH" == *"/./"* ||
          "$REMOTE_PATH" == */. ||
          "$REMOTE_PATH" == *"/../"* ||
          "$REMOTE_PATH" == */.. ]]; then
        validation_error "REMOTE_PATH must not contain dot path components."
        return 2
    fi

    return 0
}

validate_service_name() {
    if ! validate_required_value "SERVICE_NAME" "$SERVICE_NAME"; then
        return 2
    fi

    if [[ "$SERVICE_NAME" == -* ]]; then
        validation_error "SERVICE_NAME must not begin with a hyphen."
        return 2
    fi

    return 0
}

validate_http_url() {
    local variable_name="$1"
    local value="$2"

    if ! validate_required_value "$variable_name" "$value"; then
        return 2
    fi

    if contains_whitespace "$value"; then
        validation_error "${variable_name} must not contain whitespace."
        return 2
    fi

    case "$value" in
        http://*|https://*)
            return 0
            ;;
        *)
            validation_error \
                "${variable_name} must begin with http:// or https://."
                return 2
                ;;
    esac
}

validate_optional_webhook_url() {
    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        return 0
    fi

    if contains_control_character "$SLACK_WEBHOOK_URL" ||
        contains_whitespace "$SLACK_WEBHOOK_URL"; then
            validation_error \
                "SLACK_WEBHOOK_URL must not contain whitespace or control characters."
                return 2
    fi

    case "$SLACK_WEBHOOK_URL" in
        https://*)
            return 0
            ;;
        *)
            validation_error "SLACK_WEBHOOK_URL must begin with https://."
            return 2
            ;;
    esac
}

validate_git_ref() {
    local requested_ref="$1"

    if [[ -z "$requested_ref" ]]; then
        validation_error "A Git ref is required for deployment."
        return 2
    fi

    if ! command -v git >/dev/null 2>&1; then
        validation_error "Git is required to validate the requested ref."
        return 2
    fi

    if ! git check-ref-format --branch "$requested_ref" >/dev/null 2>&1; then
        validation_error "Invalid Git branch, tag or commit value: '${requested_ref}'."
        return 2
    fi

    return 0
}

validate_optional_hook() {
    local hook_name="$1"
    local hook_path="${SAFEDEPLOY_ROOT}/hooks/${hook_name}"

    if [[ ! -e "$hook_path" && ! -L "$hook_path" ]]; then
        return 0
    fi

    if [[ -L "$hook_path" ]]; then
        validation_error "${hook_path} must not be a symbolic link."
        return 2
    fi

    if [[ ! -f "$hook_path" ]]; then
        validation_error "${hook_path} must be a regular file."
        return 2
    fi

    if [[ ! -x "$hook_path" ]]; then
        validation_error "${hook_path} must be executable."
        return 2
    fi

    return 0
}

validate_configuration() {
    local operation="$1"
    local requested_ref="${2:-}"
    local failed=0
    local initial_interval=0
    local maximum_interval=0
    local connect_timeout=0
    local request_timeout=0

    validate_remote_host || failed=1
    validate_remote_path || failed=1
    validate_repository_url || failed=1
    validate_service_name || failed=1

    validate_required_value "RESTART_CMD" "$RESTART_CMD" || failed=1
    validate_required_value "STOP_CMD" "$STOP_CMD" || failed=1
    validate_required_value "CHECK_STOPPED_CMD" "$CHECK_STOPPED_CMD" || failed=1
    validate_http_url "HEALTHCHECK_URL" "$HEALTHCHECK_URL" || failed=1

    validate_integer_range \
        "PREPARE_COMMAND_TIMEOUT_SECONDS" \
        "$PREPARE_COMMAND_TIMEOUT_SECONDS" 1 86400 || failed=1

    validate_integer_range \
        "SERVICE_COMMAND_TIMEOUT_SECONDS" \
        "$SERVICE_COMMAND_TIMEOUT_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "HEALTHCHECK_EXPECT_STATUS" \
        "$HEALTHCHECK_EXPECT_STATUS" 100 599 || failed=1

    validate_integer_range \
        "HEALTHCHECK_MAX_ATTEMPTS" \
        "$HEALTHCHECK_MAX_ATTEMPTS" 1 1000 || failed=1

    validate_integer_range \
        "HEALTHCHECK_INTERVAL_SECONDS" \
        "$HEALTHCHECK_INTERVAL_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "HEALTHCHECK_MAX_INTERVAL_SECONDS" \
        "$HEALTHCHECK_MAX_INTERVAL_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "HEALTHCHECK_CONNECT_TIMEOUT_SECONDS" \
        "$HEALTHCHECK_CONNECT_TIMEOUT_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "HEALTHCHECK_REQUEST_TIMEOUT_SECONDS" \
        "$HEALTHCHECK_REQUEST_TIMEOUT_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "HEALTHCHECK_DEADLINE_SECONDS" \
        "$HEALTHCHECK_DEADLINE_SECONDS" 1 86400 || failed=1

    validate_integer_range \
        "ROLLBACK_HEALTHCHECK_DEADLINE_SECONDS" \
        "$ROLLBACK_HEALTHCHECK_DEADLINE_SECONDS" 1 86400 || failed=1

    validate_integer_range \
        "SSH_CONNECT_TIMEOUT_SECONDS" \
        "$SSH_CONNECT_TIMEOUT_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "SSH_SERVER_ALIVE_INTERVAL_SECONDS" \
        "$SSH_SERVER_ALIVE_INTERVAL_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "SSH_SERVER_ALIVE_COUNT_MAX" \
        "$SSH_SERVER_ALIVE_COUNT_MAX" 1 100 || failed=1

    validate_integer_range \
        "HOOK_TIMEOUT_SECONDS" \
        "$HOOK_TIMEOUT_SECONDS" 1 86400 || failed=1

    validate_integer_range \
        "NOTIFY_TIMEOUT_SECONDS" \
        "$NOTIFY_TIMEOUT_SECONDS" 1 3600 || failed=1

    validate_integer_range \
        "COMMAND_KILL_GRACE_SECONDS" \
        "$COMMAND_KILL_GRACE_SECONDS" 1 300 || failed=1

    validate_integer_range \
        "LOG_RETENTION_DAYS" \
        "$LOG_RETENTION_DAYS" 1 3650 || failed=1

    validate_integer_range \
        "RELEASES_TO_KEEP" \
        "$RELEASES_TO_KEEP" 1 1000 || failed=1

    validate_boolean \
        "HEALTHCHECK_REQUIRE_RELEASE_ID" \
        "$HEALTHCHECK_REQUIRE_RELEASE_ID" || failed=1

    validate_boolean "AUTO_ROLLBACK" "$AUTO_ROLLBACK" || failed=1
    validate_boolean "NOTIFY_ON_SUCCESS" "$NOTIFY_ON_SUCCESS" || failed=1
    validate_boolean "NOTIFY_ON_FAILURE" "$NOTIFY_ON_FAILURE" || failed=1
    validate_boolean "NOTIFY_ON_UNVERIFIED" "$NOTIFY_ON_UNVERIFIED" || failed=1

    validate_optional_webhook_url || failed=1

    validate_optional_hook "pre-deploy.sh" || failed=1
    validate_optional_hook "post-deploy.sh" || failed=1
    validate_optional_hook "on-failure.sh" || failed=1

    if is_decimal_integer "$HEALTHCHECK_INTERVAL_SECONDS" &&
       is_decimal_integer "$HEALTHCHECK_MAX_INTERVAL_SECONDS"; then
        initial_interval=$((10#${HEALTHCHECK_INTERVAL_SECONDS}))
        maximum_interval=$((10#${HEALTHCHECK_MAX_INTERVAL_SECONDS}))

        if (( maximum_interval < initial_interval )); then
            validation_error \
                "HEALTHCHECK_MAX_INTERVAL_SECONDS must be greater than or equal to HEALTHCHECK_INTERVAL_SECONDS."
            failed=1
        fi
    fi

    if is_decimal_integer "$HEALTHCHECK_CONNECT_TIMEOUT_SECONDS" &&
       is_decimal_integer "$HEALTHCHECK_REQUEST_TIMEOUT_SECONDS"; then
        connect_timeout=$((10#${HEALTHCHECK_CONNECT_TIMEOUT_SECONDS}))
        request_timeout=$((10#${HEALTHCHECK_REQUEST_TIMEOUT_SECONDS}))

        if (( connect_timeout > request_timeout )); then
            validation_error \
                "HEALTHCHECK_CONNECT_TIMEOUT_SECONDS must not exceed HEALTHCHECK_REQUEST_TIMEOUT_SECONDS."
            failed=1
        fi
    fi

    case "$operation" in
        deploy)
            validate_git_ref "$requested_ref" || failed=1
            ;;
        rollback|status)
            ;;
        *)
            validation_error "Unknown operation '${operation}'."
            failed=1
            ;;
    esac

    if (( failed != 0 )); then
        return 2
    fi

    return 0
}