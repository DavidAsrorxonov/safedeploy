# shellcheck shell=bash

config_error() {
    local message="$1"

    printf 'Configuration error: %s\n' "$message" >&2
    return 2
}

is_safe_environment_selector() {
    local selector="$1"
    local LC_ALL=C
    
    [[ "$selector" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]
}

set_config_defaults() {
    REMOTE_HOST=""
    REMOTE_PATH=""
    REPOSITORY_URL=""

    INSTALL_CMD=""
    BUILD_CMD=""
    PREPARE_COMMAND_TIMEOUT_SECONDS=600

    SERVICE_NAME=""
    RESTART_CMD=""
    STOP_CMD=""
    CHECK_STOPPED_CMD=""
    SERVICE_COMMAND_TIMEOUT_SECONDS=60

    HEALTHCHECK_URL=""
    HEALTHCHECK_EXPECT_STATUS=200
    HEALTHCHECK_EXPECT_BODY=""
    HEALTHCHECK_REQUIRE_RELEASE_ID=false
    HEALTHCHECK_MAX_ATTEMPTS=10
    HEALTHCHECK_INTERVAL_SECONDS=1
    HEALTHCHECK_MAX_INTERVAL_SECONDS=10
    HEALTHCHECK_CONNECT_TIMEOUT_SECONDS=2
    HEALTHCHECK_REQUEST_TIMEOUT_SECONDS=5
    HEALTHCHECK_DEADLINE_SECONDS=60
    ROLLBACK_HEALTHCHECK_DEADLINE_SECONDS=60

    SSH_CONNECT_TIMEOUT_SECONDS=10
    SSH_SERVER_ALIVE_INTERVAL_SECONDS=15
    SSH_SERVER_ALIVE_COUNT_MAX=3

    HOOK_TIMEOUT_SECONDS=60
    NOTIFY_TIMEOUT_SECONDS=10
    COMMAND_KILL_GRACE_SECONDS=5

    LOG_RETENTION_DAYS=30
    RELEASES_TO_KEEP=5
    AUTO_ROLLBACK=true

    SLACK_WEBHOOK_URL=""
    NOTIFY_ON_SUCCESS=true
    NOTIFY_ON_FAILURE=true
    NOTIFY_ON_UNVERIFIED=true

    CONFIG_ENVIRONMENT=""
    CONFIG_FILE=""
}

validate_config_syntax() {
    local config_path="$1"

    if ! bash -n "$config_path"; then
        config_error "Invalid Bash syntax in ${config_path}."
        return 2
    fi

    return 0
}

source_config_file() {
    local config_path="$1"

    validate_config_syntax "$config_path" || return $?

    # Configuration files are trusted Bash assignment files.
    # shellcheck disable=SC1090
    source "$config_path" || {
        config_error "Unable to load ${config_path}."
        return 2
    }

    return 0
}

apply_cli_config_overrides() {
    local no_rollback_override="$1"

    if [[ "$no_rollback_override" == true ]]; then
        AUTO_ROLLBACK=false
    fi
}

load_configuration() {
    local environment_name="$1"
    local global_config="${SAFEDEPLOY_ROOT}/deploy.conf"
    local environment_config=""
    local no_rollback_override="${CLI_NO_ROLLBACK:-false}"

    if ! is_safe_environment_selector "$environment_name"; then
        config_error \
            "Invalid environment name: '${environment_name}'. Use letters, numbers, underscores and hyphens only."
        return 2
    fi

    environment_config="${SAFEDEPLOY_CONFIG_DIR}/${environment_name}.env"

    if [[ ! -f "$global_config" || ! -r "$global_config" ]]; then
        config_error \
        "Global configuration is missing or unreadable: ${global_config}"
        return 2
    fi

    if [[ ! -f "$environment_config" || ! -r "$environment_config" ]]; then
        config_error \
            "Environment configuration is missing or unreadable: ${environment_config}"
        return 2
    fi

    set_config_defaults

    source_config_file "$global_config" || return $?
    source_config_file "$environment_config" || return $?

    apply_cli_config_overrides "$no_rollback_override"

    CONFIG_ENVIRONMENT="$environment_name"
    CONFIG_FILE="$environment_config"

    return 0
}