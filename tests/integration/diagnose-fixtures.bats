#!/usr/bin/env bats
# Integration tests: lamboot-diagnose --offline against fixture disks.
#
# These tests verify end-to-end offline-mode behavior against real disk
# image layouts. Require fixtures; skip when not present.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../../tools/lamboot-diagnose"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    FIXTURES_DIR="$BATS_TEST_DIRNAME/../fixtures"
    [ -x "$TOOL" ] || skip "lamboot-diagnose not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_root_for_offline() {
    [ "$EUID" -eq 0 ] || skip "offline mode needs root (losetup)"
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

@test "diagnose --offline on clean-uefi-gpt reports healthy" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture clean-uefi-gpt.raw)

    run "$TOOL" --offline "$f" --json
    [ "$status" -eq 0 ]
    # Healthy system → no critical findings
    local crit
    crit=$(echo "$output" | jq '.summary.findings_by_severity.critical')
    [ "$crit" -eq 0 ]
}

@test "diagnose --offline on no-esp fixture emits esp.mounted critical" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture no-esp.raw)

    run "$TOOL" --offline "$f" --json
    # EXIT_PARTIAL (2) or any non-1 exit is acceptable; finding is what matters
    [ "$status" -ne 1 ]
    echo "$output" | jq -e '.findings[] | select(.id == "esp.mounted" and .severity == "critical")' >/dev/null
}

@test "diagnose --offline on full-esp fixture emits esp.free_space" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture full-esp.raw)

    run "$TOOL" --offline "$f" --json
    echo "$output" | jq -e '.findings[] | select(.id == "esp.free_space" and (.severity == "warning" or .severity == "error"))' >/dev/null
}

@test "diagnose --offline on lamboot-installed detects LamBoot" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture lamboot-installed.raw)

    run "$TOOL" --offline "$f" --json
    # Bootloader finding for lamboot should be present
    echo "$output" | jq -e '.findings[] | select(.id == "bootloader.lamboot.present")' >/dev/null
}

@test "diagnose --offline on grub-installed detects GRUB" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture grub-installed.raw)

    run "$TOOL" --offline "$f" --json
    echo "$output" | jq -e '.findings[] | select(.id == "bootloader.grub.present")' >/dev/null
}

@test "diagnose --offline on sdboot-installed detects systemd-boot" {
    require_root_for_offline
    require_jq
    local f
    f=$(fixture sdboot-installed.raw)

    run "$TOOL" --offline "$f" --json
    echo "$output" | jq -e '.findings[] | select(.id == "bootloader.systemd-boot.present")' >/dev/null
}
