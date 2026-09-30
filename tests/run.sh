#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &&
    pwd -P
)" || {
    printf '%s\n' "Unable to determine the repository root." >&2
    exit 1
}

if ! command -v bats >/dev/null 2>&1; then
    printf '%s\n' "bats-core is required to run the test suite." >&2
    exit 2
fi

if ! command -v shellcheck >/dev/null 2>&1; then
    printf '%s\n' "ShellCheck is required to run the test suite." >&2
    exit 2
fi

cd "$TEST_ROOT"

bash -n \
    deploy.sh \
    rollback.sh \
    status.sh \
    deploy.conf \
    config/config.example.env \
    config/test.env \
    lib/*.sh \
    remote/*.sh \
    tests/run.sh


shellcheck -x \
    deploy.sh \
    rollback.sh \
    status.sh \
    remote/*.sh \
    tests/run.sh

bats tests/bats