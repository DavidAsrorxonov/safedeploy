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

# shellcheck source=lib/config.sh
source "${SAFEDEPLOY_LIB_DIR}/config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./deploy.sh --env <name> --ref <branch|tag|sha> [deploy-options]
  ./deploy.sh --env <name> --rollback [--dry-run]
  ./deploy.sh --env <name> --status

Common options:
  --env <name>              Environment configuration selector
  --dry-run                 Show proposed actions without changing the target
  -h, --help                Show this help message

Deployment options:
  --ref <ref>               Git branch, tag, or commit to deploy
  --skip-healthcheck        Activate the release as unverified
  --no-rollback             Disable automatic recovery for this deployment

Other operations:
  --rollback                Restore a preceding verified release (this cmd rolls back only a verified release)
  --status                  Report deployment state and health
EOF
}

cli_error() {
    local message="$1"

    printf 'Error: %s\n\n' "$message" >&2
    usage >&2

    return 2
}

reset_cli_state() {
    CLI_OPERATION="deploy"
    CLI_ENV=""
    CLI_REF=""
    CLI_DRY_RUN=false
    CLI_SKIP_HEALTHCHECK=false
    CLI_NO_ROLLBACK=false
    CLI_HELP=false

    _CLI_SEEN_ENV=false
    _CLI_SEEN_REF=false
    _CLI_SEEN_DRY_RUN=false
    _CLI_SEEN_SKIP_HEALTHCHECK=false
    _CLI_SEEN_NO_ROLLBACK=false
    _CLI_SEEN_ROLLBACK=false
    _CLI_SEEN_STATUS=false

    _CLI_SEEN_HELP=false
}

require_option_value() {
    local option_name="$1"
    local remaining_count="$2"
    local candidate_value="${3:-}"

    if (( remaining_count < 2 )); then
        cli_error "${option_name} requires a value."
        return 2
    fi

    if [[ -z "$candidate_value" || "$candidate_value" == -* ]]; then
        cli_error "${option_name} requires a non-empty value."
        return 2
    fi

    return 0
}

parse_cli() {
    reset_cli_state

    while (( $# > 0 )); do
        case "$1" in
            --env)
                if [[ "$_CLI_SEEN_ENV" == true ]]; then
                    cli_error "--env may only be provided once."
                    return 2
                fi

                require_option_value "--env" "$#" "${2:-}" || return $?

                CLI_ENV="$2"
                _CLI_SEEN_ENV=true
                shift 2
                ;;

            --ref)
                if [[ "$_CLI_SEEN_REF" == true ]]; then
                    cli_error "--ref may only be provided once."
                    return 2
                fi

                require_option_value "--ref" "$#" "${2:-}" || return $?

                CLI_REF="$2"
                _CLI_SEEN_REF=true
                shift 2
                ;;

            --dry-run)
                if [[ "$_CLI_SEEN_DRY_RUN" == true ]]; then
                    cli_error "--dry-run may only be provided once."
                    return 2
                fi

                CLI_DRY_RUN=true
                _CLI_SEEN_DRY_RUN=true
                shift
                ;;

            --skip-healthcheck)
                if [[ "$_CLI_SEEN_SKIP_HEALTHCHECK" == true ]]; then
                    cli_error "--skip-healthcheck may only be provided once."
                    return 2
                fi

                CLI_SKIP_HEALTHCHECK=true
                _CLI_SEEN_SKIP_HEALTHCHECK=true
                shift
                ;;

            --no-rollback)
                if [[ "$_CLI_SEEN_NO_ROLLBACK" == true ]]; then
                    cli_error "--no-rollback may only be provided once."
                    return 2
                fi

                CLI_NO_ROLLBACK=true
                _CLI_SEEN_NO_ROLLBACK=true
                shift
                ;;

            --rollback)
                if [[ "$_CLI_SEEN_ROLLBACK" == true ]]; then
                    cli_error "--rollback may only be provided once."
                    return 2
                fi

                _CLI_SEEN_ROLLBACK=true
                shift
                ;;

            --status)
                if [[ "$_CLI_SEEN_STATUS" == true ]]; then
                    cli_error "--status may only be provided once."
                    return 2
                fi

                _CLI_SEEN_STATUS=true
                shift
                ;;

            -h|--help)
                if [[ "$_CLI_SEEN_HELP" == true ]]; then
                    cli_error "--help may only be provided once."
                    return 2
                fi

                CLI_HELP=true
                _CLI_SEEN_HELP=true
                shift
                ;;

            --)
                shift

                if (( $# > 0 )); then
                    cli_error "Unexpected positional argument: $1"
                    return 2
                fi

                break
                ;;

            -*)
                cli_error "Unknown option: $1"
                return 2
                ;;

            *)
                cli_error "Unexpected positional argument: $1"
                return 2
                ;;

        esac

    done

    if [[ "$_CLI_SEEN_ROLLBACK" == true &&
          "$_CLI_SEEN_STATUS" == true ]]; then
        cli_error "--rollback and --status cannot be used together."
        return 2
    fi

    if [[ "$_CLI_SEEN_ROLLBACK" == true ]]; then
        CLI_OPERATION="rollback"
    elif [[ "$_CLI_SEEN_STATUS" == true ]]; then
        CLI_OPERATION="status"
    fi

    if [[ "$CLI_HELP" == true ]]; then
        return 0
    fi

    if [[ -z "$CLI_ENV" ]]; then
        cli_error "--env is required."
        return 2
    fi

    case "$CLI_OPERATION" in
        deploy)
            if [[ -z "$CLI_REF" ]]; then
                cli_error "--ref is required for deployment."
                return 2
            fi
            ;;

        rollback)
            if [[ -n "$CLI_REF" ]]; then
                cli_error "--ref cannot be used with --rollback."
                return 2
            fi

            if [[ "$CLI_SKIP_HEALTHCHECK" == true ]]; then
                cli_error "--skip-healthcheck cannot be used with --rollback."
                return 2
            fi

            if [[ "$CLI_NO_ROLLBACK" == true ]]; then
                cli_error "--no-rollback cannot be used with --rollback."
                return 2
            fi
            ;;

        status)
            if [[ -n "$CLI_REF" ]]; then
                cli_error "--ref cannot be used with --status."
                return 2
            fi

            if [[ "$CLI_DRY_RUN" == true ]]; then
                cli_error "--dry-run cannot be used with --status."
                return 2
            fi

            if [[ "$CLI_SKIP_HEALTHCHECK" == true ]]; then
                cli_error "--skip-healthcheck cannot be used with --status."
                return 2
            fi

            if [[ "$CLI_NO_ROLLBACK" == true ]]; then
                cli_error "--no-rollback cannot be used with --status."
                return 2
            fi
            ;;
    esac

    return 0
}

main() {
    local parse_status=0
    local config_status=0

    parse_cli "$@" || parse_status=$?

    if (( parse_status != 0 )); then
        return "$parse_status"
    fi

    if [[ "$CLI_HELP" == true ]]; then
        usage
        return 0 
    fi 

    load_configuration "$CLI_ENV" || config_status=$?

    if (( config_status != 0 )); then
        return "$config_status"
    fi

    printf 'safedeploy: %s configuration loaded for environment %s; execution is not implemented yet.\n' \
        "$CLI_OPERATION" \
        "$CONFIG_ENVIRONMENT" >&2

    return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi