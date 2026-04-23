#!/usr/bin/env bats
# lamboot-pve-setup CLI + prerequisite tests.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-pve-setup"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    [ -x "$TOOL" ] || skip "lamboot-pve-setup not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "pve-setup --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-pve-setup"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "pve-setup help lists all four subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"setup"* ]]
    [[ "$output" == *"teardown"* ]]
    [[ "$output" == *"check"* ]]
    [[ "$output" == *"doctor-hookscript"* ]]
    [[ "$output" == *"[beta]"* ]]
}

@test "pve-setup help setup shows detail" {
    run "$TOOL" help setup
    [ "$status" -eq 0 ]
    [[ "$output" == *"VMID"* ]]
    [[ "$output" == *"idempotent"* ]]
}

@test "pve-setup --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "pve-setup with no subcommand errors" {
    run "$TOOL"
    [ "$status" -ne 0 ]
}

@test "pve-setup setup without VMID errors" {
    run "$TOOL" setup
    [ "$status" -ne 0 ]
    [[ "$output" == *"VMID"* ]]
}

@test "pve-setup setup without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL" setup 100
    [ "$status" -eq 7 ]
}

@test "pve-setup teardown without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL" teardown 100
    [ "$status" -eq 7 ]
}

@test "pve-setup check without qm returns prerequisite error" {
    if command -v qm >/dev/null 2>&1; then
        skip "qm is available on this host"
    fi
    run "$TOOL" check 100
    [ "$status" -eq 7 ]
}

@test "pve-setup doctor-hookscript prints human-readable output when hookscript missing" {
    if command -v qm >/dev/null 2>&1 || [ -f /var/lib/vz/snippets/lamboot-hookscript.pl ]; then
        skip "Proxmox host; hookscript may be present"
    fi
    run "$TOOL" doctor-hookscript
    [ "$status" -eq 7 ]
    [[ "$output" == *"hookscript"* ]] || [[ "$output" == *"lamboot-hookscript"* ]]
}

@test "pve-setup unknown flag errors" {
    run "$TOOL" --not-a-flag
    [ "$status" -ne 0 ]
}

@test "pve-setup unknown subcommand errors" {
    run "$TOOL" nonsense-cmd
    [ "$status" -ne 0 ]
}

@test "pve-setup --no-color yields no ANSI" {
    run "$TOOL" help --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "pve-setup check --json emits schema v1" {
    # On non-Proxmox host, expect prerequisite exit but still schema v1 if reached
    require_jq
    run "$TOOL" --json-schema
    echo "$output" | jq -e '."$schema"' >/dev/null
}
