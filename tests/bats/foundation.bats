#!/usr/bin/env bats

setup() {
    TEST_ROOT="$(
        cd "$(dirname "$BATS_TEST_FILENAME")/../.." &&
        pwd -P
    )"

    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$MOCK_BIN"

    cat > "${MOCK_BIN}/ssh" <<'MOCK_SSH'
#!/usr/bin/env bash

last_argument=""

for last_argument in "$@"; do
    :
done

if [[ -n "${MOCK_SSH_CAPTURE_COMMAND:-}" ]]; then
    printf '%s' "$last_argument" > "$MOCK_SSH_CAPTURE_COMMAND"
fi

if [[ -n "${MOCK_SSH_CAPTURE_STDIN:-}" ]]; then
    cat > "$MOCK_SSH_CAPTURE_STDIN"
else
    cat >/dev/null
fi

exit "${MOCK_SSH_EXIT_CODE:-0}"
MOCK_SSH

    chmod +x "${MOCK_BIN}/ssh"
}

teardown() {
    rm -f -- "${TEST_ROOT}"/logs/deploy-test-*.log
}

@test "help exits successfully without loading configuration" {
    run "${TEST_ROOT}/deploy.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "deploy arguments produce deploy CLI state" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli \
            --env test \
            --ref main \
            --dry-run \
            --skip-healthcheck \
            --no-rollback

        printf "%s|%s|%s|%s|%s|%s\n" \
            "$CLI_OPERATION" \
            "$CLI_ENV" \
            "$CLI_REF" \
            "$CLI_DRY_RUN" \
            "$CLI_SKIP_HEALTHCHECK" \
            "$CLI_NO_ROLLBACK"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "deploy|test|main|true|true|true" ]
}

@test "deployment requires a ref" {
    run "${TEST_ROOT}/deploy.sh" --env test

    [ "$status" -eq 2 ]
    [[ "$output" == *"--ref is required for deployment"* ]]
}

@test "rollback rejects deployment-only options" {
    run "${TEST_ROOT}/deploy.sh" \
        --env test \
        --rollback \
        --skip-healthcheck

    [ "$status" -eq 2 ]
    [[ "$output" == *"--skip-healthcheck cannot be used with --rollback"* ]]
}

@test "status rejects dry-run" {
    run "${TEST_ROOT}/deploy.sh" \
        --env test \
        --status \
        --dry-run

    [ "$status" -eq 2 ]
    [[ "$output" == *"--dry-run cannot be used with --status"* ]]
}

@test "configuration precedence applies CLI override last" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main --no-rollback
        load_configuration "$CLI_ENV"

        printf "%s|%s|%s\n" \
            "$CONFIG_ENVIRONMENT" \
            "$HEALTHCHECK_MAX_ATTEMPTS" \
            "$AUTO_ROLLBACK"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "test|7|false" ]
}

@test "unsafe environment selector is rejected" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env ../test --ref main
        load_configuration "$CLI_ENV"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid environment name"* ]]
}

@test "missing environment configuration is rejected" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env missing-environment --ref main
        load_configuration "$CLI_ENV"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Environment configuration is missing or unreadable"* ]]
}

@test "valid test configuration passes validation" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main
        load_configuration "$CLI_ENV"
        validate_configuration "$CLI_OPERATION" "$CLI_REF"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 0 ]
}

@test "validation reports multiple invalid values" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main
        load_configuration "$CLI_ENV"

        REMOTE_PATH="relative/path"
        HEALTHCHECK_MAX_ATTEMPTS="invalid"

        validate_configuration "$CLI_OPERATION" "$CLI_REF"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 2 ]
    [[ "$output" == *"REMOTE_PATH must be an absolute path"* ]]
    [[ "$output" == *"HEALTHCHECK_MAX_ATTEMPTS must be a decimal integer"* ]]
}

@test "invalid webhook URL is rejected without command errors" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main
        load_configuration "$CLI_ENV"

        SLACK_WEBHOOK_URL="http://hooks.example.test/secret"

        validate_configuration "$CLI_OPERATION" "$CLI_REF"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 2 ]
    [[ "$output" == *"SLACK_WEBHOOK_URL must begin with https://"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "invalid Git ref is rejected" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref "bad ref"
        load_configuration "$CLI_ENV"
        validate_configuration "$CLI_OPERATION" "$CLI_REF"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid Git branch, tag or commit value"* ]]
}

@test "structured logging produces valid redacted private JSON" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main
        load_configuration "$CLI_ENV"
        validate_configuration "$CLI_OPERATION" "$CLI_REF"

        SLACK_WEBHOOK_URL="https://hooks.example.test/secret-token"
        REPOSITORY_URL="https://repository-secret@example.test/app.git"

        initialize_logging "$CLI_ENV"

        log_event \
            "INFO" \
            "$CLI_OPERATION" \
            "test" \
            "success" \
            0 \
            "webhook=${SLACK_WEBHOOK_URL} repository=${REPOSITORY_URL}"

        jq -e . "$SAFEDEPLOY_LOG_FILE" >/dev/null

        if grep -F "secret-token" "$SAFEDEPLOY_LOG_FILE" >/dev/null; then
            exit 1
        fi

        if grep -F "repository-secret" "$SAFEDEPLOY_LOG_FILE" >/dev/null; then
            exit 1
        fi

        if mode="$(stat -f "%Lp" "$SAFEDEPLOY_LOG_FILE" 2>/dev/null)"; then
            :
        else
            mode="$(stat -c "%a" "$SAFEDEPLOY_LOG_FILE")"
        fi

        [[ "$mode" == "600" ]]
        grep -F "[REDACTED]" "$SAFEDEPLOY_LOG_FILE" >/dev/null

        printf "%s\n" "logging-ok"
    ' _ "$TEST_ROOT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"logging-ok"* ]]
    [[ "$output" != *"secret-token"* ]]
    [[ "$output" != *"repository-secret"* ]]
}

@test "SSH argument encoding preserves hostile text as data" {
    run bash -c '
        source "$1/deploy.sh"

        dangerous_value=$'\''line one; $(printf injected)\nline two\n'\''
        encoded_value="$(encode_ssh_argument "$dangerous_value")"
        decoder_script="$2/decoder-test.sh"

        {
            emit_remote_argument_decoder

            cat <<'\''ROUND_TRIP'\''
printf "%s" "$1" |
    base64 |
    tr -d "\r\n"
ROUND_TRIP
        } > "$decoder_script"

        decoded_encoding="$(bash "$decoder_script" "$encoded_value")"

        [[ "x${decoded_encoding}" == "$encoded_value" ]]
        printf "%s\n" "round-trip-ok"
    ' _ "$TEST_ROOT" "$BATS_TEST_TMPDIR"

    [ "$status" -eq 0 ]
    [ "$output" = "round-trip-ok" ]
}

@test "SSH control directory is private and removed by cleanup" {
    run bash -c '
        source "$1/deploy.sh"

        parse_cli --env test --ref main
        load_configuration "$CLI_ENV"
        validate_configuration "$CLI_OPERATION" "$CLI_REF"

        export TMPDIR="$2"

        initialize_ssh

        control_directory="$SAFEDEPLOY_SSH_CONTROL_DIR"

        [[ -d "$control_directory" ]]

        if mode="$(stat -f "%Lp" "$control_directory" 2>/dev/null)"; then
            :
        else
            mode="$(stat -c "%a" "$control_directory")"
        fi

        [[ "$mode" == "700" ]]

        cleanup_ssh
        [[ ! -e "$control_directory" ]]

        printf "%s\n" "cleanup-ok"
    ' _ "$TEST_ROOT" "$BATS_TEST_TMPDIR"

    [ "$status" -eq 0 ]
    [ "$output" = "cleanup-ok" ]
}


@test "remote command contains encoded arguments only" {
    command_capture="${BATS_TEST_TMPDIR}/remote-command"
    stdin_capture="${BATS_TEST_TMPDIR}/remote-stdin"
    dangerous_value='value with spaces; $(printf injected)'

    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        MOCK_SSH_CAPTURE_COMMAND="$command_capture" \
        MOCK_SSH_CAPTURE_STDIN="$stdin_capture" \
        bash -c '
            source "$1/deploy.sh"

            parse_cli --env test --ref main
            load_configuration "$CLI_ENV"
            validate_configuration "$CLI_OPERATION" "$CLI_REF"

            export TMPDIR="$2"

            initialize_ssh
            ssh_run_script \
                "$1/remote/check-prerequisites.sh" \
                "$3"
            cleanup_ssh
        ' _ "$TEST_ROOT" "$BATS_TEST_TMPDIR" "$dangerous_value"

    [ "$status" -eq 0 ]

    remote_command="$(cat "$command_capture")"

    [[ "$remote_command" != *"$dangerous_value"* ]]
    [[ "$remote_command" =~ ^bash\ -s\ --\ x[a-zA-Z0-9+/=]+$ ]]

    grep -F "safedeploy-preflight-ok" "$stdin_capture" >/dev/null
}

@test "main deploy path succeeds through mocked SSH preflight" {
    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        TMPDIR="$BATS_TEST_TMPDIR" \
        "${TEST_ROOT}/deploy.sh" \
        --env test \
        --ref main

    # Execution stops at the intentional not-implemented placeholder.
    [ "$status" -eq 1 ]
    [[ "$output" == *"Configuration loaded and validated"* ]]
    [[ "$output" == *"SSH connectivity and remote prerequisites validated"* ]]
    [[ "$output" == *"deploy execution is not implemented yet"* ]]
}

@test "SSH failure returns an operational failure" {
    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        TMPDIR="$BATS_TEST_TMPDIR" \
        MOCK_SSH_EXIT_CODE=255 \
        "${TEST_ROOT}/deploy.sh" \
        --env test \
        --ref main

    [ "$status" -eq 1 ]
    [[ "$output" == *"SSH connectivity or remote prerequisite validation failed"* ]]
}

@test "rollback wrapper selects rollback operation" {
    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        TMPDIR="$BATS_TEST_TMPDIR" \
        "${TEST_ROOT}/rollback.sh" \
        --env test

    [ "$status" -eq 1 ]
    [[ "$output" == *"rollback execution is not implemented yet"* ]]
}

@test "status wrapper selects status operation" {
    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        TMPDIR="$BATS_TEST_TMPDIR" \
        "${TEST_ROOT}/status.sh" \
        --env test

    [ "$status" -eq 1 ]
    [[ "$output" == *"status execution is not implemented yet"* ]]
}