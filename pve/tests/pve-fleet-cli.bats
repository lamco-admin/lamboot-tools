#!/usr/bin/env bats
# lamboot-pve-fleet CLI tests.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-pve-fleet"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    [ -x "$TOOL" ] || skip "lamboot-pve-fleet not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "pve-fleet --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-pve-fleet"* ]]
}

@test "pve-fleet help lists all four subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"inventory"* ]]
    [[ "$output" == *"setup"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"report"* ]]
    [[ "$output" == *"[experimental]"* ]]
}

@test "pve-fleet help setup documents filter flags" {
    run "$TOOL" help setup
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
    [[ "$output" == *"--vmid"* ]]
    [[ "$output" == *"--tag"* ]]
    [[ "$output" == *"--exclude"* ]]
}

@test "pve-fleet --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "pve-fleet with no subcommand errors" {
    run "$TOOL"
    [ "$status" -ne 0 ]
}

@test "pve-fleet without qm returns prerequisite error" {
    if command -v qm >/dev/null 2>&1; then
        skip "qm is available"
    fi
    run "$TOOL" inventory
    [ "$status" -eq 7 ]
}

@test "pve-fleet setup requires --all / --vmid / --tag" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL" setup
    # Without root: EXIT_PREREQUISITE; or with root: error about missing filter
    [ "$status" -ne 0 ]
}

@test "pve-fleet unknown flag errors" {
    run "$TOOL" --not-a-flag
    [ "$status" -ne 0 ]
}

@test "pve-fleet unknown subcommand errors" {
    run "$TOOL" nonsense
    [ "$status" -ne 0 ]
}

@test "pve-fleet --no-color yields no ANSI" {
    run "$TOOL" help --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}
