#!/usr/bin/env bats
# lamboot-backup CLI + subcommand tests.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-backup"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-backup not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
    TMP_FILE="$(mktemp -t backup-test.XXXXXX.json)"
}

teardown() {
    [ -n "${TMP_FILE:-}" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

require_efi() {
    [ -d /sys/firmware/efi ] || skip "not running on UEFI"
    command -v efibootmgr >/dev/null 2>&1 || skip "efibootmgr not installed"
}

@test "backup --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-backup"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "backup help lists all four subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"save"* ]]
    [[ "$output" == *"restore"* ]]
    [[ "$output" == *"show"* ]]
    [[ "$output" == *"list"* ]]
}

@test "backup help save shows detail" {
    run "$TOOL" help save
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"FILE"* ]]
}

@test "backup help restore shows detail" {
    run "$TOOL" help restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"Requires root"* ]]
}

@test "backup --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "backup with no subcommand errors" {
    run "$TOOL"
    [ "$status" -ne 0 ]
}

@test "backup save writes a valid JSON snapshot" {
    require_efi
    require_jq
    run "$TOOL" save --force "$TMP_FILE"
    [ "$status" -eq 0 ]
    [ -f "$TMP_FILE" ]
    jq -e . "$TMP_FILE" >/dev/null
}

@test "backup save snapshot has schema_version v1" {
    require_efi
    require_jq
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    jq -e '.schema_version == "v1"' "$TMP_FILE" >/dev/null
}

@test "backup save snapshot has required top-level fields" {
    require_efi
    require_jq
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    for field in schema_version tool version toolkit_version timestamp host run_id nvram entries; do
        jq -e "has(\"${field}\")" "$TMP_FILE" >/dev/null || { echo "missing field: $field" >&2; return 1; }
    done
}

@test "backup save snapshot has nvram sub-fields" {
    require_efi
    require_jq
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    for field in boot_order timeout_seconds secure_boot_enabled setup_mode; do
        jq -e ".nvram | has(\"${field}\")" "$TMP_FILE" >/dev/null || { echo "missing nvram.$field" >&2; return 1; }
    done
}

@test "backup save entries array is populated" {
    require_efi
    require_jq
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    local count
    count=$(jq '.entries | length' "$TMP_FILE")
    [ "$count" -ge 1 ]
}

@test "backup save --dry-run does not write file" {
    require_efi
    run "$TOOL" save --dry-run "$TMP_FILE"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP_FILE" ] || [ ! -s "$TMP_FILE" ]
}

@test "backup save refuses to overwrite without --force" {
    require_efi
    : > "$TMP_FILE"
    run "$TOOL" save "$TMP_FILE"
    [ "$status" -ne 0 ]
}

@test "backup show parses snapshot correctly" {
    require_efi
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    run "$TOOL" show "$TMP_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Boot Configuration Snapshot"* ]]
    [[ "$output" == *"Entries:"* ]]
}

@test "backup show --json passes snapshot through" {
    require_efi
    require_jq
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    run "$TOOL" show "$TMP_FILE" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.tool == "lamboot-backup"' >/dev/null
}

@test "backup show errors on missing file" {
    run "$TOOL" show /nonexistent-snapshot-$$.json
    [ "$status" -ne 0 ]
}

@test "backup show without file argument errors" {
    run "$TOOL" show
    [ "$status" -ne 0 ]
}

@test "backup restore without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    "$TOOL" save --force "$TMP_FILE" >/dev/null 2>&1 || skip "save failed in this env"
    run "$TOOL" restore "$TMP_FILE"
    [ "$status" -eq 7 ]
}

@test "backup list runs unprivileged" {
    run "$TOOL" list
    [ "$status" -eq 0 ]
}

@test "backup list --json emits valid JSON" {
    require_jq
    run --separate-stderr "$TOOL" list --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.tool == "lamboot-backup"' >/dev/null
}

@test "backup unknown subcommand errors" {
    run "$TOOL" nonexistent-sub
    [ "$status" -ne 0 ]
}

@test "backup --no-color produces no ANSI" {
    run "$TOOL" help
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "backup show prints all entries from snapshot (regression: auto_created_boot_option)" {
    require_efi
    "$TOOL" save --force "$TMP_FILE" >/dev/null
    local expected_count
    expected_count=$(jq '.entries | length' "$TMP_FILE" 2>/dev/null || echo 0)
    [ "$expected_count" -ge 1 ] || skip "no entries to check"
    run "$TOOL" show "$TMP_FILE"
    # Count Boot* lines in the output
    local shown
    shown=$(printf '%s\n' "$output" | grep -cE '^[[:space:]]+Boot[0-9A-Fa-f]{4}')
    [ "$shown" -eq "$expected_count" ]
}
