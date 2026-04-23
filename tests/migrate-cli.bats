#!/usr/bin/env bats
# lamboot-migrate CLI tests — unprivileged paths only.
#
# Integration tests that require root + block devices live in
# tests/integration-migrate.bats and use fixture disk images.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-migrate"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-migrate not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "migrate --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-migrate"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "migrate --help shows structured help" {
    run "$TOOL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"subcommand reference"* ]] || [[ "$output" == *"SUBCOMMANDS"* ]] || [[ "$output" == *"Migration"* ]]
}

@test "migrate with no args fails with subcommand hint" {
    run "$TOOL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"subcommand"* ]]
}

@test "migrate help lists five subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"to-uefi"* ]]
    [[ "$output" == *"to-lamboot"* ]]
    [[ "$output" == *"verify"* ]]
    [[ "$output" == *"rollback"* ]]
    [[ "$output" == *"status"* ]]
}

@test "migrate help to-uefi shows detail" {
    run "$TOOL" help to-uefi
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"EXAMPLES"* ]]
    [[ "$output" == *"NOTES"* ]]
    [[ "$output" == *"Requires root"* ]]
}

@test "migrate help rollback shows detail" {
    run "$TOOL" help rollback
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup"* ]]
}

@test "migrate help with unknown subcommand errors" {
    run "$TOOL" help nonexistent-thing
    [ "$status" -ne 0 ]
}

@test "migrate status runs unprivileged and succeeds" {
    run "$TOOL" status
    [ "$status" -eq 0 ]
}

@test "migrate status --json emits valid JSON" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
}

@test "migrate status --json contains schema_version v1" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
}

@test "migrate status --json contains boot_mode finding" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.findings[] | select(.id == "migrate.status.boot_mode")' >/dev/null
}

@test "migrate status --json reports the correct tool name" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    echo "$output" | jq -e '.tool == "lamboot-migrate"' >/dev/null
}

@test "migrate to-uefi without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root; cannot test refusal"
    run "$TOOL" to-uefi
    [ "$status" -eq 7 ]  # EXIT_PREREQUISITE
}

@test "migrate rollback without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root; cannot test refusal"
    run "$TOOL" rollback
    [ "$status" -eq 7 ]
}

@test "migrate to-lamboot without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root; cannot test refusal"
    run "$TOOL" to-lamboot
    [ "$status" -eq 7 ]
}

@test "migrate verify runs unprivileged (read-only)" {
    run "$TOOL" verify
    # Exit is 0 (all pass) or 2 (partial — expected on dev machines that aren't
    # in post-migration state). Must not be prerequisite_missing or error.
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "migrate verify --json produces findings for 11 checks" {
    require_jq
    run --separate-stderr "$TOOL" verify --json
    # Status may be 0 or 2
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
    local count
    count=$(echo "$output" | jq '.findings | length')
    # Allow for skipped checks that consolidate, but expect close to 11
    [ "$count" -ge 9 ]
    [ "$count" -le 12 ]
}

@test "migrate --json-schema prints a schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "migrate unknown subcommand fails cleanly" {
    run "$TOOL" banana
    [ "$status" -ne 0 ]
}

@test "migrate accepts --verbose" {
    run "$TOOL" status --verbose
    [ "$status" -eq 0 ]
}

@test "migrate accepts --quiet" {
    run "$TOOL" status --quiet
    [ "$status" -eq 0 ]
}

@test "migrate accepts --no-color" {
    run "$TOOL" status --no-color
    [ "$status" -eq 0 ]
    # --no-color output should have no ANSI escape sequences
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        echo "found ANSI escape in --no-color output" >&2
        return 1
    fi
}
