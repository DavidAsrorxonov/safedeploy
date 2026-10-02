#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

repository_root="${1:-}"
test_root=""
application_root=""
holder_pid=""

if [[ -z "$repository_root" ||
      ! -f "${repository_root}/lib/lock.sh" ]]; then
    printf '%s\n' \
        "Usage: lock-smoke.sh <safedeploy-repository-root>" >&2
    exit 2
fi

cleanup() {
    if [[ -n "$holder_pid" ]]; then
        wait "$holder_pid" 2>/dev/null || true
    fi

    case "$test_root" in
        /tmp/*|/var/tmp/*)
            rm -rf -- "$test_root"
            ;;
    esac
}

trap cleanup EXIT

test_root="$(mktemp -d)"
application_root="${test_root}/application"

mkdir -p "$application_root"

# shellcheck source=lib/lock.sh
source "${repository_root}/lib/lock.sh"

canonicalize_remote_root "$application_root"
prepare_remote_lock_layout

lock_inode_before="$(stat -c '%i' "$SAFEDEPLOY_LOCK_FILE")"

acquire_deploy_lock \
    "attempt-initial" \
    "deploy" \
    "test" \
    "tester" \
    "controller-initial"

jq -e '
    .schema_version == 1 and
    .attempt_id == "attempt-initial" and
    .operation == "deploy" and
    (.remote_process.pid | type == "number")
' "$SAFEDEPLOY_OWNER_FILE" >/dev/null

owner_mode="$(stat -c '%a' "$SAFEDEPLOY_OWNER_FILE")"
lock_mode="$(stat -c '%a' "$SAFEDEPLOY_LOCK_FILE")"

[[ "$owner_mode" == "600" ]]
[[ "$lock_mode" == "600" ]]

release_deploy_lock

[[ -f "$SAFEDEPLOY_LOCK_FILE" ]]
[[ ! -e "$SAFEDEPLOY_OWNER_FILE" ]]

lock_inode_after="$(stat -c '%i' "$SAFEDEPLOY_LOCK_FILE")"
[[ "$lock_inode_before" == "$lock_inode_after" ]]

ready_file="${test_root}/holder-ready"

(
    trap - EXIT

    # shellcheck source=lib/lock.sh
    source "${repository_root}/lib/lock.sh"

    canonicalize_remote_root "$application_root"
    prepare_remote_lock_layout

    acquire_deploy_lock \
        "attempt-holder" \
        "deploy" \
        "test" \
        "tester" \
        "controller-holder"

    : > "$ready_file"
    sleep 2

    release_deploy_lock
) &

holder_pid="$!"

for ((attempt = 0; attempt < 50; attempt++)); do
    if [[ -f "$ready_file" ]]; then
        break
    fi

    sleep 0.1
done

if [[ ! -f "$ready_file" ]]; then
    printf '%s\n' "Lock holder did not become ready." >&2
    exit 1
fi

contender_status=0

acquire_deploy_lock \
    "attempt-contender" \
    "rollback" \
    "test" \
    "tester" \
    "controller-contender" ||
    contender_status=$?

[[ "$contender_status" -eq 75 ]]

wait "$holder_pid"
holder_pid=""

acquire_deploy_lock \
    "attempt-after-release" \
    "rollback" \
    "test" \
    "tester" \
    "controller-after-release"

release_deploy_lock

printf '%s\n' "lock-smoke-ok"