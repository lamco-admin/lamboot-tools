#!/usr/bin/env bats
# Integration tests: lamboot-esp against fixture disks.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../../tools/lamboot-esp"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    FIXTURES_DIR="$BATS_TEST_DIRNAME/../fixtures"
    [ -x "$TOOL" ] || skip "lamboot-esp not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_root_for_offline() {
    [ "$EUID" -eq 0 ] || skip "offline mode needs root"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

fixture() {
    local name="$1"
    local path="$FIXTURES_DIR/$name"
    [ -f "$path" ] || skip "fixture not present: $name"
    printf '%s' "$path"
}

@test "esp check --offline on full-esp emits space error" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture full-esp.raw)

    run "$TOOL" check --offline "$f" --json
    echo "$output" | jq -e '.findings[] | select(.id == "esp.filesystem.space" and .severity == "error")' >/dev/null
}

@test "esp check --offline on corrupted-esp-fat emits integrity warning" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture corrupted-esp-fat.raw)

    run "$TOOL" check --offline "$f" --json
    echo "$output" | jq -e '.findings[] | select(.id == "esp.filesystem.integrity" and .severity == "warning")' >/dev/null
}

@test "esp inventory --offline on lamboot-installed lists bootloader" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture lamboot-installed.raw)

    run "$TOOL" inventory --offline "$f" --json
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | jq '[.findings[] | select(.category == "esp_inventory")] | length')
    [ "$count" -gt 0 ]
}
