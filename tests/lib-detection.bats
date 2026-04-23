#!/usr/bin/env bats
# Detection functions — read-only, safe to run anywhere.

setup() {
    LIB="$BATS_TEST_DIRNAME/../lib/lamboot-toolkit-lib.sh"
    # shellcheck source=../lib/lamboot-toolkit-lib.sh
    source "$LIB"
}

@test "detect_boot_mode returns uefi or bios" {
    result=$(detect_boot_mode)
    [[ "$result" == "uefi" || "$result" == "bios" ]]
}

@test "detect_distro returns non-empty" {
    result=$(detect_distro)
    [ -n "$result" ]
}

@test "detect_distro_version returns non-empty" {
    result=$(detect_distro_version)
    [ -n "$result" ]
}

@test "list_bootloaders succeeds or skips (depends on ESP)" {
    if ! detect_esp >/dev/null 2>&1; then
        skip "no ESP on this system"
    fi
    list_bootloaders
}
